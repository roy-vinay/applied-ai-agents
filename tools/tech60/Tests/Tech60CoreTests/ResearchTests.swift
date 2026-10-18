import XCTest
@testable import Tech60Core

final class ResearchTests: XCTestCase {
    let now = ISO8601DateFormatter().date(from: "2026-10-17T12:00:00Z")!
    let arxiv = Source(id: "arxiv", name: "arXiv", kind: .research, url: nil, isPrimary: false)
    let hn = Source(id: "hn", name: "Hacker News", kind: .hackerNews, url: nil, isPrimary: false)

    private func item(_ id: String, type: String = "new", link: String = "https://arxiv.org/abs/2410.01234") -> FeedItem {
        FeedItem(id: "oai:arXiv.org:\(id)", title: "Scaling laws for tool-using agents", link: URL(string: link), published: now,
                 text: "arXiv:\(id)v1 Announce Type: \(type) \nAbstract: We study how agents scale with tools.")
    }

    func testParsesArxivRSS() throws {
        let xml = """
        <?xml version="1.0"?>
        <rss version="2.0" xmlns:dc="http://purl.org/dc/elements/1.1/"><channel><title>cs.AI updates on arXiv.org</title>
        <item><title>Scaling laws for tool-using agents</title><link>https://arxiv.org/abs/2410.01234</link>
          <description>arXiv:2410.01234v1 Announce Type: new
        Abstract: We study how agents scale with tools.</description>
          <guid isPermaLink="false">oai:arXiv.org:2410.01234v1</guid><dc:creator>A. Author</dc:creator>
          <pubDate>Fri, 17 Oct 2026 00:00:00 -0400</pubDate></item>
        <item><title>An older paper, revised</title><link>https://arxiv.org/abs/2301.00001</link>
          <description>arXiv:2301.00001v3 Announce Type: replace
        Abstract: Revised.</description><guid isPermaLink="false">oai:arXiv.org:2301.00001v3</guid></item>
        </channel></rss>
        """
        let stories = StoryMerge.stories(from: try FeedParser.parse(Data(xml.utf8), now: now), source: arxiv, now: now)
        XCTAssertEqual(stories.count, 1, "replaced versions of old papers are skipped")
        XCTAssertEqual(stories[0].sourceText, "We study how agents scale with tools.")
        XCTAssertEqual(stories[0].isResearch, true)
        XCTAssertFalse(stories[0].isPrimary, "papers are not summarized in the background")
    }

