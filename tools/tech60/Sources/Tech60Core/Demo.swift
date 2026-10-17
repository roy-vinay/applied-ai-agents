import Foundation

/// Sample stories for screenshots and first-run previews. Every one is clearly marked as a sample.
public enum Demo {
    public static func snapshot(now: Date = Date()) -> Snapshot {
        let source1 = "Sample Labs today released Atlas 2, a coding model with a 400,000 token context window. "
            + "Atlas 2 scores 72.5 percent on the team's internal coding benchmark, up from 61 percent. "
            + "It is available in the API today at the same price as Atlas 1."
        let summary1 = "Sample Labs released Atlas 2, a coding model with a 400,000 token context window. "
            + "Atlas 2 scores 72.5 percent on the internal coding benchmark, up from 61 percent, and is available in the API at the same price."
        let source2 = "Example Cloud now lets developers run scheduled jobs in 12 regions. "
            + "Scheduled jobs can run as often as once a minute and are billed per second."
        let summary2 = "Example Cloud now lets developers run scheduled jobs in 12 regions, as often as once a minute, billed per second."

        func story(_ id: String, _ source: String, _ title: String, minutesAgo: Double, seenMinutesAgo: Double,
                   text: String = "", summary: String? = nil, primary: Bool, points: Int? = nil, comments: Int? = nil) -> Story {
            var state: SummaryState = .none
            if let summary {
                let check = SummaryChecker.check(summary: summary, source: title + "\n" + text)
                state = check.passed ? .checked(text: summary, evidence: check.evidence) : .withheld(reason: check.reason ?? "")
            }
            var s = Story(id: id, sourceID: source, sourceName: source, title: title,
                          url: URL(string: "https://example.com/\(id)")!, published: now.addingTimeInterval(-minutesAgo * 60),
                          firstSeen: now.addingTimeInterval(-seenMinutesAgo * 60), sourceText: text, isPrimary: primary, summary: state)
            s.points = points
            s.comments = comments
            return s
        }

        return Snapshot(stories: [
            story("s1", "Sample Labs", "Sample: Atlas 2 coding model now available", minutesAgo: 12, seenMinutesAgo: 10,
                  text: source1, summary: summary1, primary: true),
            story("s2", "Example Cloud", "Sample: scheduled jobs come to 12 regions", minutesAgo: 40, seenMinutesAgo: 35,
                  text: source2, summary: summary2, primary: true),
            story("s1b", "Tech publication", "Sample Labs' Atlas 2 coding model brings a 400,000 token context window",
                  minutesAgo: 8, seenMinutesAgo: 6, primary: false),
            story("s1c", "Hacker News", "Sample: Atlas 2 coding model (example.com)", minutesAgo: 5, seenMinutesAgo: 4, primary: false,
                  points: 412, comments: 188),
            story("s5", "Security blog", "Sample: browser vendors patch a zero-day exploited in the wild", minutesAgo: 70, seenMinutesAgo: 300,
                  primary: false),
            story("s3", "Hacker News", "Sample: a deep dive into how text editors store undo history", minutesAgo: 90, seenMinutesAgo: 300,
                  primary: false, points: 236, comments: 71),
            story("s4", "Tech publication", "Sample: chipmaker reports quarterly results", minutesAgo: 130, seenMinutesAgo: 300,
                  primary: false),
        ], lastViewed: now.addingTimeInterval(-60 * 60), status: [:])
    }
}
