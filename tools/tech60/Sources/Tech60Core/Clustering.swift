import Foundation

/// Several sources covering the same news, shown as one row. The lead is the story the row is built around.
public struct StoryCluster: Identifiable, Hashable, Sendable {
    public var stories: [Story]

    public init(stories: [Story]) { self.stories = stories }

    public var id: String { lead.id }
    public var lead: Story { stories[0] }
    public var others: [Story] { Array(stories.dropFirst()) }
    public var newestDate: Date { stories.map(\.displayDate).max() ?? lead.displayDate }
    public var sourceCount: Int { Set(stories.map(\.sourceID)).count }

    /// The earliest report: who broke it, and when.
    public var firstReport: Story { stories.min { $0.displayDate < $1.displayDate } ?? lead }

    /// The first picture any source gives, the lead's own first.
    public var imageURL: URL? { lead.imageURL ?? stories.lazy.compactMap(\.imageURL).first }

    /// Spreading now: three or more outlets, the latest within the last three hours.
    public func isDeveloping(now: Date = Date()) -> Bool {
        sourceCount >= 3 && now.timeIntervalSince(newestDate) < 3 * 3600
    }

    /// The story whose summary speaks for the row: one already checked, else an official one, else the lead.
    public var summaryStory: Story {
        stories.first { if case .checked = $0.summary { return true } else { return false } }
            ?? stories.first(where: \.isPrimary) ?? lead
    }
}

public enum Clustering {
    private static let stopWords: Set<String> = [
        "the", "and", "for", "with", "from", "that", "this", "into", "its", "it's", "are", "was", "were", "has", "have",
        "had", "but", "not", "you", "your", "our", "out", "about", "over", "after", "before", "now", "new", "how", "why",
        "what", "when", "who", "will", "can", "could", "would", "should", "may", "more", "than", "just", "all", "get",
        "gets", "got", "says", "said", "say", "launch", "launches", "launched", "announce", "announces", "announced",
        "introduce", "introduces", "introducing", "release", "releases", "released", "today", "update", "updates",
        "show", "ask", "via", "report", "reports", "first", "big", "makes", "make", "here", "there", "they", "their",
        "his", "her", "one", "two", "use", "uses", "using", "available", "sample", "week", "year", "years",
    ]

    /// Distinctive words of a headline, lowercased, without common words. Numbers are kept.
    public static func keyTerms(_ title: String) -> Set<String> {
        var t = title.lowercased()
        for prefix in ["show hn:", "ask hn:", "launch hn:", "tell hn:"] where t.hasPrefix(prefix) { t = String(t.dropFirst(prefix.count)) }
        let words = t.split { !($0.isLetter || $0.isNumber) }.map(String.init)
        var out = Set<String>()
        for w in words {
            let hasDigit = w.contains { $0.isNumber }
            guard hasDigit || w.count >= 3, !stopWords.contains(w) else { continue }
            out.insert(!hasDigit && w.count > 4 && w.hasSuffix("s") && !w.hasSuffix("ss") ? String(w.dropLast()) : w)
        }
        return out
    }

    /// Groups stories that cover the same news. Words that show up in many headlines (like "apple" on a busy
    /// Apple day) count for less, so two different Apple stories don't merge just for sharing "apple iphone".
    public static func cluster(_ stories: [Story], window: TimeInterval = 36 * 3600) -> [StoryCluster] {
        let terms = stories.map { keyTerms($0.title) }
        var df: [String: Int] = [:]
        for set in terms { for w in set { df[w, default: 0] += 1 } }
        let n = Double(max(stories.count, 2))
        func weight(_ w: String) -> Double { log(n / Double(df[w] ?? 1)) + 0.3 }

        var parent = Array(stories.indices)
        func find(_ i: Int) -> Int { var i = i; while parent[i] != i { parent[i] = parent[parent[i]]; i = parent[i] }; return i }

        for i in stories.indices {
            for j in stories.indices where j > i {
                guard stories[i].sourceID != stories[j].sourceID,
                      abs(stories[i].displayDate.timeIntervalSince(stories[j].displayDate)) < window else { continue }
                let shared = terms[i].intersection(terms[j])
                guard shared.count >= 2 else { continue }
                let s = shared.reduce(0) { $0 + weight($1) }
                let a = terms[i].reduce(0) { $0 + weight($1) }
                let b = terms[j].reduce(0) { $0 + weight($1) }
                if s / max(min(a, b), 0.001) >= 0.5 {
                    let ri = find(i), rj = find(j)
                    parent[rj] = ri
                }
            }
        }

        var groups: [Int: [Story]] = [:]
        var order: [Int] = []
        for i in stories.indices {
            let root = find(i)
            if groups[root] == nil { order.append(root) }
            groups[root, default: []].append(stories[i])
        }
        return order.compactMap { groups[$0] }.map { group in
            // Lead: the company's own post, else the earliest report.
            let sorted = group.sorted {
                if $0.isPrimary != $1.isPrimary { return $0.isPrimary }
                return $0.displayDate < $1.displayDate
            }
            return StoryCluster(stories: sorted)
        }
        .sorted { $0.newestDate > $1.newestDate }
    }
}

