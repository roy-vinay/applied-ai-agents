import AppKit
import Combine
import Tech60Core

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var snapshot = Snapshot()
    @Published private(set) var isRefreshing = false
    @Published private(set) var summaryProblem: String?
    @Published var isPaused = false
    @Published var sources: [Source] { didSet { saveSources() } }
    @Published var summariesEnabled: Bool {
        didSet { UserDefaults.standard.set(summariesEnabled, forKey: "summariesEnabled"); if summariesEnabled { startSummaries() } }
    }

    let isDemo: Bool
    private let engine: Engine
    private var timer: Timer?
    private var summaryTask: Task<Void, Never>?

    init(isDemo: Bool) {
        self.isDemo = isDemo
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: "sources"), let saved = try? JSONDecoder().decode([Source].self, from: data) {
            sources = saved
        } else {
            sources = DefaultSources.all
        }
        summariesEnabled = defaults.object(forKey: "summariesEnabled") as? Bool ?? true
        if isDemo {
            engine = Engine(file: nil, summarizer: NoSummarizer(reason: "Sample mode"), initial: Demo.snapshot())
        } else {
            engine = Engine(file: SnapshotFile.standard(), summarizer: Summarizers.onDevice())
        }
        Task { await self.start() }
    }

    var visibleStories: [Story] {
        let enabled = Set(sources.filter(\.isEnabled).map(\.id))
        let recent = snapshot.stories.filter { isDemo || enabled.contains($0.sourceID) }
        let window = recent.filter { Date().timeIntervalSince($0.displayDate) < 2 * 86_400 }
        return Array((window.isEmpty ? recent : window).prefix(60))
    }

    var lastUpdated: Date? { snapshot.status.values.compactMap(\.lastSuccess).max() }

    var newCount: Int { visibleStories.filter(snapshot.isNew).count }
    func isNew(_ story: Story) -> Bool { snapshot.isNew(story) }

    private func start() async {
        snapshot = await engine.snapshot
        summaryProblem = await engine.summarizerProblem()
        guard !isDemo else { return }
        await refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    func refresh() async {
        guard !isDemo, !isRefreshing else { return }
        isRefreshing = true
        snapshot = await engine.refresh(sources: sources)
        isRefreshing = false
        startSummaries()
    }

    func markViewed() {
        guard !isDemo else { return }
        Task { snapshot = await engine.markViewed() }
    }

    func open(_ story: Story) {
        guard let scheme = story.url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return }
        NSWorkspace.shared.open(story.url)
    }

    /// The reader opened a story: summarize it now if it has no summary yet.
    func summarize(_ story: Story) {
        guard !isDemo else { return }
        Task {
            snapshot = await engine.requestSummary(id: story.id)
            snapshot = await engine.finishSummary(id: story.id)
        }
    }

    func refreshNow() { Task { await refresh() } }

    private func startSummaries() {
        guard summariesEnabled, !isDemo, summaryTask == nil else { return }
        summaryTask = Task {
            while !Task.isCancelled, summariesEnabled, let next = await engine.summarizeNext() {
                snapshot = next
            }
            summaryTask = nil
        }
    }

    func addFeed(name: String, url: URL, isOfficial: Bool) {
        let id = "custom-" + UUID().uuidString.prefix(8)
        sources.append(Source(id: String(id), name: name, kind: .feed, url: url, isPrimary: isOfficial))
        Task { await refresh() }
    }

    func status(for source: Source) -> SourceStatus? { snapshot.status[source.id] }

    private func saveSources() {
        if let data = try? JSONEncoder().encode(sources) { UserDefaults.standard.set(data, forKey: "sources") }
    }
}
