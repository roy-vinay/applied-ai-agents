import AppKit
import Combine
import Tech60Core
import UserNotifications

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var snapshot = Snapshot() { didSet { rebuild() } }
    /// Stories grouped so one launch covered by several sources is one row.
    @Published private(set) var clusters: [StoryCluster] = []
    /// When set, the card shows only these rows (the brief the reader opened from a notification).
    @Published private(set) var briefIDs: [String]?
    @Published var followedTopicIDs: Set<String> {
        didSet { if !isDemo { UserDefaults.standard.set(Array(followedTopicIDs), forKey: "followedTopics") }; rebuild() }
    }
    @Published var customTopics: [Topic] {
        didSet {
            if !isDemo, let data = try? JSONEncoder().encode(customTopics) { UserDefaults.standard.set(data, forKey: "customTopics") }
            rebuild()
        }
    }
    /// Hot ranks by heat (coverage, Hacker News, Techmeme) and hides quiet stories; Latest is newest first.
    @Published var sortMode: SortMode {
        didSet { UserDefaults.standard.set(sortMode.rawValue, forKey: "sortMode") }
    }
    enum SortMode: String, CaseIterable { case hot = "Hot", latest = "Latest" }

    /// A topic tab on the card (a topic id), or nil for Top and Latest.
    @Published var topicTab: String?
    /// Set by the app delegate so the card's settings button can open the settings window.
    var openSettings: () -> Void = {}
    private var maxScore: Double = 1

    /// Hour of the daily brief (0-23), or nil when it's off.
    @Published var briefHour: Int? {
        didSet {
            UserDefaults.standard.set(briefHour ?? -1, forKey: "briefHour")
            // Starting now means the first brief comes at the next chosen hour, not right away.
            if briefHour != nil { lastBriefSent = Date(); requestNotificationPermission() }
        }
    }
    @Published private(set) var isRefreshing = false
    @Published private(set) var summaryProblem: String?
    @Published var isPaused = false
    @Published var sources: [Source] { didSet { saveSources(); rebuild() } }
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
        sortMode = SortMode(rawValue: defaults.string(forKey: "sortMode") ?? "") ?? .hot
        if isDemo {
            followedTopicIDs = ["models", "security"]
            customTopics = []
            briefHour = nil
        } else {
            followedTopicIDs = Set(defaults.stringArray(forKey: "followedTopics") ?? [])
            customTopics = defaults.data(forKey: "customTopics").flatMap { try? JSONDecoder().decode([Topic].self, from: $0) } ?? []
            let hour = defaults.object(forKey: "briefHour") as? Int ?? -1
            briefHour = (0...23).contains(hour) ? hour : nil
        }
        if isDemo {
            engine = Engine(file: nil, summarizer: NoSummarizer(reason: "Sample mode"), initial: Demo.snapshot())
        } else {
            engine = Engine(file: SnapshotFile.standard(), summarizer: Summarizers.onDevice())
        }
        if isDemo {
            // Build the sample card synchronously so screenshots never catch it empty.
            snapshot = Demo.snapshot()
            rebuild()
            if ProcessInfo.processInfo.arguments.contains("--brief") { showBrief() }
        }
        Task { await self.start() }
    }

    var allTopics: [Topic] { Topics.builtIn + customTopics }
    var followedTopics: [Topic] { allTopics.filter { followedTopicIDs.contains($0.id) } }

    /// Recent stories from enabled sources, newest first.
    private var recentStories: [Story] {
        let enabled = Set(sources.filter(\.isEnabled).map(\.id))
        let recent = snapshot.stories.filter { isDemo || enabled.contains($0.sourceID) }
        let window = recent.filter { Date().timeIntervalSince($0.displayDate) < 2 * 86_400 }
        return Array((window.isEmpty ? recent : window).prefix(80))
    }

    private func rebuild() {
        clusters = Clustering.cluster(recentStories)
        maxScore = clusters.map { Hotness.score($0, topics: followedTopics) }.max() ?? 1
    }

    /// How hot a row is next to the hottest one on the card, 0.12 to 1, for the heat ring.
    func heatFraction(_ cluster: StoryCluster) -> Double {
        min(1, max(0.12, Hotness.score(cluster, topics: followedTopics) / max(maxScore, 0.0001)))
    }

    /// The section label above a headline: the first topic it matches, followed topics first.
    func kicker(for cluster: StoryCluster) -> String? {
        let order = followedTopics + allTopics.filter { !followedTopicIDs.contains($0.id) }
        for topic in order where cluster.stories.contains(where: { !Topics.matches($0, in: [topic]).isEmpty }) {
            return Topics.shortName(topic)
        }
        return nil
    }

    /// Tabs: followed topics, else a few useful defaults.
    var tabTopics: [Topic] {
        let followed = followedTopics
        if !followed.isEmpty { return followed }
        return Topics.builtIn.filter { ["models", "agents", "security", "funding"].contains($0.id) }
    }

    /// Fetches link-preview pictures for the rows on screen.
    func loadImages() {
        guard !isDemo else { return }
        let ids = visibleClusters.prefix(12).flatMap { c in c.imageURL == nil ? c.stories.map(\.id) : [] }
        guard !ids.isEmpty else { return }
        Task { snapshot = await engine.fetchImages(ids: ids) }
    }

    /// What the card shows: the open brief, else stories on followed topics first, then everything else.
    var visibleClusters: [StoryCluster] {
        if let ids = briefIDs {
            return ids.compactMap { id in clusters.first { $0.id == id || $0.stories.contains { $0.id == id } } }
        }
        let topics = followedTopics
        if let tab = topicTab, let topic = allTopics.first(where: { $0.id == tab }) {
            return clusters.filter { c in c.stories.contains { !Topics.matches($0, in: [topic]).isEmpty } }
                .sorted { Hotness.score($0, topics: topics) > Hotness.score($1, topics: topics) }
        }
        if sortMode == .hot { return Hotness.hot(clusters, topics: topics) }
        guard !topics.isEmpty else { return clusters }
        let (on, off) = clusters.reduce(into: ([StoryCluster](), [StoryCluster]())) { acc, c in
            if topicNames(for: c).isEmpty { acc.1.append(c) } else { acc.0.append(c) }
        }
        return on + off
    }

    /// Followed topics this row matches.
    func topicNames(for cluster: StoryCluster) -> [String] {
        let topics = followedTopics
        guard !topics.isEmpty else { return [] }
        let hits = Set(cluster.stories.flatMap { Topics.matches($0, in: topics) }.map(\.id))
        return topics.filter { hits.contains($0.id) }.map(\.name)
    }

    /// Rows outside followed topics are dimmed, so the ones you care about stand out.
    func isFaded(_ cluster: StoryCluster) -> Bool {
        briefIDs == nil && !followedTopicIDs.isEmpty && topicNames(for: cluster).isEmpty
    }

    var newCount: Int { clusters.filter(isNew).count }
    func isNew(_ cluster: StoryCluster) -> Bool { cluster.stories.contains(where: snapshot.isNew) }

    var lastUpdated: Date? { snapshot.status.values.compactMap(\.lastSuccess).max() }

    // MARK: Daily brief

    private var lastBriefSent: Date? {
        get { UserDefaults.standard.object(forKey: "lastBriefSent") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "lastBriefSent") }
    }
    private var lastBrief: [String] {
        get { UserDefaults.standard.stringArray(forKey: "lastBrief") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "lastBrief") }
    }
    private var briefTimer: Timer?
    private var isSendingBrief = false

    private func startBriefClock() {
        briefTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.briefIfDue() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            // Give the network a moment after waking.
            Task { @MainActor in try? await Task.sleep(for: .seconds(20)); await self?.briefIfDue() }
        }
    }

    /// Sends today's brief once, at the chosen hour or the first time the Mac is awake after it.
    func briefIfDue(now: Date = Date()) async {
        guard let hour = briefHour,
              let due = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: now),
              now >= due, (lastBriefSent ?? .distantPast) < due else { return }
        await sendBrief(now: now)
    }

    /// Refreshes, picks the top stories since the last brief, and posts one notification.
    func sendBrief(now: Date = Date()) async {
        guard !isDemo, !isSendingBrief else { return }
        isSendingBrief = true
        defer { isSendingBrief = false }
        let since = lastBriefSent ?? now.addingTimeInterval(-24 * 3600)
        await refresh()
        let picks = Brief.pick(clusters, topics: followedTopics, since: since, now: now)
        lastBriefSent = now
        lastBrief = picks.map(\.id)

        let content = UNMutableNotificationContent()
        if picks.isEmpty {
            content.title = "Tech60"
            content.body = "Nothing new since your last brief."
        } else {
            content.title = "Your Tech60 brief"
            content.subtitle = picks.count == 1 ? "1 story worth your time" : "\(picks.count) stories worth your time"
            content.body = Brief.body(picks)
        }
        content.threadIdentifier = "brief"
        let request = UNNotificationRequest(identifier: "brief-\(Int(now.timeIntervalSince1970))", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    /// Opens the last brief on the card.
    func showBrief() {
        if isDemo {
            briefIDs = Brief.pick(clusters, topics: followedTopics, since: Date().addingTimeInterval(-24 * 3600)).map(\.id)
        } else {
            briefIDs = lastBrief.isEmpty ? nil : lastBrief
        }
    }

    var hasBrief: Bool { isDemo || !lastBrief.isEmpty }

    func closeBrief() { briefIDs = nil }

    private func requestNotificationPermission() {
        guard !isDemo else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // MARK: Topics

    func addTopic(name: String, keywords: String) -> Bool {
        guard let topic = Topics.custom(name: name, keywords: keywords) else { return false }
        customTopics.append(topic)
        followedTopicIDs.insert(topic.id)
        return true
    }

    func removeTopic(_ topic: Topic) {
        customTopics.removeAll { $0.id == topic.id }
        followedTopicIDs.remove(topic.id)
    }

    private func start() async {
        snapshot = await engine.snapshot
        summaryProblem = await engine.summarizerProblem()
        guard !isDemo else { return }
        startBriefClock()
        await refresh()
        await briefIfDue()
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
        loadImages()
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
