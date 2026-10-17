import XCTest
@testable import Tech60Core

private struct EchoSummarizer: Summarizer {
    let reply: String
    var name: String { "Echo" }
    func availability() async -> String? { nil }
    func summarize(title: String, text: String) async throws -> String { reply }
}

final class OnDemandTests: XCTestCase {
    private let body = String(repeating: "Filler sentence about the release schedule and rollout plans for developers. ", count: 4)
        + "Example Cloud now runs scheduled jobs in 12 regions, billed per second."

    private func story(_ summary: SummaryState = .none) -> Story {
        Story(id: "s1", sourceID: "verge", sourceName: "The Verge", title: "Scheduled jobs come to 12 regions",
              url: URL(string: "https://example.com/a")!, published: Date(), firstSeen: Date(),
              sourceText: body, isPrimary: false, summary: summary)
    }

    func testReaderCanSummarizeAPublisherStory() async {
        let engine = Engine(file: nil, summarizer: EchoSummarizer(reply: "Example Cloud now runs scheduled jobs in 12 regions, billed per second."),
                            initial: Snapshot(stories: [story()]))
        let marked = await engine.requestSummary(id: "s1")
        XCTAssertEqual(marked.stories[0].summary, .pending)
        let done = await engine.finishSummary(id: "s1")
        guard case .checked = done.stories[0].summary else { return XCTFail("expected checked, got \(done.stories[0].summary)") }
    }

    func testUnfaithfulOnDemandSummaryIsWithheld() async {
        let engine = Engine(file: nil, summarizer: EchoSummarizer(reply: "Example Cloud now runs jobs in 40 regions for free."),
                            initial: Snapshot(stories: [story()]))
        _ = await engine.requestSummary(id: "s1")
        let done = await engine.finishSummary(id: "s1")
        guard case .withheld = done.stories[0].summary else { return XCTFail("expected withheld") }
    }

    func testNoModelExplainsWhy() async {
        let engine = Engine(file: nil, summarizer: NoSummarizer(reason: "No model here."), initial: Snapshot(stories: [story()]))
        let marked = await engine.requestSummary(id: "s1")
        XCTAssertEqual(marked.stories[0].summary, .withheld(reason: "No model here."))
    }
}
