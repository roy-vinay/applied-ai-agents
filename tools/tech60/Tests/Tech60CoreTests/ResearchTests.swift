import XCTest
@testable import Tech60Core

final class ResearchTests: XCTestCase {
    let now = ISO8601DateFormatter().date(from: "2026-10-17T12:00:00Z")!
    let arxiv = Source(id: "arxiv", name: "arXiv", kind: .research, url: nil, isPrimary: false)
    let hn = Source(id: "hn", name: "Hacker News", kind: .hackerNews, url: nil, isPrimary: false)

    private func item(_ id: String, type: String = "new", link: String = "https://arxiv.org/abs/2410.01234") -> FeedItem {
        FeedItem(id: "oai:arXiv.org:\(id)", title: "Scaling laws for tool-using agents", link: URL(string: link), published: now,
                 text: "arXiv:\(id)v1 Announce Type: \(type) \nAbstract: We study how agents scale with tools.")
    }

    func testParsesArxivRSS() throws {
        let xml = """
        <?xml version="1.0"?>
        <rss version="2.0" xmlns:dc="http://purl.org/dc/elements/1.1/"><channel><title>cs.AI updates on arXiv.org</title>
        <item><title>Scaling laws for tool-using agents</title><link>https://arxiv.org/abs/2410.01234</link>
          <description>arXiv:2410.01234v1 Announce Type: new
        Abstract: We study how agents scale with tools.</description>
          <guid isPermaLink="false">oai:arXiv.org:2410.01234v1</guid><dc:creator>A. Author</dc:creator>
          <pubDate>Fri, 17 Oct 2026 00:00:00 -0400</pubDate></item>
        <item><title>An older paper, revised</title><link>https://arxiv.org/abs/2301.00001</link>
          <description>arXiv:2301.00001v3 Announce Type: replace
        Abstract: Revised.</description><guid isPermaLink="false">oai:arXiv.org:2301.00001v3</guid></item>
        </channel></rss>
        """
        let stories = StoryMerge.stories(from: try FeedParser.parse(Data(xml.utf8), now: now), source: arxiv, now: now)
        XCTAssertEqual(stories.count, 1, "replaced versions of old papers are skipped")
        XCTAssertEqual(stories[0].sourceText, "We study how agents scale with tools.")
        XCTAssertEqual(stories[0].isResearch, true)
        XCTAssertFalse(stories[0].isPrimary, "papers are not summarized in the background")
    }

