import XCTest
@testable import SecondChairCore

final class TextTests: XCTestCase {
    func testNumbersNormalise() {
        XCTAssertEqual(Lexicon.numbers("Revenue grew to $31M"), ["31m"])
        XCTAssertEqual(Lexicon.numbers("31 million dollars"), ["31m"])
        XCTAssertEqual(Lexicon.numbers("margin hit 61 percent"), ["61%"])
        XCTAssertEqual(Lexicon.numbers("margin hit 61%"), ["61%"])
        XCTAssertEqual(Lexicon.numbers("1,200 users and 2.30 hours"), ["1200", "2.3"])
        XCTAssertTrue(Lexicon.numbers("no figures here").isEmpty)
    }

    func testTermsDropStopwordsAndStem() {
        XCTAssertEqual(Lexicon.terms("Tell me about the launches you shipped"), ["launch", "ship"])
    }

    func testNamesSkipSentenceStarts() {
        XCTAssertEqual(Lexicon.names("We grew at Lumen Freight. Then Tailspin copied us."), ["Lumen", "Freight", "Tailspin"])
    }
}

final class ChunkerTests: XCTestCase {
    func testHeadingsAndFrontMatter() {
        let md = "---\ntags: [x]\n---\n# Stories\n\n## Support\n\nWe cut response time.\n\n## Launch\n\nIt broke.\n"
        let chunks = Chunker.chunk(text: md, file: "/p/story.md", folder: "/p", markdown: true)
        XCTAssertEqual(chunks.count, 2)
        XCTAssertEqual(chunks[0].headings, ["Stories", "Support"])
        XCTAssertEqual(chunks[0].text, "We cut response time.")
        XCTAssertEqual(chunks[1].sourceLine, "story.md › Stories › Launch")
        XCTAssertFalse(chunks.contains { $0.text.contains("tags") })
    }

    func testLongParagraphSplitsAtSentences() {
        let long = Array(repeating: "This sentence is about fifty characters long, roughly.", count: 30).joined(separator: " ")
        let chunks = Chunker.chunk(text: long, file: "a.txt", folder: "/", markdown: false)
        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertTrue(chunks.allSatisfy { $0.text.count <= Chunker.hardLimit })
    }
}

/// A fake model that returns a fixed reply, to exercise routing and the grounding check.
struct FakeModel: ModelClient {
    var name: String
    var reply: String
    func complete(system: String, prompt: String) async throws -> String { reply }
}

final class AnsweringTests: XCTestCase {
    var index: CorpusIndex!

    override func setUp() {
        let md = """
        # Numbers
        ## Lumen
        Revenue grew from $12M to $31M ARR over two years. Gross margin improved from 48 percent to 61 percent.
        ## Team
        Team: 6 product managers and 4 designers.
        # Stories
        ## Support
        Median first response fell from 41 hours to 3 hours after AI triage, with no new headcount.
        """
        index = CorpusIndex(chunks: Chunker.chunk(text: md, file: "/pack/numbers.md", folder: "/pack", markdown: true))
    }

    func testGroundedWithExtractWhenNoModel() async {
        let r = Retriever(index: index)
        let hits = await r.retrieve("How much did revenue grow at Lumen?")
        let card = await Answerer().answer("How much did revenue grow at Lumen?", hits: hits)
        XCTAssertEqual(card.label, .grounded)
        XCTAssertEqual(card.answeredBy, "extract")
        XCTAssertTrue(card.answer?.contains("$31M") ?? false)
    }

    func testOffTopicIsNotInDocs() async {
        let r = Retriever(index: index)
        let hits = await r.retrieve("What's your salary expectation?")
        let card = await Answerer().answer("What's your salary expectation?", hits: hits)
        XCTAssertEqual(card.label, .notInDocs)
        XCTAssertNil(card.answer)
    }

