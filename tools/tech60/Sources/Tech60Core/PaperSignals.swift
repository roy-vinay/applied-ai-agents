import Foundation

/// The groups the Research tab sorts papers into, built around how practitioners think rather than
/// arXiv's broad categories.
public enum PaperGroup: String, CaseIterable, Codable, Sendable {
    case agents, models, reasoning, retrieval, evaluation, safety, efficiency, multimodal, applied

    public var name: String {
        switch self {
        case .agents: return "Agents"
        case .models: return "Models"
        case .reasoning: return "Reasoning"
        case .retrieval: return "Retrieval"
        case .evaluation: return "Evaluation"
        case .safety: return "Safety"
        case .efficiency: return "Efficiency"
        case .multimodal: return "Multimodal"
        case .applied: return "Applied"
        }
    }

    /// Words that suggest the group, used when the on-device model isn't available or hasn't rated a paper yet.
    var keywords: [String] {
        switch self {
        case .agents: return ["agent", "agentic", "multi-agent", "tool use", "tool-use", "tool calling", "planning", "orchestrat", "computer use", "web navigation"]
        case .models: return ["pretrain", "pre-train", "architecture", "transformer", "scaling law", "fine-tun", "post-train", "mixture of experts", "foundation model", "language model"]
        case .reasoning: return ["reasoning", "chain-of-thought", "chain of thought", "math", "theorem", "test-time", "self-correct", "logic"]
        case .retrieval: return ["retrieval", "rag", "long context", "long-context", "knowledge graph", "search engine", "memory"]
        case .evaluation: return ["benchmark", "evaluat", "llm-as-a-judge", "judge", "hallucinat", "metric", "leaderboard"]
        case .safety: return ["safety", "jailbreak", "prompt injection", "alignment", "guardrail", "privacy", "adversarial", "red team", "harmful"]
        case .efficiency: return ["quantiz", "distill", "pruning", "efficient", "latency", "inference cost", "small language model", "compression", "speculative decoding"]
        case .multimodal: return ["vision", "image", "video", "speech", "audio", "multimodal", "visual", "document understanding"]
        case .applied: return ["clinical", "medical", "health", "legal", "finance", "education", "code generation", "software engineering", "logistics", "robot"]
        }
    }
}

/// What Tech60 knows about a paper's quality, from arXiv's own data and the on-device model.
public enum PaperSignals {
    private static let venues = ["NeurIPS", "ICLR", "ICML", "ACL", "EMNLP", "NAACL", "COLING", "CVPR", "ICCV", "ECCV", "AAAI",
                                 "IJCAI", "KDD", "COLM", "TMLR", "JMLR", "TACL", "SIGIR", "WWW", "CHI", "UIST", "ICRA", "AISTATS", "UAI"]

    /// The group whose words show up most in the title and abstract. Title words count double.
    public static func keywordGroup(title: String, abstract: String) -> PaperGroup {
        let t = title.lowercased(), a = abstract.lowercased()
        var best: (group: PaperGroup, hits: Int) = (.models, 0)
        for group in PaperGroup.allCases {
            let hits = group.keywords.reduce(0) { n, k in n + (t.contains(k) ? 2 : 0) + (a.contains(k) ? 1 : 0) }
            if hits > best.hits { best = (group, hits) }
        }
        return best.group
    }

