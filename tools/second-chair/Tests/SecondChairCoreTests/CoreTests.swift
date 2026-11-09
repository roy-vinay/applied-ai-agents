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
        XCTAssertEqual(card.label, .notInDocs)
    }

    func testFollowUpCarriesContext() async {
        let r = Retriever(index: index)
        XCTAssertTrue(Retriever.isFollowUp("And why was that?"))
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