    func testInventedFigureIsWithheld() async {
        let r = Retriever(index: index)
        let q = "How much did revenue grow at Lumen?"
        let hits = await r.retrieve(q)
        let liar = FakeModel(name: "fast", reply: "Revenue grew to $45M.")
        let card = await Answerer(fast: liar).answer(q, hits: hits)
        XCTAssertEqual(card.label, .grounded)
        XCTAssertNil(card.answer)
        XCTAssertTrue(card.withheld?.contains("45m") ?? false)
        XCTAssertFalse(card.passages.isEmpty, "the passage still shows when the answer is withheld")
    }

    func testFastFailureFallsToQuality() async {
        let r = Retriever(index: index)
        let q = "How much did revenue grow at Lumen?"
        let hits = await r.retrieve(q)
        let card = await Answerer(fast: FakeModel(name: "fast", reply: "It hit $50M."),
                                  quality: FakeModel(name: "quality", reply: "We went from $12M to $31M ARR in two years."))
            .answer(q, hits: hits)
        XCTAssertEqual(card.answeredBy, "quality")
    }

    func testModelRefusalBecomesNotInDocs() async {
        let r = Retriever(index: index)
        let q = "How much did revenue grow at Lumen?"
        let hits = await r.retrieve(q)
        let card = await Answerer(fast: FakeModel(name: "fast", reply: "NOT_COVERED")).answer(q, hits: hits)
        XCTAssertEqual(card.label, .grounded, "a strong match in your doc outranks the model's doubt")
        XCTAssertEqual(card.answeredBy, "extract")
    }

    func testFollowUpCarriesContext() async {
        let r = Retriever(index: index)
        XCTAssertTrue(Retriever.isFollowUp("And why was that?"))
        XCTAssertFalse(Retriever.isFollowUp("What would you do in your first 90 days?"))
        let w = r.weightedTerms("And why was that?", previous: ["How did gross margin change?"])
        XCTAssertEqual(w["margin"], 0.5)
    }

    func testPrimaryPackRanksFirst() async {
        var chunks = index.chunks
        chunks.append(Chunk(id: "old#0", file: "/vault/old.md", headings: ["Lumen"],
                            text: "Revenue grew from $12M to $25M ARR.", folder: "/vault"))
        let r = Retriever(index: CorpusIndex(chunks: chunks), primaryFolder: "/pack")
        let hits = await r.retrieve("How much did revenue grow at Lumen?")
        XCTAssertEqual(hits.first?.chunk.folder, "/pack")
    }
}

final class PreparedAnswerTests: XCTestCase {
    let doc = """
    # Prep
    ## Why are you looking for a new job?
    I want a bigger canvas.

    Q: What's your management style?
    A: Outcomes over tasks.

    **How do you handle conflict?**
    I find the missing fact.

    ## Questions to ask them
    - What would make year one a success?
    - Where does product sit?
    """

    func testQuestionFormsBecomePreparedAnswers() {
        let chunks = Chunker.chunk(text: doc, file: "/p/q.md", folder: "/p", markdown: true)
        let prepared = chunks.filter { $0.question != nil }
        XCTAssertEqual(prepared.map(\.question), ["Why are you looking for a new job?", "What's your management style?", "How do you handle conflict?"])
        XCTAssertEqual(prepared.map(\.text), ["I want a bigger canvas.", "Outcomes over tasks.", "I find the missing fact."])
        XCTAssertEqual(prepared.map(\.headings), [["Prep", "Why are you looking for a new job?"], ["Prep"], ["Prep"]])
        XCTAssertTrue(chunks.contains { $0.question == nil && $0.text.contains("Where does product sit?") },
                      "a bulleted list of questions to ask is not a set of prepared answers")
    }

    func testMatchedQuestionShowsWrittenAnswerWithoutModel() async {
        let index = CorpusIndex(chunks: Chunker.chunk(text: doc, file: "/p/q.md", folder: "/p", markdown: true))
        let hits = await Retriever(index: index).retrieve("How would you describe your management style?")
        XCTAssertEqual(hits.first?.via, .prepared)
        let model = FakeModel(name: "should not be called", reply: "invented")
        let card = await Answerer(fast: model, quality: model).answer("How would you describe your management style?", hits: hits)
        XCTAssertEqual(card.label, .grounded)
        XCTAssertEqual(card.answer, "Outcomes over tasks.")
        XCTAssertEqual(card.answeredBy, Answerer.preparedAnswer)
        XCTAssertEqual(card.matchedQuestion, "What's your management style?")
    }

