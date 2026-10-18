import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// A plain-English explainer for a research paper, in four parts: the problem, what the authors did, what
/// they found, and why it matters. The first three are checked against the paper. "Why it matters" is the
/// model's reading of what the work enables, so the card labels it as interpretation.
public struct PaperExplainer: Equatable, Sendable {
    public var problem: String
    public var approach: String
    public var findings: String
    public var impact: String

    public init(problem: String, approach: String, findings: String, impact: String) {
        self.problem = problem
        self.approach = approach
        self.findings = findings
        self.impact = impact
    }

    public static let maxWords = 220
    /// Plain language rewords jargon, so findings need less word overlap than a news summary does.
    public static let findingsSupport = 0.4

    public static let instructions = """
    You explain new AI research papers to busy professionals who are not researchers. Write four short parts, \
    each on its own line, each starting with its label exactly as shown:
    Problem: what problem or question the paper tackles and why it matters, in everyday words.
    Approach: what the authors did, in one or two sentences. Explain any technical term in a few plain words.
    Findings: the main results. Copy numbers exactly as they appear in the text.
    Why it matters: who could use this work and for what, in one or two sentences, based on what the text says it enables.
    Use only facts from the text. Do not invent numbers, names, datasets, or results. Keep the whole answer \
    under 180 words. No headings, bullet points, or markdown.
    """

    public static func prompt(title: String, text: String) -> String {
        "Title: \(title)\n\nPaper text:\n\(String(text.prefix(6_000)))"
    }

    private static let labels: [(String, WritableKeyPath<PaperExplainer, String>)] = [
        ("problem", \.problem), ("approach", \.approach), ("findings", \.findings), ("why it matters", \.impact),
    ]

    /// Reads the model's four labeled parts. Nil unless all four are there.
    public static func parse(_ raw: String) -> PaperExplainer? {
        var out = PaperExplainer(problem: "", approach: "", findings: "", impact: "")
        var current: WritableKeyPath<PaperExplainer, String>?
        for rawLine in raw.split(whereSeparator: \.isNewline) {
            var line = rawLine.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "__", with: "")
                .trimmingCharacters(in: .whitespaces)
            while let first = line.first, "#*-•>".contains(first) { line = String(line.dropFirst()).trimmingCharacters(in: .whitespaces) }
            guard !line.isEmpty else { continue }
            let lower = line.lowercased()
            if let match = labels.first(where: { lower.hasPrefix($0.0 + ":") }) {
                current = match.1
                line = String(line.dropFirst(match.0.count + 1)).trimmingCharacters(in: .whitespaces)
            }
            guard let key = current else { continue }
            out[keyPath: key] = out[keyPath: key].isEmpty ? line : out[keyPath: key] + " " + line
        }
        let parts = [out.problem, out.approach, out.findings, out.impact]
        return parts.allSatisfy { !$0.isEmpty } ? out : nil
    }

    /// How the explainer is stored in a story's checked summary.
    public var stored: String {
        "Problem: \(problem)\nApproach: \(approach)\nFindings: \(findings)\nWhy it matters: \(impact)"
    }

    /// Checks the explainer with plain code. Every number and name in all four parts must be in the paper,
    /// and every sentence of the findings must be supported by a sentence of the paper.
    public static func check(_ e: PaperExplainer, source: String) -> SummaryChecker.Result {
        func fail(_ why: String) -> SummaryChecker.Result { SummaryChecker.Result(passed: false, reason: why, evidence: []) }
        let all = [e.problem, e.approach, e.findings, e.impact].joined(separator: " ")
        let words = all.split(whereSeparator: { $0.isWhitespace }).count
        guard words <= maxWords else { return fail("Too long: \(words) words (limit \(maxWords)).") }
        let sourceFlat = SummaryChecker.flatten(source)
        for part in [e.problem, e.approach, e.findings, e.impact] {
            for number in SummaryChecker.numbers(in: part) where !sourceFlat.contains(number) {
                return fail("The number \"\(number)\" isn't in the paper.")
            }
            for name in SummaryChecker.properNames(in: part) where !sourceFlat.contains(name.lowercased()) {
                return fail("The name \"\(name)\" isn't in the paper.")
            }
        }
        return SummaryChecker.check(summary: e.findings, source: source, maxWords: maxWords, minimumSupport: findingsSupport)
    }
}

extension Research {
    /// arXiv's web version of a paper, which has the full text: arxiv.org/html/2410.01234.
    public static func htmlURL(for url: URL) -> URL? {
        canonicalArxiv(url).flatMap { URL(string: $0.replacingOccurrences(of: "/abs/", with: "/html/")) }
    }

    /// What the explainer reads: the abstract, then the introduction and the conclusion, where authors say
    /// what the work is for. Falls back to the abstract alone.
    public static func explainerText(abstract: String, introduction: String?, conclusion: String?) -> String {
        var parts = ["Abstract: " + abstract]
        if let intro = introduction, !intro.isEmpty { parts.append("Introduction: " + String(intro.prefix(2_500))) }
        if let end = conclusion, !end.isEmpty { parts.append("Conclusion: " + String(end.prefix(1_500))) }
        return parts.joined(separator: "\n\n")
    }

    /// The introduction and conclusion of an arXiv HTML paper (LaTeXML sections with numbered headings).
    public static func introductionAndConclusion(fromHTML data: Data) -> (introduction: String?, conclusion: String?) {
        #if os(macOS)
        guard let doc = try? XMLDocument(data: data, options: [.documentTidyHTML]),
              let sections = try? doc.nodes(forXPath: "//section[contains(@class,'ltx_section')]") else { return (nil, nil) }
        var intro: String?
        var end: String?
        for section in sections {
            let title = ((try? section.nodes(forXPath: "./h2")) ?? []).first?.stringValue?.lowercased() ?? ""
            let text = ((try? section.nodes(forXPath: ".//p")) ?? [])
                .compactMap { $0.stringValue?.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression) }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            if intro == nil, title.contains("introduction") { intro = text }
            if title.contains("conclusion") || (end == nil && title.contains("discussion")) { end = text }
        }
        return (intro, end)
        #else
        return (nil, nil)
        #endif
    }
}
