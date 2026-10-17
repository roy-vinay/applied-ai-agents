import Foundation

/// Refreshes sources, keeps the stored snapshot, and writes checked summaries one at a time.
public actor Engine {
    public private(set) var snapshot: Snapshot
    private let client: HTTPClient
    private let summarizer: Summarizer
    private let file: SnapshotFile?
    private var inFlight: Set<String> = []

    public init(file: SnapshotFile?, client: HTTPClient = HTTPClient(), summarizer: Summarizer, initial: Snapshot? = nil) {
        self.file = file
        self.client = client
        self.summarizer = summarizer
        self.snapshot = initial ?? file?.load() ?? Snapshot()
    }

    public var summarizerName: String { summarizer.name }
    public func summarizerProblem() async -> String? { await summarizer.availability() }

    /// Fetches every enabled source, four at a time. One failing source never blocks the others.
    @discardableResult
    public func refresh(sources: [Source], now: Date = Date()) async -> Snapshot {
        let enabled = sources.filter(\.isEnabled)
        var incoming: [Story] = []
        for chunk in stride(from: 0, to: enabled.count, by: 4).map({ Array(enabled[$0..<min($0 + 4, enabled.count)]) }) {
            let results = await withTaskGroup(of: (Source, Result<[FeedItem], Error>).self) { group in
                for source in chunk {
                    group.addTask { [client] in
                        do {
                            switch source.kind {
                            case .hackerNews: return (source, .success(try await HackerNews.topStories(client: client)))
                            case .feed:
                                guard let url = source.url else { return (source, .failure(Tech60Error.notAFeed)) }
                                return (source, .success(try FeedParser.parse(try await client.get(url), now: now)))
                            }
                        } catch {
                            return (source, .failure(error))
                        }
                    }
                }
                var all: [(Source, Result<[FeedItem], Error>)] = []
                for await r in group { all.append(r) }
                return all
            }
            for (source, result) in results {
                var status = snapshot.status[source.id] ?? SourceStatus()
                status.lastAttempt = now
                switch result {
                case .success(let items):
                    status.lastSuccess = now
                    status.lastError = nil
                    incoming += StoryMerge.stories(from: Array(items.prefix(40)), source: source, now: now)
                case .failure(let error):
                    status.lastError = error.localizedDescription
                }
                snapshot.status[source.id] = status
            }
        }
        // First launch: everything already in the feeds counts as seen.
        if snapshot.lastViewed == nil { snapshot.lastViewed = now }
        snapshot.stories = StoryMerge.merge(existing: snapshot.stories, incoming: incoming, now: now)
        // Only recent official stories are summarized; older ones stay headline and link.
        for i in snapshot.stories.indices where snapshot.stories[i].summary == .pending
            && now.timeIntervalSince(snapshot.stories[i].displayDate) > 3 * 86_400 {
            snapshot.stories[i].summary = .withheld(reason: "Older than three days, so it wasn't summarized.")
        }
        persist()
        return snapshot
    }

    public func markViewed(at date: Date = Date()) -> Snapshot {
        snapshot.lastViewed = date
        persist()
        return snapshot
    }

    /// Summarizes the next pending official story. Returns nil when there's nothing to do or no model.
    public func summarizeNext() async -> Snapshot? {
        guard await summarizer.availability() == nil,
              let story = snapshot.stories.first(where: { $0.summary == .pending && !inFlight.contains($0.id) }) else { return nil }
        await summarize(story)
        return snapshot
    }

    /// Summarizes one story because the reader asked for it, from any source and of any age.
    /// Returns the snapshot right away with the story marked pending; call `finishSummary` to run the model.
    public func requestSummary(id: String) async -> Snapshot {
        guard let i = snapshot.stories.firstIndex(where: { $0.id == id }) else { return snapshot }
        switch snapshot.stories[i].summary {
        case .checked: return snapshot
        case .pending where inFlight.contains(id): return snapshot
        default: break
        }
        if let problem = await summarizer.availability() {
            snapshot.stories[i].summary = .withheld(reason: problem)
        } else {
            snapshot.stories[i].summary = .pending
        }
        return snapshot
    }

    /// Runs the model for a story the reader asked about. Returns the updated snapshot.
    public func finishSummary(id: String) async -> Snapshot {
        if let story = snapshot.stories.first(where: { $0.id == id }), story.summary == .pending, !inFlight.contains(id) {
            await summarize(story)
        }
        return snapshot
    }

    private func summarize(_ original: Story) async {
        inFlight.insert(original.id)
        defer { inFlight.remove(original.id) }
        var story = original
        if story.sourceText.count < 300,
           let data = try? await client.get(story.url, maxBytes: 3_000_000),
           let page = HTMLText.articleText(fromHTML: data, minimum: 1), page.count > story.sourceText.count {
            story.sourceText = page
        }
        if story.sourceText.count < 150 {
            story.summary = .withheld(reason: "Tech60 couldn't find readable text on this page. It may load its content with scripts. Open the article to read it.")
        } else {
            do {
                let text = try await summarizer.summarize(title: story.title, text: story.sourceText)
                let result = SummaryChecker.check(summary: text, source: story.title + "\n" + story.sourceText)
                story.summary = result.passed
                    ? .checked(text: text, evidence: result.evidence)
                    : .withheld(reason: "The summary didn't pass the source check (\(result.reason ?? "unknown")), so it isn't shown.")
            } catch {
                story.summary = .withheld(reason: "The on-device model couldn't summarize it (\(error.localizedDescription)).")
            }
        }
        if let i = snapshot.stories.firstIndex(where: { $0.id == story.id }) {
            snapshot.stories[i].sourceText = story.sourceText
            snapshot.stories[i].summary = story.summary
        }
        persist()
    }

    private func persist() {
        try? file?.save(snapshot)
    }
}