    func testAllPossibleAnswersAreListed() async {
        let md = """
        # Stories
        ## Support
        I cut support response time from 41 hours to 3 hours with AI triage.
        ## Launch
        Our dispatch launch broke for two accounts; I now ship to 10 percent first.
        ## Pricing
        I talked the CEO out of a custom pricing engine.
        """
        let index = CorpusIndex(chunks: Chunker.chunk(text: md, file: "/p/s.md", folder: "/p", markdown: true))
        let q = "Tell me about a time you used AI to cut response time on a launch"
        let hits = await Retriever(index: index).retrieve(q)
        let card = await Answerer().answer(q, hits: hits)
        XCTAssertGreaterThanOrEqual(card.candidates.count, 2, "support and launch both relate")
        XCTAssertEqual(Set(card.candidates.map(\.chunk.id)).count, card.candidates.count, "no duplicates")
    }

    func testUnmatchedQuestionFallsBackToModel() async {
        let index = CorpusIndex(chunks: Chunker.chunk(text: doc, file: "/p/q.md", folder: "/p", markdown: true))
        let hits = await Retriever(index: index).retrieve("What is your salary expectation?")
        XCTAssertNotEqual(hits.first?.via, .prepared)
    }
}

final class ExtractTests: XCTestCase {
    func testBulletsAreSeparateSentences() {
        let passage = "- Revenue grew from $12M to $31M ARR over two years.\n- Team: 6 product managers, 4 designers."
        XCTAssertEqual(Answerer.extract("How much did revenue grow?", from: passage),
                       "Revenue grew from $12M to $31M ARR over two years.")
    }
}

final class GroundingTests: XCTestCase {
    func testNumbersAndNames() {
        let p = ["At Lumen Freight revenue reached $31M with 61 percent margin."]
        XCTAssertTrue(Grounding.check("At Lumen we reached 31 million in revenue and 61% margin.", against: p).passed)
        let bad = Grounding.check("We reached $40M, beating Tailspin.", against: p)
        XCTAssertEqual(bad.unsupportedNumbers, ["40m"])
        XCTAssertEqual(bad.unsupportedNames, ["Tailspin"])
    }
}

final class SessionTests: XCTestCase {
    func testQuestionDetection() {
        XCTAssertTrue(QuestionDetector.isQuestion("So walk me through your ninety day plan"))
        XCTAssertTrue(QuestionDetector.isQuestion("Great. Tell me about a time you failed"))
        XCTAssertTrue(QuestionDetector.isQuestion("is that something you've done before?"))
        XCTAssertFalse(QuestionDetector.isQuestion("That makes sense, thanks for sharing."))
        XCTAssertFalse(QuestionDetector.isQuestion("Okay."))
    }

    func testConsentGate() {
        var gate = ConsentGate(kind: .remote, mode: .announced)
        XCTAssertTrue(gate.needsAttestation)
        XCTAssertFalse(gate.mayCaptureSystemAudio, "no capture before attestation")
        gate.attest(saidIt: true, objection: false)
        XCTAssertTrue(gate.mayCaptureSystemAudio)
        XCTAssertTrue(gate.detectsQuestions(on: .them))

        var objected = ConsentGate(kind: .remote, mode: .announced)
        objected.attest(saidIt: true, objection: true)
        XCTAssertEqual(objected.mode, .myVoiceOnly)
        XCTAssertFalse(objected.mayCaptureSystemAudio)
        XCTAssertTrue(objected.mayDictate)

        let inPersonQuiet = ConsentGate(kind: .inPerson, mode: .myVoiceOnly)
        XCTAssertFalse(inPersonQuiet.mayListenContinuously, "in person, the mic hears them too")

        let rehearsal = ConsentGate(kind: .rehearsal, mode: .announced)
        XCTAssertFalse(rehearsal.needsAttestation)
        XCTAssertTrue(rehearsal.detectsQuestions(on: .you))

        let off = ConsentGate(kind: .remote, mode: .off)
        XCTAssertFalse(off.mayDictate)
    }