    func testParsesArxivSearchAPI() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom"><title>arXiv Query</title>
        <entry><id>http://arxiv.org/abs/2410.01234v1</id><updated>2026-10-16T17:59:59Z</updated>
          <published>2026-10-16T17:59:59Z</published><title>Scaling laws for
            tool-using agents</title>
          <summary>  We study how agents scale with tools.
        </summary><author><name>A. Author</name></author>
          <link href="http://arxiv.org/abs/2410.01234v1" rel="alternate" type="text/html"/>
          <link title="pdf" href="http://arxiv.org/pdf/2410.01234v1" rel="related" type="application/pdf"/></entry>
        </feed>
        """
        let stories = StoryMerge.stories(from: try FeedParser.parse(Data(xml.utf8), now: now), source: arxiv, now: now)
        XCTAssertEqual(stories.count, 1)
        XCTAssertEqual(stories[0].title, "Scaling laws for tool-using agents")
        XCTAssertEqual(stories[0].url.absoluteString, "https://arxiv.org/abs/2410.01234")
        XCTAssertEqual(stories[0].sourceText, "We study how agents scale with tools.")
    }

    func testDefaultArxivAddressIsTheSearchAPI() {
        let source = DefaultSources.all.first { $0.id == "arxiv" }
        XCTAssertEqual(source?.url?.host, "export.arxiv.org")
        XCTAssertEqual(DefaultSources.movedURLs["arxiv"]?.new, source?.url?.absoluteString)
    }

    func testCrossListsAreKept() {
        XCTAssertFalse(Research.isReplacement(item("2410.01234", type: "cross")))
        XCTAssertTrue(Research.isReplacement(item("2410.01234", type: "replace-cross")))
    }

    func testCanonicalArxivLinks() {
        let abs = "https://arxiv.org/abs/2410.01234"
        XCTAssertEqual(Research.canonicalArxiv(URL(string: "https://arxiv.org/pdf/2410.01234v2.pdf")!), abs)
        XCTAssertEqual(Research.canonicalArxiv(URL(string: "https://www.arxiv.org/abs/2410.01234v1")!), abs)
        XCTAssertEqual(Research.canonicalArxiv(URL(string: "https://arxiv.org/html/2410.01234v3")!), abs)
        XCTAssertNil(Research.canonicalArxiv(URL(string: "https://example.com/abs/2410.01234")!))
    }

    func testPaperStaysOutOfTheNewsUntilHackerNewsPicksItUp() {
        let papers = StoryMerge.merge(existing: [], incoming: StoryMerge.stories(from: [item("2410.01234")], source: arxiv, now: now), now: now)
        XCTAssertTrue(Research.isPaperOnly(papers[0]))

        let post = FeedItem(id: "hn-1", title: "Scaling laws for tool-using agents (arxiv.org)",
                            link: URL(string: "https://arxiv.org/pdf/2410.01234v1.pdf"), published: now, text: "", points: 420, comments: 90)
        let merged = StoryMerge.merge(existing: papers, incoming: StoryMerge.stories(from: [post], source: hn, now: now), now: now)
        XCTAssertEqual(merged.count, 1, "the post and the paper are one story")
        XCTAssertEqual(merged[0].points, 420)
        XCTAssertFalse(Research.isPaperOnly(merged[0]), "in the news now, so it can reach Top and Latest")
    }

    func testPostFirstThenPaperGivesThePostTheAbstract() {
        let post = FeedItem(id: "hn-1", title: "Scaling laws for tool-using agents", link: URL(string: "https://arxiv.org/abs/2410.01234"),
                            published: now, text: "", points: 300)
        let first = StoryMerge.merge(existing: [], incoming: StoryMerge.stories(from: [post], source: hn, now: now), now: now)
        let merged = StoryMerge.merge(existing: first, incoming: StoryMerge.stories(from: [item("2410.01234")], source: arxiv, now: now), now: now)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].sourceText, "We study how agents scale with tools.")
    }

    func testUnnoticedPapersExpireSooner() {
        let old = now.addingTimeInterval(-3 * 86_400)
        var paper = StoryMerge.stories(from: [item("2410.01234")], source: arxiv, now: old)[0]
        paper.published = old
        XCTAssertTrue(StoryMerge.merge(existing: [paper], incoming: [], now: now).isEmpty)
    }

    func testPapersCountFromWhenTech60SawThemNotWhenTheyWereSubmitted() {
        var paper = StoryMerge.stories(from: [item("2410.01234")], source: arxiv, now: now)[0]
        paper.published = now.addingTimeInterval(-4 * 86_400)
        XCTAssertEqual(StoryMerge.merge(existing: [paper], incoming: [], now: now.addingTimeInterval(3600)).count, 1)
    }

    func testResearchFeedIsFetchedAtMostEverySixHours() async {
        var snapshot = Snapshot()
        snapshot.status["arxiv"] = SourceStatus(lastAttempt: now, lastSuccess: now)
        snapshot.stories = StoryMerge.stories(from: [item("2410.01234")], source: arxiv, now: now)
        let engine = Engine(file: nil, summarizer: NoSummarizer(reason: "test"), initial: snapshot)
        let source = Source(id: "arxiv", name: "arXiv", kind: .research, url: URL(string: "https://rss.arxiv.org/rss/cs.AI"), isPrimary: false)
        let after = await engine.refresh(sources: [source], now: now.addingTimeInterval(3600))
        XCTAssertEqual(after.status["arxiv"]?.lastAttempt, now, "fetched an hour ago, so not asked again")
    }

    func testAfterA429ArxivIsLeftAloneForAnHour() async {
        var snapshot = Snapshot()
        snapshot.status["arxiv"] = SourceStatus(lastAttempt: now, lastSuccess: nil, lastError: "429")
        let engine = Engine(file: nil, summarizer: NoSummarizer(reason: "test"), initial: snapshot)
        let source = Source(id: "arxiv", name: "arXiv", kind: .research, url: URL(string: "https://export.arxiv.org/api/query"), isPrimary: false)
        let after = await engine.refresh(sources: [source], now: now.addingTimeInterval(600))
        XCTAssertEqual(after.status["arxiv"]?.lastAttempt, now, "ten minutes after a 429: not asked again")
    }
}

final class PaperExplainerTests: XCTestCase {
    let source = """
    Scaling laws for tool-using agents
    Abstract: We study how language model agents improve when given more tools. Across 12 benchmarks, agents with \
    retrieval tools solved 41% more tasks than agents without them. Introduction: Agents often fail on long tasks.
    """
    let raw = """
    **Problem:** AI agents often fail on long tasks, and it's unclear whether giving them more tools helps.
    Approach: The authors tested language model agents with and without retrieval tools across 12 benchmarks.
    Findings: Agents with retrieval tools solved 41% more tasks than agents without them.
    Why it matters: Teams building agents can expect retrieval tools to help on long, multi-step work.
    """

    func testParsesFourParts() {
        let e = PaperExplainer.parse(raw)
        XCTAssertEqual(e?.problem, "AI agents often fail on long tasks, and it's unclear whether giving them more tools helps.")
        XCTAssertEqual(e?.impact, "Teams building agents can expect retrieval tools to help on long, multi-step work.")
        XCTAssertEqual(PaperExplainer.parse(e!.stored), e, "stored form reads back the same")
    }

    func testMissingPartIsRejected() {
        XCTAssertNil(PaperExplainer.parse("Problem: x\nApproach: y\nFindings: z"))
    }

    func testPassesWhenGrounded() {
        let result = PaperExplainer.check(PaperExplainer.parse(raw)!, source: source)
        XCTAssertTrue(result.passed, result.reason ?? "")
        XCTAssertFalse(result.evidence.isEmpty)
    }

    func testInventedNumberFailsEvenInWhyItMatters() {
        var e = PaperExplainer.parse(raw)!
        e.impact = "It could cut support costs by 30%."
        XCTAssertFalse(PaperExplainer.check(e, source: source).passed)
    }

    func testUnsupportedFindingFails() {
        var e = PaperExplainer.parse(raw)!
        e.findings = "Bigger models were much cheaper to run in production deployments."
        XCTAssertFalse(PaperExplainer.check(e, source: source).passed)
    }

    func testHTMLAddressAndExplainerText() {
        XCTAssertEqual(Research.htmlURL(for: URL(string: "https://arxiv.org/abs/2410.01234v2")!)?.absoluteString,
                       "https://arxiv.org/html/2410.01234")
        let text = Research.explainerText(abstract: "A.", introduction: "I.", conclusion: nil)
        XCTAssertEqual(text, "Abstract: A.\n\nIntroduction: I.")
    }

    func testFindsIntroductionAndConclusion() {
        let html = """
        <html><body><article>
        <section class="ltx_section" id="S1"><h2 class="ltx_title">1 Introduction</h2><p class="ltx_p">Agents fail on long tasks.</p></section>
        <section class="ltx_section" id="S2"><h2 class="ltx_title">2 Method</h2><p class="ltx_p">We add tools.</p></section>
        <section class="ltx_section" id="S5"><h2 class="ltx_title">5 Conclusion</h2><p class="ltx_p">Tools help agents.</p></section>
        </article></body></html>
        """
        let (intro, end) = Research.introductionAndConclusion(fromHTML: Data(html.utf8))
        XCTAssertEqual(intro, "Agents fail on long tasks.")
        XCTAssertEqual(end, "Tools help agents.")
    }
}

final class ExplainerUpgradeTests: XCTestCase {
    func testOldPaperSummariesAreClearedButExplainersAndNewsStay() {
        let now = Date()
        func story(_ id: String, research: Bool, _ summary: SummaryState) -> Story {
            var s = Story(id: id, sourceID: research ? "arxiv" : "openai", sourceName: "x", title: id,
                          url: URL(string: "https://example.com/\(id)")!, published: now, firstSeen: now, sourceText: "",
                          isPrimary: !research, summary: summary)
            s.isResearch = research ? true : nil
            return s
        }
        let explainer = PaperExplainer(problem: "P.", approach: "A.", findings: "F.", impact: "W.").stored
        let snap = Snapshot(stories: [
            story("old", research: true, .checked(text: "A short 45-word summary.", evidence: [])),
            story("failed", research: true, .withheld(reason: "x")),
            story("new", research: true, .checked(text: explainer, evidence: [])),
            story("news", research: false, .checked(text: "News summary.", evidence: [])),
        ])
        let up = PaperExplainer.upgrade(snap).stories
        XCTAssertEqual(up[0].summary, .none)
        XCTAssertEqual(up[1].summary, .none)
        XCTAssertEqual(up[2].summary, .checked(text: explainer, evidence: []))
        XCTAssertEqual(up[3].summary, .checked(text: "News summary.", evidence: []))
    }
}

final class PaperSignalsTests: XCTestCase {
    func testVenue() {
        XCTAssertEqual(PaperSignals.venue(fromComment: "Accepted at NeurIPS 2026. Code at github.com/x/y"), "NeurIPS 2026")
        XCTAssertEqual(PaperSignals.venue(fromComment: "ICLR'26 camera ready"), "ICLR 2026")
        XCTAssertEqual(PaperSignals.venue(fromComment: "Published in TMLR"), "TMLR")
        XCTAssertNil(PaperSignals.venue(fromComment: "Submitted to ICML 2027"))
        XCTAssertNil(PaperSignals.venue(fromComment: "12 pages, 4 figures"))
    }

    func testKeywordGroups() {
        XCTAssertEqual(PaperSignals.keywordGroup(title: "Multi-agent orchestration for tool use", abstract: ""), .agents)
        XCTAssertEqual(PaperSignals.keywordGroup(title: "Jailbreak attacks on chat models", abstract: "We study safety."), .safety)
        XCTAssertEqual(PaperSignals.keywordGroup(title: "A new benchmark for code", abstract: "We evaluate models."), .evaluation)
    }

    func testRatingParse() {
        let r = PaperRatingPrompt.parse("1: agents, 4, 3\n2. Safety, 2, 5\n3: unknown, 3, 3\n**4: efficiency, 5, 1**", count: 4)
        XCTAssertEqual(r[0], PaperRatingPrompt.Rating(group: .agents, applicability: 4, generalizability: 3))
        XCTAssertEqual(r[1]?.group, .safety)
        XCTAssertNil(r[2], "unknown groups are skipped")
        XCTAssertEqual(r[3]?.applicability, 5)
    }

    func testLenientRatingParse() {
        let r = PaperRatingPrompt.parse("""
        Paper 1: Multi-agent systems; applicability 4, generalizability 3
        2) RAG | 5 | 2
        3: Agent, 3
        """, count: 3)
        XCTAssertEqual(r[0], PaperRatingPrompt.Rating(group: .agents, applicability: 4, generalizability: 3))
        XCTAssertEqual(r[1], PaperRatingPrompt.Rating(group: .retrieval, applicability: 5, generalizability: 2))
        XCTAssertNil(r[2], "needs both scores")
    }

    func testPracticalAloneIsNotable() {
        var s = Story(id: "a", sourceID: "arxiv", sourceName: "arXiv", title: "T", url: URL(string: "https://arxiv.org/abs/1")!,
                      published: nil, firstSeen: Date(), sourceText: "", isPrimary: false)
        s.isResearch = true
        s.paperApplicability = 4; s.paperGeneralizability = 2
        XCTAssertTrue(PaperSignals.isNotable(s))
        s.paperApplicability = 3; s.paperGeneralizability = 4
        XCTAssertTrue(PaperSignals.isNotable(s))
        s.paperApplicability = 3; s.paperGeneralizability = 3
        XCTAssertFalse(PaperSignals.isNotable(s))
    }

    func testNotableAndTags() {
        var s = Story(id: "a", sourceID: "arxiv", sourceName: "arXiv", title: "T", url: URL(string: "https://arxiv.org/abs/1")!,
                      published: nil, firstSeen: Date(), sourceText: "", isPrimary: false)
        s.isResearch = true
        XCTAssertFalse(PaperSignals.isNotable(s))
        s.paperApplicability = 4; s.paperGeneralizability = 3
        XCTAssertTrue(PaperSignals.isNotable(s))
        s.paperApplicability = 2; s.paperVenue = "NeurIPS 2026"
        XCTAssertTrue(PaperSignals.isNotable(s))
        XCTAssertEqual(PaperSignals.tags(s), ["NeurIPS 2026"])
        s.paperHasCode = true; s.points = 300
        XCTAssertEqual(PaperSignals.tags(s), ["NeurIPS 2026", "On Hacker News", "Code"])
    }

    func testArxivCommentIsParsedIntoSignals() throws {
        let xml = """
        <feed xmlns="http://www.w3.org/2005/Atom" xmlns:arxiv="http://arxiv.org/schemas/atom">
        <entry><id>http://arxiv.org/abs/2410.01234v1</id><published>2026-10-16T17:59:59Z</published>
          <title>Multi-agent orchestration with tool use</title>
          <summary>We coordinate agents. Code: https://github.com/x/y</summary>
          <arxiv:comment>Accepted at ICLR 2027</arxiv:comment>
          <link href="http://arxiv.org/abs/2410.01234v1" rel="alternate" type="text/html"/></entry>
        </feed>
        """
        let arxiv = Source(id: "arxiv", name: "arXiv", kind: .research, url: nil, isPrimary: false)
        let s = StoryMerge.stories(from: try FeedParser.parse(Data(xml.utf8)), source: arxiv, now: Date())[0]
        XCTAssertEqual(s.paperVenue, "ICLR 2027")
        XCTAssertEqual(s.paperHasCode, true)
        XCTAssertEqual(s.paperGroup, "agents")
    }
}
