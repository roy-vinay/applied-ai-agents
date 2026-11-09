import Foundation

/// One labelled question in the gate set, written by you from a real prep pack.
public struct GateQuestion: Codable, Sendable {
    public var question: String
    /// Does the corpus answer this? False means the correct behaviour is NOT IN YOUR DOCS.
    public var covered: Bool
    /// File name of the passage that answers it (when covered).
    public var file: String?
    /// Optional: a heading that passage sits under.
    public var heading: String?
    /// Optional: words or figures a correct answer must contain.
    public var mustContain: [String]?
    /// Optional: the question before it, for follow-up questions.
    public var previous: String?
}

public struct GateResult: Codable, Sendable {
    public struct Row: Codable, Sendable {
        public var question: String
        public var covered: Bool
        public var label: AnswerLabel
        public var source: String?
        public var answer: String?
        public var correctSource: Bool
        public var correctRefusal: Bool
        public var citationOK: Bool
        public var unsupportedNumbers: [String]
        public var sourceLatency: Double
        /// How the top passage was found and how strongly ("keyword 0.67", "embedding 0.71").
        public var match: String
    }

    public var date: Date
    public var rows: [Row]
    public var citationCorrectness: Double
    public var groundedAccuracy: Double
    public var refusalPrecision: Double
    public var unsupportedNumbers: Int
    public var medianLatency: Double
    public var p90Latency: Double

    // The bars from the PRD, Section 11.
    public var passed: Bool {
        citationCorrectness >= 0.95 && groundedAccuracy >= 0.85 && refusalPrecision >= 0.90
            && unsupportedNumbers == 0 && medianLatency < 3 && p90Latency < 5
    }

    public var failures: [String] {
        var f: [String] = []
        if citationCorrectness < 0.95 { f.append("citation correctness \(pct(citationCorrectness)) (needs 95%)") }
        if groundedAccuracy < 0.85 { f.append("grounded accuracy \(pct(groundedAccuracy)) (needs 85%)") }
        if refusalPrecision < 0.90 { f.append("refusal precision \(pct(refusalPrecision)) (needs 90%)") }
        if unsupportedNumbers > 0 { f.append("\(unsupportedNumbers) invented figure(s) (needs zero)") }
        if medianLatency >= 3 { f.append(String(format: "median latency %.2fs (needs under 3s)", medianLatency)) }
        if p90Latency >= 5 { f.append(String(format: "90th percentile latency %.2fs (needs under 5s)", p90Latency)) }
        return f
    }

    func pct(_ x: Double) -> String { String(format: "%.0f%%", x * 100) }

    public var markdown: String {
        var s = "# Second Chair gate: \(passed ? "PASSED" : "FAILED")\n\n"
        s += "| Gate | Result | Bar |\n|---|---|---|\n"
        s += "| Citation correctness | \(pct(citationCorrectness)) | at least 95% |\n"
        s += "| Grounded accuracy | \(pct(groundedAccuracy)) | at least 85% |\n"
        s += "| Refusal precision | \(pct(refusalPrecision)) | at least 90% |\n"
        s += "| Unsupported numbers | \(unsupportedNumbers) | zero |\n"
        s += String(format: "| Source latency, median | %.2fs | under 3s |\n", medianLatency)
        s += String(format: "| Source latency, 90th percentile | %.2fs | under 5s |\n\n", p90Latency)
        s += "| Question | Expected | Shown | Source | Best match | OK |\n|---|---|---|---|---|---|\n"
        for r in rows {
            let ok = r.covered ? r.correctSource && r.citationOK : r.correctRefusal
            let q = r.question.replacingOccurrences(of: "|", with: "/")
            s += "| \(q) | \(r.covered ? "covered" : "not covered") | \(r.label.rawValue) | \(r.source ?? "") | \(r.match) | \(ok ? "yes" : "**no**") |\n"
        }
        return s
    }
}

/// Runs the answering half against a labelled question set, with no listening involved.
public enum Gate {
    public static func run(_ questions: [GateQuestion], retriever: Retriever, answerer: Answerer) async -> GateResult {
        var rows: [GateResult.Row] = []
        var latencies: [Double] = []
        for q in questions {
            let start = Date()
            let hits = await retriever.retrieve(q.question, previous: q.previous.map { [$0] } ?? [])
            let card = await answerer.answer(q.question, hits: hits, started: start)
            latencies.append(card.sourceLatency)

            let shownFiles = card.passages.map(\.chunk)
            let matchesExpected = shownFiles.contains { chunk in
                guard let file = q.file else { return false }
                let fileOK = chunk.fileName.caseInsensitiveCompare(file) == .orderedSame
                    || chunk.file.lowercased().hasSuffix(file.lowercased())
                let headingOK = q.heading.map { h in chunk.headings.contains { $0.localizedCaseInsensitiveContains(h) } } ?? true
                return fileOK && headingOK
            }
            let containsOK = (q.mustContain ?? []).allSatisfy { needle in
                (card.answer ?? card.passages.first?.chunk.text ?? "").localizedCaseInsensitiveContains(needle)
            }
            let correctSource = q.covered && card.label != .notInDocs && matchesExpected && containsOK
            let correctRefusal = q.covered ? card.label != .notInDocs : card.label == .notInDocs
            let check = card.answer.map { Grounding.check($0, against: card.passages.map(\.chunk.text), question: q.question) }
            rows.append(.init(question: q.question, covered: q.covered, label: card.label,
                              source: card.passages.first?.chunk.sourceLine, answer: card.answer,
                              correctSource: correctSource, correctRefusal: correctRefusal,
                              citationOK: check?.passed ?? true, unsupportedNumbers: check?.unsupportedNumbers ?? [],
                              sourceLatency: card.sourceLatency,
                              match: hits.first.map { String(format: "%@ %.2f", $0.via.rawValue, $0.strength) } ?? "none"))
        }
        let shown = rows.filter { $0.answer != nil }
        let covered = rows.filter(\.covered)
        let sorted = latencies.sorted()
        func quantile(_ p: Double) -> Double {
            guard !sorted.isEmpty else { return 0 }
            return sorted[min(sorted.count - 1, Int((Double(sorted.count - 1) * p).rounded()))]
        }
        return GateResult(
            date: Date(), rows: rows,
            citationCorrectness: shown.isEmpty ? 1 : Double(shown.filter(\.citationOK).count) / Double(shown.count),
            groundedAccuracy: covered.isEmpty ? 1 : Double(covered.filter { $0.correctSource && $0.citationOK }.count) / Double(covered.count),
            refusalPrecision: rows.isEmpty ? 1 : Double(rows.filter(\.correctRefusal).count) / Double(rows.count),
            unsupportedNumbers: rows.reduce(0) { $0 + $1.unsupportedNumbers.count },
            medianLatency: quantile(0.5), p90Latency: quantile(0.9))
    }
}