    func testTranscriptIsABuffer() {
        let log = SessionLog()
        log.add(Utterance(channel: .them, text: "What did you ship?"))
        XCTAssertEqual(log.lastExchange, "What did you ship?")
        log.discardTranscript()
        XCTAssertTrue(log.transcript.isEmpty)
    }
}

final class GateTests: XCTestCase {
    func testSamplePackPassesKeywordOnly() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("examples")
        let pack = root.appendingPathComponent("prep-pack")
        var chunks: [Chunk] = []
        for name in try FileManager.default.contentsOfDirectory(atPath: pack.path).sorted() where name.hasSuffix(".md") {
            let url = pack.appendingPathComponent(name)
            chunks += Chunker.chunk(text: try String(contentsOf: url, encoding: .utf8), file: url.path, folder: pack.path, markdown: true)
        }
        let questions = try JSONDecoder().decode([GateQuestion].self,
                                                 from: Data(contentsOf: root.appendingPathComponent("gate-questions.json")))
        let result = await Gate.run(questions, retriever: Retriever(index: CorpusIndex(chunks: chunks), primaryFolder: pack.path),
                                    answerer: Answerer())
        print(result.markdown)
        XCTAssertEqual(result.unsupportedNumbers, 0)
        XCTAssertEqual(result.citationCorrectness, 1)
        XCTAssertTrue(result.passed, result.failures.joined(separator: "; "))
    }
}

final class DocxTests: XCTestCase {
    let styles = """
    <w:styles xmlns:w="w"><w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/></w:style>
    <w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/></w:style></w:styles>
    """
    let numbering = """
    <w:numbering xmlns:w="w"><w:abstractNum w:abstractNumId="0"><w:lvl w:ilvl="0"><w:numFmt w:val="decimal"/></w:lvl></w:abstractNum>
    <w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num></w:numbering>
    """
    let document = """
    <w:document xmlns:w="w"><w:body>
    <w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr><w:r><w:t>What is Synopsys</w:t></w:r></w:p>
    <w:p><w:pPr><w:pStyle w:val="Heading2"/></w:pPr><w:r><w:t>How would you price the agents</w:t></w:r></w:p>
    <w:p><w:r><w:rPr><w:b/></w:rPr><w:t>How not to price</w:t></w:r></w:p>
    <w:p><w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="1"/></w:numPr></w:pPr><w:r><w:rPr><w:b/></w:rPr><w:t xml:space="preserve">Token based pricing: </w:t></w:r><w:r><w:t>tokens are the wrong unit.</w:t></w:r></w:p>
    <w:p><w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="1"/></w:numPr></w:pPr><w:r><w:rPr><w:b/></w:rPr><w:t>Outcome based pricing:</w:t></w:r><w:r><w:t xml:space="preserve"> needs reconciliation.</w:t></w:r></w:p>
    <w:p><w:r><w:t>Price on engine hours instead.</w:t></w:r></w:p>
    <w:p><w:pPr><w:pStyle w:val="Heading2"/></w:pPr><w:r><w:t>Why Synopsys</w:t></w:r></w:p>
    <w:p><w:r><w:t>Because EDA is where agents pay off.</w:t></w:r></w:p>
    </w:body></w:document>
    """

    func testHeadingsListsAndBoldSurvive() {
        let md = DocxMarkdown.convert(document: Data(document.utf8), styles: Data(styles.utf8), numbering: Data(numbering.utf8))
        XCTAssertTrue(md.contains("# What is Synopsys\n"))
        XCTAssertTrue(md.contains("## How would you price the agents\n"))
        XCTAssertTrue(md.contains("### How not to price\n"), "a short all-bold paragraph is a heading")
        XCTAssertTrue(md.contains("1. **Token based pricing:** tokens are the wrong unit.\n2. **Outcome based pricing:** needs reconciliation."))
    }

