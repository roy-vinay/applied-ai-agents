import XCTest
@testable import SpeakerNotesCore

final class SlideMatcherTests: XCTestCase {
    let talk = NotesParser.slides(in: """
        # What is an AI agent?
        An agent takes actions.
        ---
        ## The agent loop
        Perceive, plan, act, reflect.
        ---
        ## Keeping agents safe
        Start read-only.
        ---
        ## Thank you
        Questions.
        """)

    let numbered = NotesParser.slides(in: """
        ## 1. Opening
        Hello.
        ---
        ## 2. The problem
        Why.
        ---
        ## 4. Pricing
        Skipped slide 3 on purpose.
        ---
        ## 5. Thank you
        Bye.
        """)

    func testDeclaredNumbers() {
        XCTAssertEqual(numbered.map(SlideMatcher.declaredNumber(of:)), [1, 2, 4, 5])
        XCTAssertEqual(talk.map(SlideMatcher.declaredNumber(of:)), [nil, nil, nil, nil])
        XCTAssertEqual(SlideMatcher.leadingNumber("Slide 12: Routing"), 12)
        XCTAssertEqual(SlideMatcher.leadingNumber("7) Wrap up"), 7)
        XCTAssertNil(SlideMatcher.leadingNumber("2024 plans"))
        XCTAssertNil(SlideMatcher.leadingNumber("3PL capacity"))
    }

    func testIndexForSlideNumberInOrder() {
        XCTAssertEqual(SlideMatcher.index(forSlideNumber: 1, in: talk), 0)
        XCTAssertEqual(SlideMatcher.index(forSlideNumber: 4, in: talk), 3)
        XCTAssertNil(SlideMatcher.index(forSlideNumber: 9, in: talk))
        XCTAssertNil(SlideMatcher.index(forSlideNumber: 0, in: talk))
    }

    func testIndexForSlideNumberUsesDeclaredNumbers() {
        XCTAssertEqual(SlideMatcher.index(forSlideNumber: 2, in: numbered), 1)
        XCTAssertEqual(SlideMatcher.index(forSlideNumber: 3, in: numbered), 1) // no notes for 3: stay on 2
        XCTAssertEqual(SlideMatcher.index(forSlideNumber: 4, in: numbered), 2)
        XCTAssertEqual(SlideMatcher.index(forSlideNumber: 5, in: numbered), 3)
    }

    func testKeyWords() {
        XCTAssertEqual(SlideMatcher.keyWords("## 7. The Agent Loop!"), ["agent", "loop"])
        XCTAssertEqual(SlideMatcher.keyWords("Slide 3: What is an AI agent?"), ["ai", "agent"])
    }

    func testMatchesTitleOnScreen() {
        let m = SlideMatcher.match(screenTitle: "The agent loop",
                                   screenLines: ["The agent loop", "Every agent repeats four steps", "Perceive", "Plan", "Act", "Reflect"],
                                   slides: talk, near: 0)
        XCTAssertEqual(m?.index, 1)
        XCTAssertTrue(m.map(SlideMatcher.isConfident) ?? false)
    }

    func testMatchesWithOCRNoise() {
        let m = SlideMatcher.match(screenTitle: "Keeping agents safe.", screenLines: ["Keepinq agents safe.", "1 Start"],
                                   slides: talk, near: 0)
        XCTAssertEqual(m?.index, 2)
    }

    func testUnrelatedScreenIsNotConfident() {
        let m = SlideMatcher.match(screenTitle: "Quarterly revenue", screenLines: ["Quarterly revenue", "Q3"],
                                   slides: talk, near: 0)
        XCTAssertFalse(m.map(SlideMatcher.isConfident) ?? false)
    }

    func testDuplicateTitlesPickTheClosest() {
        let slides = NotesParser.slides(in: "## Intro\na\n---\n## Thank you\nb\n---\n## Appendix\nc\n---\n## Thank you\nd")
        XCTAssertEqual(SlideMatcher.match(screenTitle: "Thank you", screenLines: ["Thank you"], slides: slides, near: 3)?.index, 3)
        XCTAssertEqual(SlideMatcher.match(screenTitle: "Thank you", screenLines: ["Thank you"], slides: slides, near: 0)?.index, 1)
    }

    func testEditorChromeDoesNotWinOverTheTitle() {
        // A browser editor shows other slide titles in its filmstrip; the large title decides.
        let m = SlideMatcher.match(screenTitle: "Keeping agents safe",
                                   screenLines: ["File Edit View", "What is an AI agent?", "The agent loop", "Keeping agents safe", "Thank you"],
                                   slides: talk, near: 1)
        XCTAssertEqual(m?.index, 2)
    }
}
