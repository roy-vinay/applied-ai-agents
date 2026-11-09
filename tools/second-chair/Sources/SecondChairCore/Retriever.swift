import Foundation

/// A passage found for a question, with why it was found.
public struct Hit: Sendable, Equatable {
    public enum Via: String, Sendable {
        case keyword, embedding
        /// The question matched one you wrote an answer to.
        case prepared
    }
    public var chunk: Chunk
    /// Share of the question's terms the passage contains (keyword hits), 0...1.
    public var coverage: Double
    /// Cosine similarity (embedding hits), 0...1.
    public var similarity: Double
    public var score: Double
    public var via: Via
    public var primary: Bool

    /// One strength number on a common scale, for labelling and sorting.
    public var strength: Double {
        switch via {
        case .keyword: return coverage
        case .embedding: return similarity
        case .prepared: return max(coverage, similarity)
        }
    }
}

public struct RetrievalSettings: Sendable {
    /// Below this best keyword coverage, keyword search counts as thin and embeddings are tried.
    public var thinCoverage = 0.5
    /// Multiplier on scores of passages in the pinned prep pack.
    public var primaryBoost = 1.6
    /// Weight of terms carried over from the previous question in a follow-up.
    public var followUpWeight = 0.5
    /// How many possible answers to look for. The label uses the best few; the rest are shown as alternatives.
    public var maxHits = 8
    /// A question you wrote counts as the same question when it shares this much of its wording...
    public var preparedOverlap = 0.6
    /// ...or means this nearly the same (embedding similarity, question to question).
    public var preparedSimilarity = 0.8

    public init() {}
}

/// Keyword search first, embeddings only when keyword search is thin, the pinned prep pack first,
/// and the last exchange as context for short follow-ups.
public struct Retriever: Sendable {
    public var index: CorpusIndex
    public var primaryFolder: String?
    public var settings = RetrievalSettings()
    public var embedder: Embedder?

    public init(index: CorpusIndex, primaryFolder: String? = nil, embedder: Embedder? = nil) {
        self.index = index
        self.primaryFolder = primaryFolder
        self.embedder = embedder
    }

    static let followUpCues: Set<String> = ["that", "it", "this", "those", "these", "there", "then", "else",
                                            "more", "why", "how", "example", "again", "instead", "result"]

    /// Is this a follow-up that leans on the previous question ("why was that?", "what happened next")?
    public static func isFollowUp(_ question: String) -> Bool {
        let words = Lexicon.words(question.lowercased())
        // Short and pointing back ("why was that?", "what happened then?"). A short question that names
        // its own subject ("your first 90 days?") stands on its own.
        return words.count <= 8 && words.contains(where: followUpCues.contains) && Lexicon.terms(question).count <= 2
    }

    public func weightedTerms(_ question: String, previous: [String]) -> [String: Double] {
        var weights: [String: Double] = [:]
        for t in Lexicon.terms(question) { weights[t] = 1 }
        if Self.isFollowUp(question), let last = previous.last {
            for t in Lexicon.terms(last) where weights[t] == nil { weights[t] = settings.followUpWeight }
        }
        return weights
    }

    /// Every question you wrote an answer to that matches this one, best first.
    public func matchPreparedAll(_ question: String) async -> [Hit] {
        let asked = index.chunks.filter { $0.question != nil }
        guard !asked.isEmpty else { return [] }
        let incoming = Set(Lexicon.terms(question))
        var sims: [String: Double] = [:]
        if let embedder, !index.questionVectors.isEmpty, index.embedderName == embedder.name,
           let qv = try? await embedder.embed([question]).first {
            let q = Vector.normalized(qv)
            for chunk in asked { if let v = index.questionVectors[chunk.id] { sims[chunk.id] = Double(max(0, Vector.dot(q, v))) } }
        }
        var found: [Hit] = []
        for chunk in asked {
            let stored = Set(Lexicon.terms(chunk.question ?? ""))
            let overlap = incoming.isEmpty || stored.isEmpty ? 0
                : Double(incoming.intersection(stored).count) / Double(max(incoming.count, stored.count))
            let sim = sims[chunk.id] ?? 0
            guard overlap >= settings.preparedOverlap || sim >= settings.preparedSimilarity else { continue }
            let primary = chunk.folder == primaryFolder
            found.append(Hit(chunk: chunk, coverage: overlap, similarity: sim,
                             score: max(overlap, sim) * (primary ? settings.primaryBoost : 1), via: .prepared, primary: primary))
        }
        return found.sorted { $0.score > $1.score }
    }

    /// The question you wrote an answer to that matches this one best, if it's close enough.
    public func matchPrepared(_ question: String) async -> Hit? {
        await matchPreparedAll(question).first
    }

    public func retrieve(_ question: String, previous: [String] = []) async -> [Hit] {
        // Your own written answers to this question come first; other passages follow as alternatives.
        let prepared = await matchPreparedAll(question)
        guard !prepared.isEmpty else { return await retrievePassages(question, previous: previous) }
        let ids = Set(prepared.map(\.chunk.id))
        let rest = await retrievePassages(question, previous: previous).filter { !ids.contains($0.chunk.id) }
        return Array((prepared + rest).prefix(settings.maxHits))
    }

    public func retrievePassages(_ question: String, previous: [String] = []) async -> [Hit] {
        let weighted = weightedTerms(question, previous: previous)
        var hits: [Hit] = index.keywordSearch(weighted).prefix(settings.maxHits * 3).map { item in
            let (i, score, coverage) = item
            let chunk = index.chunks[i]
            let primary = chunk.folder == primaryFolder
            return Hit(chunk: chunk, coverage: coverage, similarity: 0,
                       score: score * (primary ? settings.primaryBoost : 1), via: .keyword, primary: primary)
        }
        hits.sort { $0.score > $1.score }

        let best = hits.map(\.coverage).max() ?? 0
        if best < settings.thinCoverage, let embedder, !index.vectors.isEmpty, index.embedderName == embedder.name {
            let query = (Self.isFollowUp(question) ? (previous.last ?? "") + " " : "") + question
            if let qv = try? await embedder.embed([query]).first {
                let q = Vector.normalized(qv)
                var semantic: [Hit] = index.chunks.compactMap { chunk in
                    guard let v = index.vectors[chunk.id] else { return nil }
                    let sim = Double(max(0, Vector.dot(q, v)))
                    let primary = chunk.folder == primaryFolder
                    return Hit(chunk: chunk, coverage: 0, similarity: sim,
                               score: sim * (primary ? settings.primaryBoost : 1), via: .embedding, primary: primary)
                }
                semantic.sort { $0.score > $1.score }
                // Meaning search only adds: keyword matches keep their order and come first, then the closest
                // meaning matches fill the remaining places. A loosely related passage can't jump a real word match.
                let kept = hits.filter { $0.coverage >= 0.2 }
                var seen = Set(kept.map(\.chunk.id))
                hits = kept
                for h in semantic where !seen.contains(h.chunk.id) && hits.count < settings.maxHits {
                    hits.append(h)
                    seen.insert(h.chunk.id)
                }
            }
        }
        return Array(hits.prefix(settings.maxHits))
    }
}
