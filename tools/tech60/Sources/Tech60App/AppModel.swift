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
    enum SortMode: String, CaseIterable { case hot = "Hot", latest = "Latest", research = "Research" }

    /// What "More like this" and "Less like this" taught Tech60.
    @Published var taste: Taste {
        didSet {
            if !isDemo, let data = try? JSONEncoder().encode(taste) { UserDefaults.standard.set(data, forKey: "taste") }
            rebuild()
        }
    }
    /// Stories the reader dismissed with "Less like this".
    @Published private(set) var hiddenIDs: Set<String> {
        didSet {
            if !isDemo { UserDefaults.standard.set(Array(hiddenIDs.suffix(2_000)), forKey: "hiddenStories") }
            rebuild()
        }
    }
    /// A topic tab on the card (a topic id), or nil for Top and Latest.
    @Published var topicTab: String?
    /// Set by the app delegate so the card's settings button can open the settings window.
    var openSettings: () -> Void = {}
    /// The row under the pointer, so a hover-started summary only runs if the pointer stayed.
    var hoveredID: String?
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
        if let data = defaults.data(forKey: "sources"), var saved = try? JSONDecoder().decode([Source].self, from: data) {
            // Once per default-list version: add new default sources and turn off the noisy ones.
            let savedVersion = defaults.integer(forKey: "sourcesVersion")
            if savedVersion < DefaultSources.version {
                let have = Set(saved.map(\.id))
                saved += DefaultSources.all.filter { !have.contains($0.id) }
                // Only once, when they first went quiet; a reader who turned them back on keeps them on.
                if savedVersion < 2 {
                    for i in saved.indices where DefaultSources.offByDefault.contains(saved[i].id) { saved[i].isEnabled = false }
                }
                for i in saved.indices {
                    if let moved = DefaultSources.movedURLs[saved[i].id], saved[i].url?.absoluteString == moved.old {
                        saved[i].url = URL(string: moved.new)
                    }
                }
                defaults.set(DefaultSources.version, forKey: "sourcesVersion")
                if let data = try? JSONEncoder().encode(saved) { defaults.set(data, forKey: "sources") }
            }
            sources = saved
        } else {
            sources = DefaultSources.all
            defaults.set(DefaultSources.version, forKey: "sourcesVersion")
        }
        taste = defaults.data(forKey: "taste").flatMap { try? JSONDecoder().decode(Taste.self, from: $0) } ?? Taste()
        hiddenIDs = Set(defaults.stringArray(forKey: "hiddenStories") ?? [])
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
        let recent = snapshot.stories.filter {
            (isDemo || enabled.contains($0.sourceID)) && !hiddenIDs.contains($0.id) && !NoiseFilter.isNoise($0)
                && !Research.isPaperOnly($0)
        }
        let window = recent.filter { Date().timeIntervalSince($0.displayDate) < 2 * 86_400 }
        return Array((window.isEmpty ? recent : window).prefix(80))
    }

    /// True when a research feed is on, so the card shows a Research tab.
    var hasResearch: Bool { sources.contains { $0.kind == .research && $0.isEnabled } }

    /// What the empty Research tab says: still fetching, or why the last fetch failed.
    var researchStatus: String {
        guard let source = sources.first(where: { $0.kind == .research && $0.isEnabled }) else { return "Turn on arXiv in Sources." }
        let s = snapshot.status[source.id]
        if let error = s?.lastError { return "\(source.name) didn't answer: \(error) Tech60 will try again soon." }
        if s?.lastSuccess == nil { return "Fetching new papers from \(source.name)." }
        let unrated = snapshot.stories.filter { $0.isResearch == true && $0.paperRated != true }.count
        if !researchShowAll, unrated > 0, summariesEnabled, summaryProblem == nil {
            return "Rating \(unrated) new papers on your Mac. Notable ones appear as they're rated; All shows everything now."
        }
        if !researchShowAll, !researchPapers(notableOnly: false).isEmpty {
            return "No notable papers yet. Choose All to see every new paper."
        }
        return "\(source.name) sent no new papers. Tech60 checks again every few hours."
    }

    /// The row with this id, from the news or the Research tab.
    func cluster(id: String) -> StoryCluster? {
        clusters.first { $0.id == id || $0.stories.contains { $0.id == id } }
            ?? researchClusters.first { $0.id == id }
    }

    /// The Research tab: new papers, newest first, one per row.
    var researchClusters: [StoryCluster] {
        var papers = researchPapers(notableOnly: !researchShowAll)
        if let g = researchGroup { papers = papers.filter { $0.paperGroup == g.rawValue } }
        return papers.prefix(100).map { StoryCluster(stories: [$0]) }
    }

    /// Research shows notable papers by default; "All" shows every new one.
    @Published var researchShowAll = false
    /// A group chip in Research, or nil for every group.
    @Published var researchGroup: PaperGroup?

    /// Groups that match followed news topics, so Research lifts them a little.
    var followedPaperGroups: Set<PaperGroup> {
        Set(followedTopicIDs.compactMap { id -> PaperGroup? in
            switch id {
            case "agents": return .agents
            case "models": return .models
            case "security": return .safety
            case "devtools": return .applied
            default: return nil
            }
        })
    }

    /// Papers from enabled research feeds: notable ones best first, or all of them newest first.
    func researchPapers(notableOnly: Bool) -> [Story] {
        let enabled = Set(sources.filter { $0.kind == .research && $0.isEnabled }.map(\.id))
        let papers = snapshot.stories.filter { $0.isResearch == true && enabled.contains($0.sourceID) && !hiddenIDs.contains($0.id) }
        guard notableOnly else { return papers.sorted { $0.displayDate > $1.displayDate } }
        let followed = followedPaperGroups
        return papers.filter(PaperSignals.isNotable).sorted {
            let a = PaperSignals.score($0, followed: followed), b = PaperSignals.score($1, followed: followed)
            return a != b ? a > b : $0.displayDate > $1.displayDate
        }
    }

    /// Group chips for Research: groups with papers in the current view, followed groups first, with counts.
    struct GroupCount: Identifiable { let group: PaperGroup; let count: Int; var id: String { group.rawValue } }
    var researchGroupCounts: [GroupCount] {
        let papers = researchPapers(notableOnly: !researchShowAll)
        let followed = followedPaperGroups
        return PaperGroup.allCases.compactMap { g in
            let n = papers.filter { $0.paperGroup == g.rawValue }.count
            return n > 0 ? GroupCount(group: g, count: n) : nil
        }.sorted { followed.contains($0.group) && !followed.contains($1.group) }
    }

    private func rebuild() {
        clusters = Clustering.cluster(recentStories)
        maxScore = clusters.map { Hotness.score($0, topics: followedTopics, taste: taste) }.max() ?? 1
    }

    /// How hot a row is next to the hottest one on the card, 0.12 to 1, for the heat ring.
    func heatFraction(_ cluster: StoryCluster) -> Double {
        min(1, max(0.12, Hotness.score(cluster, topics: followedTopics, taste: taste) / max(maxScore, 0.0001)))
    }

    /// The section label above a headline: the first topic it matches, followed topics first.
    func kicker(for cluster: StoryCluster) -> String? {
        if cluster.lead.isResearch == true, let g = cluster.lead.paperGroup.flatMap(PaperGroup.init(rawValue:)) { return g.name }
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
                .sorted { Hotness.score($0, topics: topics, taste: taste) > Hotness.score($1, topics: topics, taste: taste) }
        }
        if sortMode == .research { return hasResearch ? researchClusters : Hotness.hot(clusters, topics: topics, taste: taste) }
        if sortMode == .hot { return Hotness.hot(clusters, topics: topics, taste: taste) }
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
        let picks = Brief.pick(clusters, topics: followedTopics, taste: taste, since: since, now: now)
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
            briefIDs = Brief.pick(clusters, topics: followedTopics, taste: taste, since: Date().addingTimeInterval(-24 * 3600)).map(\.id)
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

    // MARK: Learning from the reader

    /// "More like this" raises similar stories; "Less like this" lowers them and hides this one.
    func feedback(_ cluster: StoryCluster, more: Bool) {
        taste.record(cluster, more: more)
        if !more { hiddenIDs.formUnion(cluster.stories.map(\.id)) }
    }

    func resetTaste() {
        taste = Taste()
        hiddenIDs = []
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
        await engine.prewarm()
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
        // The editor pass rates new headlines before the card is ranked and summaries are queued.
        // Papers are rated 15 at a time, so notable ones show up as each batch finishes.
        while summariesEnabled, let rated = await engine.ratePapers(limit: 15) { snapshot = rated }
        if summariesEnabled, let rated = await engine.rateHeadlines() { snapshot = rated }
        isRefreshing = false
        await prepareTopSummaries()
        loadImages()
    }

    /// Summarizes the top stories in the background, so opening one shows its summary at once.
    func prepareTopSummaries() async {
        guard summariesEnabled, !isDemo else { return }
        // Papers take a few seconds each, so the Research tab writes ahead further than the news tabs.
        let ids = visibleClusters.prefix(sortMode == .research && topicTab == nil ? 30 : 10).map(\.summaryStory.id)
        if sortMode == .research { await engine.prewarmExplainer() }
        snapshot = await engine.prioritize(ids: ids)
        startSummaries()
    }

    /// A row scrolled into view in Research: queue its explainer so it's ready before it's opened.
    func queueAhead(_ cluster: StoryCluster) {
        guard summariesEnabled, !isDemo, sortMode == .research, cluster.lead.summary == .none else { return }
        Task {
            snapshot = await engine.enqueue(id: cluster.lead.id)
            startSummaries()
        }
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
