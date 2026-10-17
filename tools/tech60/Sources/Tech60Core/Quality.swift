import Foundation

/// Drops stories that aren't news: deals, reviews, buying guides, how-tos, gaming, and small Hacker News posts.
public enum NoiseFilter {
    /// Hacker News stories need this many points to count as news.
    public static let hnMinimumPoints = 150
    /// Show HN, Ask HN, and Tell HN need far more, because most are personal projects or questions.
    public static let hnPostMinimumPoints = 400

    private static let patterns: [String] = [
        // Deals and shopping
        #"\bdeals?\b.*(\$\d|% off)"#, #"\bbest .*deals\b"#, #"\bdeals on\b"#, #"\bdeal of the day\b"#, #"\d+\s?% off\b"#, #"\bsave \$\d"#, #"\bon sale\b"#, #"\bcoupons?\b"#, #"\bpromo codes?\b"#,
        #"\bprime day\b"#, #"\bblack friday\b"#, #"\bcyber monday\b"#, #"\bgift guide\b"#, #"\bgiveaway\b"#,
        #"\blowest price\b"#, #"\bbuying guide\b"#,
        // Reviews and buying guides
        #"\breview:"#, #"\bhands-on\b"#, #"^the \d+ best\b"#, #"^best .+ (for|to|of|in)\b"#, #"\bthe best .+ (for|of|in) \d{4}\b"#,
        #"\bwe tested\b"#, #"\bworth (it|buying)\b"#,
        // How-tos
        #"^how to\b"#, #"\bhow to (use|set up|turn|get|fix|change|enable|disable|download|watch)\b"#, #"\btips and tricks\b"#,
        // Gaming
        #"\bgaming\b"#, #"\bvideo ?games?\b"#, #"\bplaystation\b"#, #"\bps5\b"#, #"\bxbox\b"#, #"\bnintendo\b"#,
        #"\bswitch 2\b"#, #"\bsteam deck\b"#, #"\besports\b"#, #"\btrailer\b"#, #"\bwordle\b"#, #"\bconnections hints\b"#,
    ]
    private static let regexes: [NSRegularExpression] = patterns.compactMap {
        try? NSRegularExpression(pattern: $0, options: [.caseInsensitive])
    }

    public static func isNoise(_ story: Story) -> Bool {
        if story.sourceID == "hn" {
            let lower = story.title.lowercased()
            let isPost = ["show hn", "ask hn", "tell hn", "launch hn"].contains { lower.hasPrefix($0) }
            let points = story.points ?? 0
            if points < (isPost ? hnPostMinimumPoints : hnMinimumPoints) { return true }
        }
        let title = story.title
        let range = NSRange(title.startIndex..., in: title)
        return regexes.contains { $0.firstMatch(in: title, range: range) != nil }
    }
}

/// The on-device "editor": rates headlines 1 to 5 on whether a tech professional needs to know them today.
public enum EditorPrompt {
    public static let instructions = """
    You are the editor of a short daily technology briefing for working professionals: engineers, product \
    leaders, and founders. For each numbered headline, rate from 1 to 5 whether a technology professional \
    needs to know it today. 5: major industry news everyone will discuss. 4: important to many people in tech. \
    3: useful to some. 2: niche or minor. 1: not news (deals, reviews, how-tos, trivia, opinion with no news). \
    Reply with one line per headline in the form "number: score" and nothing else.
    """

    public static func prompt(_ headlines: [String]) -> String {
        headlines.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
    }

    /// Reads "3: 4" lines back into scores, one per headline; nil where the model skipped one.
    public static func parse(_ text: String, count: Int) -> [Int?] {
        var scores = [Int?](repeating: nil, count: count)
        let regex = try! NSRegularExpression(pattern: #"^\s*(\d+)\s*[:.)\-]\s*([1-5])\b"#)
        for line in text.split(whereSeparator: \.isNewline) {
            let s = String(line)
            guard let m = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
                  let n = Int((s as NSString).substring(with: m.range(at: 1))),
                  let score = Int((s as NSString).substring(with: m.range(at: 2))),
                  (1...count).contains(n) else { continue }
            scores[n - 1] = score
        }
        return scores
    }
}

/// What the reader has told Tech60 with "More like this" and "Less like this": weights on headline words
/// and on sources. Small and explainable, and it never leaves the Mac.
public struct Taste: Codable, Equatable, Sendable {
    public var terms: [String: Double] = [:]
    public var sources: [String: Double] = [:]

    public init() {}

    public var isEmpty: Bool { terms.isEmpty && sources.isEmpty }

    public mutating func record(_ cluster: StoryCluster, more: Bool) {
        let step = more ? 1.0 : -1.0
        for word in Set(cluster.stories.flatMap { Clustering.keyTerms($0.title) }) where !word.allSatisfy(\.isNumber) {
            terms[word, default: 0] = max(-4, min(4, terms[word, default: 0] + step))
        }
        for source in Set(cluster.stories.map(\.sourceID)) {
            sources[source, default: 0] = max(-4, min(4, sources[source, default: 0] + step * 0.5))
        }
    }

    /// A multiplier on heat between 0.5 and 2: above 1 for stories like ones the reader wanted more of.
    public func multiplier(for cluster: StoryCluster) -> Double {
        guard !isEmpty else { return 1 }
        let words = Set(cluster.stories.flatMap { Clustering.keyTerms($0.title) })
        let termScore = words.reduce(0) { $0 + (terms[$1] ?? 0) }
        let sourceScore = Set(cluster.stories.map(\.sourceID)).reduce(0) { $0 + (sources[$1] ?? 0) }
        let total = max(-3, min(3, termScore * 0.5 + sourceScore))
        return max(0.5, min(2, exp(0.25 * total)))
    }
}
