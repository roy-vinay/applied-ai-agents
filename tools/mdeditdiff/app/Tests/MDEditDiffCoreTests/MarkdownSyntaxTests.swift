import XCTest
@testable import MDEditDiffCore

final class MarkdownSyntaxTests: XCTestCase {
    private func matches(_ pattern: String, _ text: String) throws -> [String] {
        let re = try NSRegularExpression(pattern: pattern, options: MarkdownSyntax.options)
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
    }

    func testAllPatternsCompile() throws {
        for p in MarkdownSyntax.all {
            XCTAssertNoThrow(try NSRegularExpression(pattern: p, options: MarkdownSyntax.options), p)
        }
    }

    func testPatternsMatchWhatTheyShould() throws {
        XCTAssertEqual(try matches(MarkdownSyntax.heading, "# One\ntext\n### Three\n#nospace"), ["# One", "### Three"])
        XCTAssertEqual(try matches(MarkdownSyntax.bold, "a **b** c __d__"), ["**b**", "__d__"])
        XCTAssertEqual(try matches(MarkdownSyntax.italic, "a *b* c **d** snake_case_name _e_"), ["*b*", "_e_"])
        XCTAssertEqual(try matches(MarkdownSyntax.inlineCode, "use `x` and `y`"), ["`x`", "`y`"])
        XCTAssertEqual(try matches(MarkdownSyntax.link, "[a](b) ![c](d.png)"), ["[a](b)", "![c](d.png)"])
        XCTAssertEqual(try matches(MarkdownSyntax.listMarker, "- a\n  2. b\n-not"), ["-", "  2."])
        XCTAssertEqual(try matches(MarkdownSyntax.codeFence, "x\n```js\ncode\n```\ny").count, 1)
        XCTAssertEqual(try matches(MarkdownSyntax.codeFence, "```\nunclosed\nstill code").count, 1)
        XCTAssertEqual(try matches(MarkdownSyntax.rule, "---\n* * *\n--"), ["---", "* * *"])
    }
}