    func testWholeSectionComesBackInPlace() async {
        let md = DocxMarkdown.convert(document: Data(document.utf8), styles: Data(styles.utf8), numbering: Data(numbering.utf8))
        let index = CorpusIndex(chunks: Chunker.chunk(text: md, file: "/p/Synopsys.docx", folder: "/p", markdown: true))
        let hits = await Retriever(index: index).retrieve("How would you price the agents")
        let sections = index.sections(for: hits, question: "How would you price the agents")
        let top = sections.first?.section
        XCTAssertEqual(top?.title, "How would you price the agents")
        XCTAssertEqual(top?.parents, ["What is Synopsys"])
        XCTAssertTrue(top?.text.contains("### How not to price") ?? false)
        XCTAssertTrue(top?.text.contains("2. **Outcome based pricing:**") ?? false)
        XCTAssertTrue(top?.text.contains("Price on engine hours instead.") ?? false)
        XCTAssertFalse(top?.text.contains("EDA is where") ?? true, "the next section isn't included")
        XCTAssertEqual(Set(sections.map(\.id)).count, sections.count)
    }

    func testSimilarQuestions() {
        let md = DocxMarkdown.convert(document: Data(document.utf8), styles: Data(styles.utf8), numbering: Data(numbering.utf8))
        let index = CorpusIndex(chunks: Chunker.chunk(text: md, file: "/p/S.docx", folder: "/p", markdown: true))
        let similar = index.similarSections(to: "what pricing would you use for agents")
        XCTAssertTrue(similar.contains { $0.section.title == "How would you price the agents" })
    }
}

final class EchoTests: XCTestCase {
    func testSpeakerEcho() {
        XCTAssertTrue(Echo.isEcho("Where the merchant is not actually creating the dispatch, uh, if they want to approve, they can, uh, from an API perspective.",
                                  "Where the merchant is not actually creating the dispatch. Uh, they wanted approve, they can, uh, from an API perspective."))
        XCTAssertFalse(Echo.isEcho("How would you price the agents?", "I'd price on engine hours, not tokens."))
    }
}

final class DocumentViewTests: XCTestCase {
    let md = """
    # Synopsys
    ## How would you price the agents
    I'd price on engine hours.
    ## Copilot adoption
    Start with one painful workflow and measure weekly active designers.
    ## Why Synopsys
    EDA is where agents pay off.
    """

    func testHeadingThatSaysTheQuestionWins() {
        let index = CorpusIndex(chunks: Chunker.chunk(text: md, file: "/p/S.docx", folder: "/p", markdown: true))
        let m = index.titleMatches("How would you increase the adoption of a copilot?")
        XCTAssertEqual(m.first?.section.title, "Copilot adoption")
    }

    func testWholeDocumentInOrderWithSectionMembership() {
        let index = CorpusIndex(chunks: Chunker.chunk(text: md, file: "/p/S.docx", folder: "/p", markdown: true))
        let parts = index.documentParts(file: "/p/S.docx")
        XCTAssertEqual(parts.map(\.text).filter { $0.hasPrefix("#") }, ["# Synopsys", "## How would you price the agents", "## Copilot adoption", "## Why Synopsys"])
        let section = index.titleMatches("copilot adoption").first!.section
        let inside = parts.compactMap(\.chunk).filter(section.contains).map(\.text)
        XCTAssertEqual(inside, ["Start with one painful workflow and measure weekly active designers."])
    }

    func testLongListKeepsItsItemsOnSeparateLines() {
        let items = (1...8).map { "\($0). **Item \($0):** " + String(repeating: "This item explains one pricing model in detail. ", count: 3) }
        let chunks = Chunker.chunk(text: "## Pricing\n" + items.joined(separator: "\n"), file: "/p/a.md", folder: "/p", markdown: true)
        XCTAssertGreaterThan(chunks.count, 1)
        for c in chunks { for line in c.text.components(separatedBy: "\n") { XCTAssertTrue(line.first?.isNumber ?? false, line) } }
    }
}
