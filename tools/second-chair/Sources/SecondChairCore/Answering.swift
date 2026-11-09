import Foundation

/// Which kind of help you're looking at. Never blended silently.
public enum AnswerLabel: String, Codable, Sendable {
    case grounded = "GROUNDED"
    case synthesized = "SYNTHESIZED"
    case notInDocs = "NOT IN YOUR DOCS"
}

/// A local language model that turns passages into a short spoken answer.
public protocol ModelClient: Sendable {
    var name: String { get }
    func complete(system: String, prompt: String) async throws -> String
}

/// What the overlay shows: the question as heard, the source first, the sayable answer second.
public struct AnswerCard: Sendable {
    public var question: String
    public var label: AnswerLabel
    /// Passages shown verbatim: one for GROUNDED, every passage used for SYNTHESIZED,
    /// the closest one (if worth seeing) for NOT IN YOUR DOCS.
    public var passages: [Hit]
    /// Two or three sentences, or nil while it's being written, or when withheld.
    public var answer: String?
    /// Which path wrote the answer: a model name, or "extract" for sentences lifted from the passage.
    public var answeredBy: String?
    /// Why an answer was withheld (the grounding check failed), shown in small type.
    public var withheld: String?
    public var sourceLatency: TimeInterval = 0
    public var answerLatency: TimeInterval = 0
}

public struct LabelThresholds: Sendable {
    /// One keyword passage covering this share of the question, or an embedding this similar, answers it.
    public var groundedCoverage = 0.6
    public var groundedSimilarity = 0.72
    /// Passages at least this strong count toward a synthesized answer.
    public var supportCoverage = 0.4
    public var supportSimilarity = 0.6
    /// Below this, even the closest passage isn't worth showing.
    public var closestCoverage = 0.25
    public var closestSimilarity = 0.45
    public init() {}
}

/// The grounding check: an answer may only contain figures and names its passages contain.
public enum Grounding {
    public struct Result: Equatable, Sendable {
        public var unsupportedNumbers: [String]
        public var unsupportedNames: [String]
        public var passed: Bool { unsupportedNumbers.isEmpty && unsupportedNames.isEmpty }
        public var reason: String {
            var parts: [String] = []
            if !unsupportedNumbers.isEmpty { parts.append("figure not in your docs: " + unsupportedNumbers.joined(separator: ", ")) }
            if !unsupportedNames.isEmpty { parts.append("name not in your docs: " + unsupportedNames.joined(separator: ", ")) }
            return parts.joined(separator: "; ")
        }
    }

    public static func check(_ answer: String, against passages: [String], question: String = "") -> Result {
        let source = passages.joined(separator: "\n")
        let sourceNumbers = Lexicon.numbers(source).union(Lexicon.numbers(question))
        let numbers = Lexicon.numbers(answer).filter { !sourceNumbers.contains($0) }.sorted()
        let haystack = (source + "\n" + question).lowercased()
        let names = Lexicon.names(answer).filter { !haystack.contains($0.lowercased()) }.sorted()
        return Result(unsupportedNumbers: numbers, unsupportedNames: names)
    }
}

/// Labels a question from what retrieval found, routes it to a model, checks the answer, and
/// reports the source card the moment it's known and the answer when it's ready.
public struct Answerer: Sendable {
    public var fast: ModelClient?
    public var quality: ModelClient?
    public var thresholds = LabelThresholds()

    public init(fast: ModelClient? = nil, quality: ModelClient? = nil) {
        self.fast = fast
        self.quality = quality
    }

    public static let notCovered = "NOT_COVERED"

    public static let system = """
        You help a job candidate during a live interview. You get the interviewer's question and passages \
        from the candidate's own prep documents. Write what the candidate could say: two or three short \
        sentences, first person, spoken style. Use only facts in the passages. Copy every figure and name \
        exactly as it appears in a passage. Never add a figure, name, company, or claim that is not in the \
        passages. If the passages do not answer the question, reply with exactly \(notCovered) and nothing else.
        """