/// How hot a story is right now. Heat comes from signals other people create, not from the clock:
/// several outlets covering it, Hacker News points and comments, Techmeme picking it, or the company posting
/// it themselves. Heat then cools with age, like Hacker News's own ranking.
public enum Hotness {
    /// The editor's best rating among the row's stories, if any were rated.
    public static func editorScore(_ cluster: StoryCluster) -> Int? { cluster.stories.compactMap(\.editorScore).max() }

    /// Heat before cooling. 1 means no signal at all (one outlet, no discussion). Coverage and a Techmeme
    /// pick count most; Hacker News points are capped so a popular essay can't outrank real news.
    public static func heat(_ cluster: StoryCluster, topics: [Topic] = [], taste: Taste = Taste()) -> Double {
        let points = Double(cluster.stories.compactMap(\.points).max() ?? 0)
        let comments = Double(cluster.stories.compactMap(\.comments).max() ?? 0)
        var h = 1.0
        h += Double(cluster.sourceCount - 1) * 3
        h += min(log10(1 + points) * 1.5, 3.5)      // 100 points adds 3, capped at 3.5
        h += min(log10(1 + comments) * 0.5, 1)
        if cluster.stories.contains(where: { $0.sourceID.lowercased() == "techmeme" }) { h += 3 }    // an editor picked it
        if cluster.stories.contains(where: \.isPrimary) { h += 1.5 }
        if !topics.isEmpty, cluster.stories.contains(where: { !Topics.matches($0, in: topics).isEmpty }) { h *= 1.5 }
        switch editorScore(cluster) {
        case 5?: h *= 1.4
        case 4?: h *= 1.15
        case 1?, 2?: h *= 0.6
        default: break
        }
        return h * taste.multiplier(for: cluster)
    }

    public static func score(_ cluster: StoryCluster, topics: [Topic] = [], taste: Taste = Taste(), now: Date = Date()) -> Double {
        let hours = max(0, now.timeIntervalSince(cluster.newestDate) / 3600)
        return heat(cluster, topics: topics, taste: taste) / pow(hours + 2, 1.3)
    }

    /// Real signal that a story matters: more than one outlet, a Techmeme pick, the company's own post,
    /// or a very big Hacker News story.
    public static func hasSignal(_ cluster: StoryCluster) -> Bool {
        cluster.sourceCount >= 2
            || cluster.stories.contains { $0.sourceID.lowercased() == "techmeme" || $0.isPrimary }
            || (cluster.stories.compactMap(\.points).max() ?? 0) >= 400
    }

    /// The hottest rows, hottest first: only rows with real signal that the editor didn't rate 2 or lower.
    /// No filler: on a quiet day Top is simply shorter.
    public static func hot(_ clusters: [StoryCluster], topics: [Topic] = [], taste: Taste = Taste(), now: Date = Date(),
                           limit: Int = 25) -> [StoryCluster] {
        let worthy = clusters.filter { hasSignal($0) && (editorScore($0) ?? 3) >= 3 }
        let ranked = worthy.sorted { score($0, topics: topics, taste: taste, now: now) > score($1, topics: topics, taste: taste, now: now) }
        return Array(ranked.prefix(limit))
    }
}

/// Picks the few stories worth a notification.
public enum Brief {
    public static func score(_ cluster: StoryCluster, topics: [Topic], taste: Taste = Taste(), now: Date = Date()) -> Double {
        Hotness.score(cluster, topics: topics, taste: taste, now: now)
    }

    public static func pick(_ clusters: [StoryCluster], topics: [Topic], taste: Taste = Taste(), since: Date, now: Date = Date(),
                            count: Int = 5) -> [StoryCluster] {
        let floor = max(since, now.addingTimeInterval(-36 * 3600))
        let recent = clusters.filter { $0.newestDate >= floor && (Hotness.editorScore($0) ?? 3) >= 3 }
        return Array(recent.sorted { score($0, topics: topics, taste: taste, now: now) > score($1, topics: topics, taste: taste, now: now) }.prefix(count))
    }

    /// The notification text: one headline per line.
    public static func body(_ clusters: [StoryCluster]) -> String {
        clusters.map { c in
            let more = c.sourceCount > 1 ? " (\(c.sourceCount) sources)" : ""
            return "\u{2022} " + c.lead.title + more
        }.joined(separator: "\n")
    }
}
