import XCTest
@testable import Tech60Core

final class QualityTests: XCTestCase {
    private func s(_ title: String, source: String = "verge", points: Int? = nil) -> Story {
        var story = Story(id: title, sourceID: source, sourceName: source, title: title, url: URL(string: "https://e.com/\(abs(title.hashValue))")!,
                          published: Date(), firstSeen: Date(), sourceText: "", isPrimary: false)
        story.points = points
        return story
    }

    func testNoiseIsDropped() {
        for title in ["The best laptops for students in 2026", "Apple Watch Series 12 review: a quieter upgrade",
                      "Save $200 on the MacBook Air today", "AirPods Pro are 30% off right now",
                      "How to turn on Live Captions on your Mac", "Nintendo announces a new Zelda game for Switch 2",
                      "Hands-on with the new Pixel Fold"] {
            XCTAssertTrue(NoiseFilter.isNoise(s(title)), title)
        }
    }

    func testRealNewsIsKept() {
        for title in ["OpenAI signs a $10B compute deal with Microsoft", "EU regulators open a review of the Figma deal",
                      "Nvidia reports record data center revenue", "Game theory explains the new chip export rules",
                      "Best Buy cuts 2,000 jobs as PC sales slow"] {
            XCTAssertFalse(NoiseFilter.isNoise(s(title)), title)
        }
    }

    func testHackerNewsNeedsPoints() {
        XCTAssertTrue(NoiseFilter.isNoise(s("A tiny Forth in 200 lines", source: "hn", points: 120)))
        XCTAssertFalse(NoiseFilter.isNoise(s("A tiny Forth in 200 lines", source: "hn", points: 210)))
        XCTAssertTrue(NoiseFilter.isNoise(s("Show HN: My weekend app", source: "hn", points: 300)))
        XCTAssertFalse(NoiseFilter.isNoise(s("Show HN: My weekend app", source: "hn", points: 900)))
    }

    func testEditorReplyParsing() {
        XCTAssertEqual(EditorPrompt.parse("1: 5\n2. 2\nnoise\n4) 3", count: 4), [5, 2, nil, 3])
        XCTAssertEqual(EditorPrompt.parse("9: 5", count: 2), [nil, nil], "out-of-range numbers are ignored")
    }

    func testEditorDropsLowRatedFromTop() {
        var low = s("Company updates its logo", source: "techcrunch"); low.editorScore = 1
        var high = s("Major chip export rules change", source: "techcrunch"); high.editorScore = 5
        let clusters = Clustering.cluster([low, high])
        let top = Hotness.hot(clusters, minimumCount: 8)
        XCTAssertEqual(top.map(\.lead.title), ["Major chip export rules change"])
    }

    func testTasteMovesSimilarStories() {
        let robots = StoryCluster(stories: [s("Humanoid robots start warehouse trials")])
        let robots2 = StoryCluster(stories: [s("Another humanoid robots startup raises money", source: "techcrunch")])
        var taste = Taste()
        XCTAssertEqual(taste.multiplier(for: robots2), 1)
        taste.record(robots, more: true)
        XCTAssertGreaterThan(taste.multiplier(for: robots2), 1)
        taste.record(robots, more: false); taste.record(robots, more: false)
        XCTAssertLessThan(taste.multiplier(for: robots2), 1)
    }

    func testTechmemeAndCoverageOutweighHNPoints() {
        let essay = StoryCluster(stories: [s("An essay on undo history in text editors", source: "hn", points: 3_000)])
        let news = StoryCluster(stories: [s("Chip export rules tightened", source: "techmeme"), s("US tightens chip export rules", source: "verge")])
        XCTAssertGreaterThan(Hotness.heat(news), Hotness.heat(essay))
    }
}
