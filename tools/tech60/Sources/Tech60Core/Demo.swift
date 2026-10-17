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
                   text: String = "", summary: String? = nil, primary: Bool) -> Story {
            var state: SummaryState = .none
            if let summary {
                let check = SummaryChecker.check(summary: summary, source: title + "\n" + text)
                state = check.passed ? .checked(text: summary, evidence: check.evidence) : .withheld(reason: check.reason ?? "")
            }
            return Story(id: id, sourceID: source, sourceName: source, title: title,
                         url: URL(string: "https://example.com/\(id)")!, published: now.addingTimeInterval(-minutesAgo * 60),
                         firstSeen: now.addingTimeInterval(-seenMinutesAgo * 60), sourceText: text, isPrimary: primary, summary: state)
        }

        return Snapshot(stories: [
            story("s1", "Sample Labs", "Sample: Atlas 2 coding model now available", minutesAgo: 12, seenMinutesAgo: 10,
                  text: source1, summary: summary1, primary: true),
            story("s2", "Example Cloud", "Sample: scheduled jobs come to 12 regions", minutesAgo: 40, seenMinutesAgo: 35,
                  text: source2, summary: summary2, primary: true),
            story("s3", "Hacker News", "Sample: a deep dive into how text editors store undo history", minutesAgo: 90, seenMinutesAgo: 300,
                  primary: false),
            story("s4", "Tech publication", "Sample: chipmaker reports quarterly results", minutesAgo: 130, seenMinutesAgo: 300,
                  primary: false),
        ], lastViewed: now.addingTimeInterval(-60 * 60), status: [:])
    }
}