    /// A peer-reviewed venue the authors say the paper was accepted at, such as "NeurIPS 2026".
    /// "Submitted to" and "under review" don't count.
    public static func venue(fromComment comment: String) -> String? {
        let lower = comment.lowercased()
        guard !lower.contains("submitted to"), !lower.contains("under review"), !lower.contains("in submission") else { return nil }
        for v in venues {
            guard let r = comment.range(of: #"\b\#(v)\b"#, options: .regularExpression) else { continue }
            let after = comment[r.upperBound...]
            if let y = after.range(of: #"^[\s'’]*(20\d\d|\d\d)\b"#, options: .regularExpression) {
                let year = after[y].trimmingCharacters(in: CharacterSet(charactersIn: " '’"))
                return "\(v) \(year.count == 2 ? "20" + year : year)"
            }
            return v
        }
        return nil
    }

    /// True when the abstract or comment links to code or a model release.
    public static func hasCode(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("github.com/") || lower.contains("huggingface.co/") || lower.contains("gitlab.com/")
    }

    /// Hacker News picked it up.
    public static func inTheNews(_ s: Story) -> Bool { (s.points ?? 0) >= Research.newsPoints }

    /// A paper worth showing by default. Without model ratings, only hard signals count.
    public static func isNotable(_ s: Story) -> Bool {
        if inTheNews(s) || s.paperVenue != nil { return true }
        let a = s.paperApplicability ?? 0, g = s.paperGeneralizability ?? 0
        if a >= 4 && g >= 3 { return true }
        if s.paperHasCode == true && (a >= 3 || s.paperApplicability == nil) { return true }
        return false
    }

    /// How high a paper sits in Research. Followed groups get a small lift.
    public static func score(_ s: Story, followed: Set<PaperGroup> = []) -> Double {
        var x = 0.0
        if inTheNews(s) { x += 3 }
        if s.paperVenue != nil { x += 2 }
        if s.paperHasCode == true { x += 1 }
        x += Double(max(0, (s.paperApplicability ?? 3) - 3))
        x += 0.5 * Double(max(0, (s.paperGeneralizability ?? 3) - 3))
        if let g = s.paperGroup.flatMap(PaperGroup.init(rawValue:)), followed.contains(g) { x += 1 }
        return x
    }

    /// Why a paper made the cut, shortest first. "Practical" and "Broad" are the on-device model's read.
    public static func tags(_ s: Story) -> [String] {
        var out: [String] = []
        if let v = s.paperVenue { out.append(v) }
        if inTheNews(s) { out.append("On Hacker News") }
        if s.paperHasCode == true { out.append("Code") }
        if (s.paperApplicability ?? 0) >= 4 { out.append("Practical") }
        if (s.paperGeneralizability ?? 0) >= 4 { out.append("Broad") }
        return out
    }
}

/// The on-device rating pass for papers: a group, and 1-5 for applicability and generalizability.
public enum PaperRatingPrompt {
    public static let instructions = """
    You triage new AI research papers for people who build AI products. For each numbered paper, reply on one \
    line in the form "number: group, applicability, generalizability".
    group is one of: agents, models, reasoning, retrieval, evaluation, safety, efficiency, multimodal, applied.
    applicability, 1 to 5: could a team building products use this within a year? 5 means directly usable, \
    1 means purely theoretical.
    generalizability, 1 to 5: does the result hold across many tasks, models, or domains? 5 means broadly \
    tested, 1 means one narrow benchmark or setting.
    Judge only from the title and abstract. Reply with the lines and nothing else.
    """

    public static func prompt(_ papers: [(title: String, abstract: String)]) -> String {
        papers.enumerated().map { i, p in
            "\(i + 1). \(p.title)\n\(String(p.abstract.prefix(320)))"
        }.joined(separator: "\n\n")
    }

    public struct Rating: Equatable, Sendable {
        public var group: PaperGroup
        public var applicability: Int
        public var generalizability: Int
    }

    public static func parse(_ text: String, count: Int) -> [Rating?] {
        var out = [Rating?](repeating: nil, count: count)
        let regex = try! NSRegularExpression(pattern: #"^\s*(\d+)\s*[:.)\-]\s*([a-z]+)\s*,\s*([1-5])\s*,\s*([1-5])\b"#,
                                             options: [.caseInsensitive])
        for line in text.split(whereSeparator: \.isNewline) {
            let s = String(line).replacingOccurrences(of: "**", with: "")
            let ns = s as NSString
            guard let m = regex.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)),
                  let n = Int(ns.substring(with: m.range(at: 1))), (1...count).contains(n),
                  let group = PaperGroup(rawValue: ns.substring(with: m.range(at: 2)).lowercased()),
                  let a = Int(ns.substring(with: m.range(at: 3))), let g = Int(ns.substring(with: m.range(at: 4))) else { continue }
            out[n - 1] = Rating(group: group, applicability: a, generalizability: g)
        }
        return out
    }
}
