import XCTest
@testable import Tech60Core

final class FeedTests: XCTestCase {
    let now = ISO8601DateFormatter().date(from: "2026-10-17T12:00:00Z")!

    func testRSSWithFullContent() throws {
        let xml = """
        <?xml version="1.0"?>
        <rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
        <channel><title>Changelog</title><link>https://example.com</link>
        <item>
          <title>Open source license compliance &amp; more</title>
          <link>https://example.com/post?utm_source=rss</link>
          <guid isPermaLink="false">post-1</guid>
          <pubDate>Thu, 16 Oct 2026 18:30:00 +0000</pubDate>
          <description>Short teaser.</description>
          <content:encoded><![CDATA[<p>Full <b>text</b> of the post.</p><script>alert(1)</script><p>Second paragraph.</p>]]></content:encoded>
        </item>
        </channel></rss>
        """
        let items = try FeedParser.parse(Data(xml.utf8), now: now)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].title, "Open source license compliance & more")
        XCTAssertEqual(items[0].id, "post-1")
        XCTAssertEqual(items[0].text, "Full text of the post.\nSecond paragraph.")
        XCTAssertNotNil(items[0].published)
    }

    func testAtom() throws {
        let xml = """
        <feed xmlns="http://www.w3.org/2005/Atom"><title>Blog</title>
        <entry><title>Hello</title><id>tag:example.com,2026:1</id>
          <link rel="alternate" href="https://example.com/hello"/><link rel="enclosure" href="https://example.com/a.mp3"/>
          <updated>2026-10-16T10:00:00Z</updated><summary>Summary text</summary></entry>
        </feed>
        """
        let items = try FeedParser.parse(Data(xml.utf8), now: now)
        XCTAssertEqual(items.first?.link?.absoluteString, "https://example.com/hello")
        XCTAssertEqual(items.first?.text, "Summary text")
        XCTAssertNotNil(items.first?.published)
    }

    func testNotAFeed() {
        XCTAssertThrowsError(try FeedParser.parse(Data("<html><body>hi</body></html>".utf8), now: now))
    }

    func testFutureAndMissingDates() {
        XCTAssertNil(FeedDates.parse("", now: now))
        XCTAssertNil(FeedDates.parse("2027-01-01T00:00:00Z", now: now), "dates far in the future are unreliable")
        XCTAssertNotNil(FeedDates.parse("Thu, 16 Oct 2026 18:30:00 GMT", now: now))
    }

    func testWordPressFooterRemoved() {
        let text = HTMLText.plain("<p>Real content here.</p><p>The post <a href='x'>Thing</a> appeared first on The GitHub Blog.</p>")
        XCTAssertEqual(text, "Real content here.")
    }

    func testEntities() {
        XCTAssertEqual(HTMLText.decodeEntities("It&#8217;s &quot;new&quot; &#x2014; ok"), "It\u{2019}s \"new\" \u{2014} ok")
    }
}

final class MergeTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let source = Source(id: "a", name: "A", url: URL(string: "https://a.com/feed"), isPrimary: true)

    func item(_ id: String, _ url: String, text: String = "") -> FeedItem {
        FeedItem(id: id, title: "T \(id)", link: URL(string: url), published: nil, text: text)
    }

    func testFirstSeenKeptAndDuplicatesByURLDropped() {
        let first = StoryMerge.merge(existing: [], incoming: StoryMerge.stories(from: [item("1", "https://a.com/x")], source: source, now: t0), now: t0)
        let later = t0.addingTimeInterval(600)
        let other = Source(id: "b", name: "B", url: nil, isPrimary: false)
        let incoming = StoryMerge.stories(from: [item("1", "https://a.com/x")], source: source, now: later)
            + StoryMerge.stories(from: [item("9", "https://A.com/x/?utm_source=feed#top")], source: other, now: later)
        let merged = StoryMerge.merge(existing: first, incoming: incoming, now: later)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].firstSeen, t0)
    }

    func testNewSinceYouLooked() {
        var snap = Snapshot(stories: StoryMerge.stories(from: [item("1", "https://a.com/1")], source: source, now: t0), lastViewed: t0.addingTimeInterval(-60))
        XCTAssertEqual(snap.newCount, 1)
        snap.lastViewed = t0.addingTimeInterval(60)
        XCTAssertEqual(snap.newCount, 0)
        XCTAssertEqual(Snapshot(stories: snap.stories, lastViewed: nil).newCount, 0, "first launch shows nothing as new")
    }

    func testPublisherStoriesAreNeverSummarized() {
        let publisher = Source(id: "p", name: "P", url: nil, isPrimary: false)
        let s = StoryMerge.stories(from: [item("1", "https://p.com/1", text: "Body")], source: publisher, now: t0)
        XCTAssertEqual(s[0].summary, .none)
        XCTAssertEqual(s[0].sourceText, "", "publisher text isn't even stored")
    }

    func testOldStoriesPruned() {
        let old = StoryMerge.stories(from: [item("1", "https://a.com/1")], source: source, now: t0)
        XCTAssertTrue(StoryMerge.merge(existing: old, incoming: [], now: t0.addingTimeInterval(8 * 86_400)).isEmpty)
    }
}
