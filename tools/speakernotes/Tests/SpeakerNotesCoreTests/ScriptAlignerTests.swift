import XCTest
@testable import SpeakerNotesCore

final class ScriptAlignerTests: XCTestCase {
    let script = """
        An agent is a model that can take actions, not just answer questions. It reads a goal, picks a tool, \
        and checks the result. It keeps going until the goal is met, or it asks you. Start with read-only tools, \
        then add actions one at a time.
        """

    func index(_ a: ScriptAligner, _ word: String, after: Int = -1) -> Int {
        a.words.indices.first { $0 > after && a.words[$0].text == word }!
    }

    func say(_ a: ScriptAligner, _ phrase: String) -> Int? {
        a.update(heard: phrase.split(separator: " ").map(String.init))
    }

    func testTokenizeKeepsRanges() {
        let a = ScriptAligner(text: "Hello, **world**! Don't stop.")
        XCTAssertEqual(a.words.map(\.text), ["hello", "world", "dont", "stop"])
        XCTAssertEqual(("Hello, **world**! Don't stop." as NSString).substring(with: a.words[1].range), "world")
        XCTAssertFalse(ScriptAligner(text: "the and").words.contains { $0.isContent })
    }

    func testFollowsReadingWordByWord() {
        let a = ScriptAligner(text: script)
        XCTAssertEqual(say(a, "an agent is a model"), index(a, "model"))
        XCTAssertEqual(say(a, "a model that can take actions"), index(a, "actions"))
        XCTAssertEqual(say(a, "not just answer questions"), index(a, "questions"))
    }

    func testToleratesMisheardWords() {
        let a = ScriptAligner(text: script)
        a.reset(to: index(a, "result"))
        let moved = say(a, "it keeps going untill the goal")
        XCTAssertEqual(moved, index(a, "goal", after: index(a, "result")))
    }

    func testAdLibsAndFillerDontMove() {
        let a = ScriptAligner(text: script)
        a.reset(to: index(a, "questions"))
        let start = a.position
        XCTAssertNil(say(a, "and the"))
        XCTAssertNil(say(a, "great question thanks Dylan"))
        XCTAssertEqual(a.position, start)
    }

    func testBigJumpNeedsTwoReadings() {
        let a = ScriptAligner(text: script)
        XCTAssertNil(say(a, "it keeps going until the goal is met"))
        XCTAssertEqual(say(a, "it keeps going until the goal is met"), index(a, "met"))
    }

    func testOneStrayMatchFarAheadIsIgnored() {
        let a = ScriptAligner(text: script)
        XCTAssertNil(say(a, "tools then"))   // "tools" is far ahead, but one word proves nothing
        XCTAssertEqual(a.position, -1)
    }

    func testGoingBackNeedsStrongEvidence() {
        let a = ScriptAligner(text: script)
        a.reset(to: index(a, "asks"))
        let start = a.position
        XCTAssertNil(say(a, "it reads a goal"))
        XCTAssertNil(say(a, "it reads a goal"))
        XCTAssertEqual(a.position, start)
        XCTAssertNil(say(a, "it reads a goal picks a tool"))
        XCTAssertEqual(say(a, "it reads a goal picks a tool"), index(a, "tool"))
    }

    func testRecognitionStyleMistakes() {
        let a = ScriptAligner(text: "Built on DispatchOS, the routing engines plan every delivery for our dispatchers.")
        XCTAssertNotNil(say(a, "built on dispatch os the routing engine"))
        XCTAssertEqual(a.words[a.position].text, "engines")
        XCTAssertNotNil(say(a, "plan every delivery for our dispatcher"))
        XCTAssertEqual(a.words[a.position].text, "dispatchers")
    }

    func testFindsYouAfterSkippingAhead() {
        let a = ScriptAligner(text: script)
        for _ in 0..<3 { XCTAssertNil(say(a, "blah blah weather sunny")) }
        XCTAssertNil(say(a, "start with read only tools then add actions"))
        XCTAssertEqual(say(a, "start with read only tools then add actions"), index(a, "actions", after: index(a, "start")))
    }

    func testRepeatedWordsPreferTheNextOccurrence() {
        let a = ScriptAligner(text: script)
        a.reset(to: index(a, "keeps"))
        XCTAssertEqual(say(a, "going until the goal"), index(a, "goal", after: index(a, "keeps")))
    }
}
