import XCTest
@testable import Tech60Core

final class HotTests: XCTestCase {
    private func s(_ id: String, _ source: String, _ title: String, hoursAgo: Double = 1, points: Int? = nil, primary: Bool = false) -> Story {
        var story = Story(id: id, sourceID: source, sourceName: source, title: title, url: URL(string: "https://example.com/\(id)")!,
                          published: Date().addingTimeInterval(-hoursAgo * 3600), firstSeen: Date(), sourceText: "", isPrimary: primary)
        story.points = points
        return story
    }

    func testWidelyCoveredAndDiscussedBeatsQuietButNewer() {
        let clusters = Clustering.cluster([
            s("a", "openai", "Introducing GPT-6 with a 2 million token context window", hoursAgo: 4, primary: true),
            s("b", "verge", "OpenAI launches GPT-6 with a 2 million token context window", hoursAgo: 3),
            s("c", "hn", "GPT-6 (openai.com)", hoursAgo: 3, points: 900),
            s("d", "ars", "A review of a mid-range office chair", hoursAgo: 0.2),
            s("e", "hn", "Show HN: My weekend Forth interpreter", hoursAgo: 0.5, points: 4),
        ])
        let hot = Hotness.hot(clusters)
        XCTAssertEqual(hot.first?.lead.id, "a")
        XCTAssertFalse(hot.contains { $0.lead.id == "d" }, "one outlet, no discussion: not trending")
    }

    func testNoFillerOnQuietDays() {
        let clusters = Clustering.cluster([s("a", "ars", "A quiet chair story"), s("b", "hn", "Butlerian Jihad", points: 225)])
        XCTAssertTrue(Hotness.hot(clusters).isEmpty, "no signal, no slot in Top")
    }

    func testHNPointsCarryOverWhenHNLinksToAStoryWeHave() {
        let openai = Source(id: "openai", name: "OpenAI", url: nil, isPrimary: true)
        let hn = Source(id: "hn", name: "Hacker News", kind: .hackerNews, url: nil, isPrimary: false)
        let now = Date()
        let first = StoryMerge.merge(existing: [], incoming: StoryMerge.stories(
            from: [FeedItem(id: "1", title: "Introducing GPT-6", link: URL(string: "https://openai.com/gpt-6"), published: now, text: "")],
            source: openai, now: now), now: now)
        let merged = StoryMerge.merge(existing: first, incoming: StoryMerge.stories(
            from: [FeedItem(id: "99", title: "GPT-6", link: URL(string: "https://openai.com/gpt-6/"), published: now, text: "", points: 812, comments: 400)],
            source: hn, now: now), now: now)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].title, "Introducing GPT-6", "the company's headline is kept")
        XCTAssertEqual(merged[0].points, 812)
    }
}
