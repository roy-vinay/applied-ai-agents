import XCTest
@testable import Tech60Core

final class ImageTests: XCTestCase {
    func testMediaContentInRSS() throws {
        let rss = """
        <rss version="2.0" xmlns:media="http://search.yahoo.com/mrss/"><channel><item>
        <title>Hello</title><link>https://example.com/a</link>
        <media:content url="https://cdn.example.com/a.jpg" medium="image"/>
        </item></channel></rss>
        """
        let items = try FeedParser.parse(Data(rss.utf8))
        XCTAssertEqual(items.first?.image?.absoluteString, "https://cdn.example.com/a.jpg")
    }

    func testInlineImageAndHTTPRejected() throws {
        let rss = """
        <rss version="2.0"><channel>
        <item><title>A</title><link>https://example.com/a</link><description><![CDATA[<p><img src="https://cdn.example.com/b.png"> text</p>]]></description></item>
        <item><title>B</title><link>https://example.com/b</link><description><![CDATA[<img src="http://insecure.example.com/c.png">]]></description></item>
        </channel></rss>
        """
        let items = try FeedParser.parse(Data(rss.utf8))
        XCTAssertEqual(items[0].image?.host, "cdn.example.com")
        XCTAssertNil(items[1].image, "only https pictures")
    }

    func testPreviewImageEitherAttributeOrder() {
        XCTAssertEqual(HTMLText.previewImage(inHTML: #"<meta property="og:image" content="https://x.com/1.jpg">"#)?.lastPathComponent, "1.jpg")
        XCTAssertEqual(HTMLText.previewImage(inHTML: #"<meta content="https://x.com/2.jpg" property="og:image" />"#)?.lastPathComponent, "2.jpg")
        XCTAssertEqual(HTMLText.previewImage(inHTML: #"<meta name="twitter:image" content="https://x.com/3.jpg&amp;w=1">"#)?.absoluteString, "https://x.com/3.jpg&w=1")
    }

    func testFirstReportAndDeveloping() {
        func s(_ id: String, _ src: String, minutesAgo: Double) -> Story {
            Story(id: id, sourceID: src, sourceName: src, title: "Atlas 2 coding model launch", url: URL(string: "https://e.com/\(id)")!,
                  published: Date().addingTimeInterval(-minutesAgo * 60), firstSeen: Date(), sourceText: "", isPrimary: false)
        }
        let c = StoryCluster(stories: [s("a", "Verge", minutesAgo: 10), s("b", "Northwind", minutesAgo: 40), s("c", "HN", minutesAgo: 20)])
        XCTAssertEqual(c.firstReport.sourceName, "Northwind")
        XCTAssertTrue(c.isDeveloping())
    }
}