    func testParsesArxivSearchAPI() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom"><title>arXiv Query</title>
        <entry><id>http://arxiv.org/abs/2410.01234v1</id><updated>2026-10-16T17:59:59Z</updated>
          <published>2026-10-16T17:59:59Z</published><title>Scaling laws for
            tool-using agents</title>
          <summary>  We study how agents scale with tools.
        </summary><author><name>A. Author</name></author>
          <link href="http://arxiv.org/abs/2410.01234v1" rel="alternate" type="text/html"/>
          <link title="pdf" href="http://arxiv.org/pdf/2410.01234v1" rel="related" type="application/pdf"/></entry>
        </feed>
        """
        let stories = StoryMerge.stories(from: try FeedParser.parse(Data(xml.utf8), now: now), source: arxiv, now: now)
        XCTAssertEqual(stories.count, 1)
        XCTAssertEqual(stories[0].title, "Scaling laws for tool-using agents")
        XCTAssertEqual(stories[0].url.absoluteString, "https://arxiv.org/abs/2410.01234")
        XCTAssertEqual(stories[0].sourceText, "We study how agents scale with tools.")
    }

    func testDefaultArxivAddressIsTheSearchAPI() {
        let source = DefaultSources.all.first { $0.id == "arxiv" }
        XCTAssertEqual(source?.url?.host, "export.arxiv.org")
        XCTAssertEqual(DefaultSources.movedURLs["arxiv"]?.new, source?.url?.absoluteString)
    }

    func testCrossListsAreKept() {
        XCTAssertFalse(Research.isReplacement(item("2410.01234", type: "cross")))
        XCTAssertTrue(Research.isReplacement(item("2410.01234", type: "replace-cross")))
    }

    func testCanonicalArxivLinks() {
        let abs = "https://arxiv.org/abs/2410.01234"
        XCTAssertEqual(Research.canonicalArxiv(URL(string: "https://arxiv.org/pdf/2410.01234v2.pdf")!), abs)
        XCTAssertEqual(Research.canonicalArxiv(URL(string: "https://www.arxiv.org/abs/2410.01234v1")!), abs)
        XCTAssertEqual(Research.canonicalArxiv(URL(string: "https://arxiv.org/html/2410.01234v3")!), abs)
        XCTAssertNil(Research.canonicalArxiv(URL(string: "https://example.com/abs/2410.01234")!))
    }

    func testPaperStaysOutOfTheNewsUntilHackerNewsPicksItUp() {
        let papers = StoryMerge.merge(existing: [], incoming: StoryMerge.stories(from: [item("2410.01234")], source: arxiv, now: now), now: now)
        XCTAssertTrue(Research.isPaperOnly(papers[0]))

        let post = FeedItem(id: "hn-1", title: "Scaling laws for tool-using agents (arxiv.org)",
                            link: URL(string: "https://arxiv.org/pdf/2410.01234v1.pdf"), published: now, text: "", points: 420, comments: 90)
        let merged = StoryMerge.merge(existing: papers, incoming: StoryMerge.stories(from: [post], source: hn, now: now), now: now)
        XCTAssertEqual(merged.count, 1, "the post and the paper are one story")
        XCTAssertEqual(merged[0].points, 420)
        XCTAssertFalse(Research.isPaperOnly(merged[0]), "in the news now, so it can reach Top and Latest")
    }

    func testPostFirstThenPaperGivesThePostTheAbstract() {
        let post = FeedItem(id: "hn-1", title: "Scaling laws for tool-using agents", link: URL(string: "https://arxiv.org/abs/2410.01234"),
                            published: now, text: "", points: 300)
        let first = StoryMerge.merge(existing: [], incoming: StoryMerge.stories(from: [post], source: hn, now: now), now: now)
        let merged = StoryMerge.merge(existing: first, incoming: StoryMerge.stories(from: [item("2410.01234")], source: arxiv, now: now), now: now)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].sourceText, "We study how agents scale with tools.")
    }

    func testUnnoticedPapersExpireSooner() {
        let old = now.addingTimeInterval(-3 * 86_400)
        var paper = StoryMerge.stories(from: [item("2410.01234")], source: arxiv, now: old)[0]
        paper.published = old
        XCTAssertTrue(StoryMerge.merge(existing: [paper], incoming: [], now: now).isEmpty)
    }

    func testPapersCountFromWhenTech60SawThemNotWhenTheyWereSubmitted() {
        var paper = StoryMerge.stories(from: [item("2410.01234")], source: arxiv, now: now)[0]
        paper.published = now.addingTimeInterval(-4 * 86_400)
        XCTAssertEqual(StoryMerge.merge(existing: [paper], incoming: [], now: now.addingTimeInterval(3600)).count, 1)
    }

    func testResearchFeedIsFetchedAtMostEverySixHours() async {
        var snapshot = Snapshot()
        snapshot.status["arxiv"] = SourceStatus(lastAttempt: now, lastSuccess: now)
        snapshot.stories = StoryMerge.stories(from: [item("2410.01234")], source: arxiv, now: now)
        let engine = Engine(file: nil, summarizer: NoSummarizer(reason: "test"), initial: snapshot)
        let source = Source(id: "arxiv", name: "arXiv", kind: .research, url: URL(string: "https://rss.arxiv.org/rss/cs.AI"), isPrimary: false)
        let after = await engine.refresh(sources: [source], now: now.addingTimeInterval(3600))
        XCTAssertEqual(after.status["arxiv"]?.lastAttempt, now, "fetched an hour ago, so not asked again")
    }
}
