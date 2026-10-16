import XCTest
@testable import MDEditDiffCore

final class SourceTextTests: XCTestCase {
    private func bytes(_ s: String) -> Data { Data(s.utf8) }

    func testNoOpSaveIsByteIdenticalForEveryStyle() throws {
        let samples: [Data] = [
            bytes("# Title\n\nBody\n"),
            bytes("# Title\r\n\r\nBody\r\n"),
            bytes("# Title\rBody\r"),
            bytes("# Title\nmixed\r\nendings\rhere"),
            Data(SourceText.bom) + bytes("# BOM\r\n"),
            bytes(""),
            bytes("no newline at end"),
            bytes("Caf\u{00E9} and cafe\u{0301} and emoji \u{1F600}\n"),
            bytes("trailing spaces   \n\t\ttabs\n\n\n"),
        ]
        for data in samples {
            let s = try SourceText(data: data)
            XCTAssertEqual(s.data(for: s.text), data, "no-op save changed \(Array(data))")
            XCTAssertFalse(s.isEdited(s.text))
        }
    }

    func testEditKeepsCRLFAndBOM() throws {
        let s = try SourceText(data: Data(SourceText.bom) + bytes("a\r\nb\r\n"))
        XCTAssertTrue(s.hasBOM)
        XCTAssertEqual(s.lineEnding, .crlf)
        XCTAssertEqual(s.text, "a\nb\n")
        let out = s.data(for: "a\nb\nc\n")
        XCTAssertEqual(out, Data(SourceText.bom) + bytes("a\r\nb\r\nc\r\n"))
    }

    func testEditKeepsLFAndMissingFinalNewline() throws {
        let s = try SourceText(data: bytes("one\ntwo"))
        XCTAssertFalse(s.endsWithNewline)
        XCTAssertEqual(s.data(for: "one\ntwo!"), bytes("one\ntwo!"))
    }

    func testPastedCarriageReturnsAreNormalized() throws {
        let s = try SourceText(data: bytes("a\n"))
        XCTAssertEqual(s.data(for: "a\r\nb\r\n"), bytes("a\nb\n"))
    }

    func testCROnlyFile() throws {
        let s = try SourceText(data: bytes("a\rb\r"))
        XCTAssertEqual(s.lineEnding, .cr)
        XCTAssertEqual(s.data(for: "a\nb\nc\n"), bytes("a\rb\rc\r"))
    }

    func testMixedEndingsUseTheMostCommonStyleWhenEdited() throws {
        let s = try SourceText(data: bytes("a\r\nb\r\nc\nd"))
        XCTAssertTrue(s.hasMixedLineEndings)
        XCTAssertEqual(s.lineEnding, .crlf)
        XCTAssertEqual(s.data(for: "a\nb\nc\nd!"), bytes("a\r\nb\r\nc\r\nd!"))
    }

    func testDecomposedCharacterChangeIsSaved() throws {
        // "é" precomposed vs "e" + combining accent are equal as Swift Strings but different bytes.
        let s = try SourceText(data: bytes("caf\u{00E9}\n"))
        let edited = "cafe\u{0301}\n"
        XCTAssertTrue(s.isEdited(edited))
        XCTAssertEqual(s.data(for: edited), bytes(edited))
    }

    func testInvalidUTF8IsRefused() {
        XCTAssertThrowsError(try SourceText(data: Data([0x23, 0x20, 0xFF, 0xFE]))) { error in
            XCTAssertEqual(error as? SourceText.DecodeError, .notUTF8)
        }
    }

    func testLargeFile() throws {
        let line = "Paragraph with some words in it for a size test.\r\n"
        let data = bytes(String(repeating: line, count: 20_000))
        let s = try SourceText(data: data)
        XCTAssertEqual(s.data(for: s.text), data)
        XCTAssertEqual(s.data(for: s.text + "end\n").count, data.count + 5)
    }
}
