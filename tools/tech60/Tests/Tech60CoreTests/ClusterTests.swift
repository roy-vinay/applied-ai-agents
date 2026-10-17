import XCTest
@testable import Tech60Core

final class ClusterTests: XCTestCase {
    private func s(_ id: String, _ source: String, _ title: String, primary: Bool = false, hoursAgo: Double = 1, text: String = "") -> Story {
        Story(id: id, sourceID: source, sourceName: source, title: title, url: URL(string: "https://example.com/\(id)")!,
              published: Date().addingTimeInterval(-hoursAgo * 3600), firstSeen: Date(), sourceText: text, isPrimary: primary)
    }

    func testSameLaunchFromThreeSourcesIsOneRow() {
        let stories = [
            s("a", "OpenAI", "Introducing GPT-6 with a 2 million token context window", primary: true),
            s("b", "The Verge", "OpenAI launches GPT-6, and it has a 2 million token context window"),
            s("c", "HN", "GPT-6 (openai.com)"),
            s("d", "Ars", "Nvidia reports record quarterly data center revenue"),
            s("e", "Apple", "Xcode 27 adds Swift Assist for everyone", primary: true),
        ]
        let clusters = Clustering.cluster(stories)
        XCTAssertEqual(clusters.count, 3)
        let gpt = clusters.first { $0.stories.count == 3 }
        XCTAssertEqual(gpt?.lead.id, "a", "the company's own post leads")
    }

    func testDifferentStoriesOnABusyAppleDayStaySeparate() {
        let stories = [
            s("a", "Verge", "Apple iPhone 18 Pro review: the best camera yet"),
            s("b", "Ars", "Apple iPhone sales fall in China"),
            s("c", "Techmeme", "Apple iPhone shipments slow as Huawei gains"),
            s("d", "HN", "Apple iPhone repair program expands to more countries"),
        ]
        XCTAssertEqual(Clustering.cluster(stories).count, 4)
    }

    func testSameSourceNeverMerges() {
        let stories = [s("a", "HN", "Rust 2.0 released"), s("b", "HN", "Rust 2.0 released: what changed")]
        XCTAssertEqual(Clustering.cluster(stories).count, 2)
    }

    func testTopicsMatchWholeWords() {
        let apple = Topics.builtIn.first { $0.id == "apple" }!
        XCTAssertTrue(Topics.matches(s("a", "x", "Machine learning on a budget"), in: [apple]).isEmpty)
        XCTAssertEqual(Topics.matches(s("b", "x", "The new Mac mini is tiny"), in: [apple]).map(\.id), ["apple"])
        let custom = Topics.custom(name: "Robotics", keywords: "robot, robots, humanoid")!
        XCTAssertEqual(Topics.matches(s("c", "x", "A humanoid that folds laundry"), in: [custom]).count, 1)
    }

    func testBriefPrefersWideCoverageAndFollowedTopics() {
        let stories = [
            s("a", "OpenAI", "Introducing GPT-6 with a 2 million token context window", primary: true),
            s("b", "The Verge", "OpenAI launches GPT-6 with a 2 million token context window"),
            s("c", "HN", "A tiny Forth interpreter in 200 lines"),
            s("d", "Ars", "Nvidia reports record quarterly data center revenue"),
            s("e", "HN", "My weekend woodworking bench", hoursAgo: 40),
        ]
        let clusters = Clustering.cluster(stories)
        let chips = Topics.builtIn.filter { $0.id == "chips" }
        let brief = Brief.pick(clusters, topics: chips, since: Date().addingTimeInterval(-24 * 3600), count: 2)
        XCTAssertEqual(Set(brief.map(\.lead.id)), ["a", "d"])
        XCTAssertTrue(Brief.body(brief).contains("(2 sources)"))
    }

    func testDemoHasAClusterWithThreeSources() {
        let clusters = Clustering.cluster(Demo.snapshot().stories)
        XCTAssertEqual(clusters.first { $0.lead.id == "s1" }?.stories.count, 3)
    }
}