    public func label(_ hits: [Hit]) -> (AnswerLabel, [Hit]) {
        func strong(_ h: Hit) -> Bool {
            h.via == .keyword ? h.coverage >= thresholds.groundedCoverage : h.similarity >= thresholds.groundedSimilarity
        }
        func support(_ h: Hit) -> Bool {
            h.via == .keyword ? h.coverage >= thresholds.supportCoverage : h.similarity >= thresholds.supportSimilarity
        }
        func closest(_ h: Hit) -> Bool {
            h.via == .keyword ? h.coverage >= thresholds.closestCoverage : h.similarity >= thresholds.closestSimilarity
        }
        if let top = hits.first, strong(top) { return (.grounded, [top]) }
        let supporting = hits.filter(support)
        if supporting.count >= 2 { return (.synthesized, Array(supporting.prefix(3))) }
        if let near = hits.first(where: closest) { return (.notInDocs, [near]) }
        return (.notInDocs, [])
    }

    /// `onSource` fires as soon as the label and passages are known; the returned card has the answer.
    public func answer(_ question: String, hits: [Hit], started: Date = Date(),
                       onSource: @Sendable (AnswerCard) -> Void = { _ in }) async -> AnswerCard {
        let (label, passages) = label(hits)
        var card = AnswerCard(question: question, label: label, passages: passages)
        card.sourceLatency = Date().timeIntervalSince(started)
        onSource(card)
        guard label != .notInDocs else { return card }

        let texts = passages.map(\.chunk.text)
        let prompt = "Question: \(question)\n\n" + passages.enumerated().map { i, h in
            "Passage \(i + 1) (\(h.chunk.sourceLine)):\n\(h.chunk.text)"
        }.joined(separator: "\n\n")

        // Grounded and short: the fast path compresses. Synthesized: the quality path builds.
        let route: [ModelClient] = label == .grounded ? [fast, quality].compactMap { $0 } : [quality, fast].compactMap { $0 }
        var lastFailure: String?
        for model in route {
            guard let raw = try? await model.complete(system: Self.system, prompt: prompt) else { continue }
            let reply = Self.clean(raw)
            if reply.contains(Self.notCovered) || reply.isEmpty {
                // The model says the passages don't answer it. Trust the refusal; keep the passage visible.
                card.label = .notInDocs
                card.passages = Array(passages.prefix(1))
                card.answerLatency = Date().timeIntervalSince(started)
                return card
            }
            let check = Grounding.check(reply, against: texts, question: question)
            if check.passed {
                card.answer = reply
                card.answeredBy = model.name
                card.answerLatency = Date().timeIntervalSince(started)
                return card
            }
            lastFailure = check.reason
        }
        if let lastFailure {
            // A checked failure beats an unchecked invention: show the passages alone.
            card.withheld = "Answer withheld (\(lastFailure)). Use the passage."
        } else if label == .grounded {
            // No model on this Mac: lift the most relevant sentences straight from the passage.
            card.answer = Self.extract(question, from: passages[0].chunk.text)
            card.answeredBy = "extract"
        } else {
            card.withheld = "No local model running for a made-on-the-spot answer. Use the passages."
        }
        card.answerLatency = Date().timeIntervalSince(started)
        return card
    }

    /// Strips model chatter: thinking blocks, quotes, labels, and anything past three sentences.
    static func clean(_ raw: String) -> String {
        var s = raw
        while let open = s.range(of: "<think>"), let close = s.range(of: "</think>", range: open.upperBound..<s.endIndex) {
            s.removeSubrange(open.lowerBound..<close.upperBound)
        }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"“”")))
        for prefix in ["Answer:", "Candidate:", "You could say:"] where s.hasPrefix(prefix) {
            s = String(s.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        let sentences = Lexicon.sentences(s.replacingOccurrences(of: "\n", with: " "))
        return sentences.prefix(3).joined(separator: " ")
    }

    /// The sentence (or bullet) that shares the most terms with the question, plus the next best one
    /// only when it's nearly as relevant. Kept in passage order.
    public static func extract(_ question: String, from passage: String) -> String {
        let q = Set(Lexicon.terms(question))
        let sentences = passage.components(separatedBy: "\n")
            .flatMap { Lexicon.sentences($0) }
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "-*•> ").union(.whitespaces)) }
            .filter { !$0.isEmpty }
        guard !sentences.isEmpty else { return passage }
        let scored = sentences.enumerated().map { i, s in (i, Set(Lexicon.terms(s)).intersection(q).count) }
        let ranked = scored.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }
        let best = ranked[0]
        var picked = [best.0]
        if ranked.count > 1, ranked[1].1 >= max(1, Int((Double(best.1) * 0.75).rounded())) { picked.append(ranked[1].0) }
        return picked.sorted().map { sentences[$0] }.joined(separator: " ")
    }
}
