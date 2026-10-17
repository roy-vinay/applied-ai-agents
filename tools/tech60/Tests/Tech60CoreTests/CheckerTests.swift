import XCTest
@testable import Tech60Core

final class CheckerTests: XCTestCase {
    let source = """
    Sample Labs today released Atlas 2, a coding model with a 400,000 token context window.
    Atlas 2 scores 72.5 percent on the team's internal coding benchmark, up from 61 percent.
    It is not available in the European Union yet. It is available in the API today at the same price as Atlas 1.
    """

    func testFaithfulSummaryPasses() {
        let r = SummaryChecker.check(summary: "Sample Labs released Atlas 2, a coding model with a 400,000 token context window. It scores 72.5 percent on the internal coding benchmark, up from 61 percent.", source: source)
        XCTAssertTrue(r.passed, r.reason ?? "")
        XCTAssertEqual(r.evidence.count, 2)
    }

    func testWrongNumberFails() {
        let r = SummaryChecker.check(summary: "Sample Labs released Atlas 2 with a 500,000 token context window.", source: source)
        XCTAssertFalse(r.passed)
        XCTAssertTrue(r.reason?.contains("500000") == true, r.reason ?? "")
    }

    func testInventedNameFails() {
        let r = SummaryChecker.check(summary: "Sample Labs released Atlas 2 together with Microsoft, a coding model with a large context window.", source: source)
        XCTAssertFalse(r.passed)
        XCTAssertTrue(r.reason?.contains("Microsoft") == true, r.reason ?? "")
    }

    func testAddedNegationFails() {
        let r = SummaryChecker.check(summary: "Atlas 2 is not available in the API at the same price as Atlas 1.", source: source)
        XCTAssertFalse(r.passed, "the source says it IS available in the API")
    }

    func testUnsupportedSentenceFails() {
        let r = SummaryChecker.check(summary: "Sample Labs released Atlas 2. Analysts expect strong revenue growth for the company next quarter.", source: source)
        XCTAssertFalse(r.passed)
    }

    func testTooLongFails() {
        let long = Array(repeating: "Atlas 2 coding model context window", count: 13).joined(separator: " ") + "."
        XCTAssertFalse(SummaryChecker.check(summary: long, source: source).passed)
    }

    func testDemoSummariesPass() {
        let demo = Demo.snapshot()
        let checked = demo.stories.filter { if case .checked = $0.summary { return true } else { return false } }
        XCTAssertEqual(checked.count, 2, "both sample summaries should pass the checker")
    }
}
