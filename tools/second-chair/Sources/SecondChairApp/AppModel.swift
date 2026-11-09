import AppKit
import SwiftUI
import UniformTypeIdentifiers
import SecondChairCore

/// One question and what came back, for the answer view and its history.
struct Asked: Identifiable {
    var id = UUID()
    var question: String
    var card: AnswerCard?
    var answering = true
    var askedAt = Date()
    /// Whole sections that answer it, best first, each with the passages that matched.
    var results: [SectionMatch] = []
    /// Looked up from the conversation as it happens, not asked as a question.
    var live = false
    /// Other sections and questions in your documents that resemble it.
    var similar: [SectionMatch] = []
}

/// A document in the library, grouped from the index.
struct IndexedDocument: Identifiable, Hashable {
    var id: String { path }
    var path: String
    var passages: Int
    var name: String { (path as NSString).lastPathComponent }
    var kind: String { (path as NSString).pathExtension.uppercased() }
}

/// Everything the windows show, in one place.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var folders: [String] = []
    @Published var primaryFolder: String?
    @Published var documents: [String: [IndexedDocument]] = [:]
    @Published var skipped: [String] = []
    @Published var indexStatus = ""
    @Published var isIndexing = false
    @Published var isStale = false
    @Published var passageCount = 0
    @Published var usesEmbeddings = false

    @Published var modelsSummary = "Checking local models…"
    @Published var fastReady = false
    @Published var qualityReady = false

    @Published var current: Asked?
    @Published var history: [Asked] = []
    /// What the overlay shows: the latest question from any source.
    @Published var overlayItem: Asked?

    @Published var sessionActive = false
    @Published var sessionStatus = ""
    @Published var sessionHearing: [String] = []
    @Published var dictating = false
    @Published var review: SessionLog?
    @Published var warning: (title: String, text: String)?

    @Published var gate: GateResult? = GateStore.latest
    @Published var gateFailures = GateStore.consecutiveFailures
    @Published var gateRunning = false
    @Published var showGateResult = false

    @Published var overlayFocusTick = 0
    @Published var showSetup = false
    @Published var showSettings = false

    let session = SessionController()
    /// What's being heard right now. Kept apart so meters and words-in-progress, which change many times a
    /// second, redraw only the live panel and not the answer and document views.
    let live = LiveState()
    var statusItem: NSStatusItem?
    private var askTask: Task<Void, Never>?

    init() {
        Library.shared.onChange = { [weak self] in Task { @MainActor in self?.syncLibrary() } }
        session.onQuestion = { [weak self] q in Task { @MainActor in self?.ask(q, fromSession: true) } }
        session.onPartial = { [weak self] c, t in Task { @MainActor in
            self?.live.heardPartial = String(t.suffix(160))
            self?.live.partials[c] = t
            self?.suggestFromConversation()
        } }
        session.onHeard = { [weak self] u in Task { @MainActor in
            guard let self else { return }
            self.live.partials[u.channel] = nil
            self.live.heardPartial = ""
            self.live.transcript.append(u)
            self.suggestFromConversation(force: true)
            if self.live.transcript.count > 200 { self.live.transcript.removeFirst() }
        } }
        session.onRetract = { [weak self] u in Task { @MainActor in
            self?.live.transcript.removeAll { $0.channel == u.channel && $0.text == u.text && $0.at == u.at }
        } }
        session.onLevel = { [weak self] c, v in Task { @MainActor in
            guard let self, abs((self.live.levels[c] ?? 0) - v) > 0.03 else { return }
            self.live.levels[c] = v
        } }
        session.onStatus = { [weak self] t in Task { @MainActor in self?.live.listenStatus = t } }
        session.onChange = { [weak self] in Task { @MainActor in self?.syncSession() } }
        session.onWarning = { [weak self] t, x in Task { @MainActor in self?.warning = (t, x) } }
    }

    // MARK: Library

    func syncLibrary() {
        let lib = Library.shared
        folders = lib.folders
        primaryFolder = lib.primaryFolder
        isIndexing = lib.isBuilding
        isStale = lib.isStale
        indexStatus = lib.statusLine
        passageCount = lib.index.chunks.count
        usesEmbeddings = lib.index.embedderName != nil
        skipped = lib.index.skipped
        var byFile: [String: Int] = [:]
        var folderOf: [String: String] = [:]
        for c in lib.index.chunks {
            byFile[c.file, default: 0] += 1
            folderOf[c.file] = c.folder
        }
        var grouped: [String: [IndexedDocument]] = [:]
        for (file, n) in byFile { grouped[folderOf[file] ?? "", default: []].append(IndexedDocument(path: file, passages: n)) }
        documents = grouped.mapValues { $0.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
    }

    func addFolders(_ urls: [URL]) {
        var list = Library.shared.folders
        for url in urls {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { continue }
            if !list.contains(url.path) { list.append(url.path) }
        }
        guard list != Library.shared.folders else { return }
        let wasEmpty = Library.shared.folders.isEmpty
        Library.shared.folders = list
        if wasEmpty, Library.shared.primaryFolder == nil { Library.shared.primaryFolder = list.first }
        rebuild()
    }

    func chooseFolders() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        panel.message = "Choose folders of documents to answer from. Nothing else on this Mac is read."
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK { addFolders(panel.urls) }
    }

    func chooseGateFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.message = "Choose a question set (JSON). See examples/gate-questions.json for the format."
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url { runGate(url) }
    }

    func removeFolder(_ folder: String) {
        Library.shared.folders.removeAll { $0 == folder }
        if Library.shared.primaryFolder == folder { Library.shared.primaryFolder = nil }
        rebuild()
    }

    func togglePrimary(_ folder: String) {
        Library.shared.primaryFolder = Library.shared.primaryFolder == folder ? nil : folder
        syncLibrary()
    }

    func rebuild() {
        Library.shared.rebuild(embedder: AppState.shared.models.embedder) { [weak self] in
            Task { @MainActor in self?.syncLibrary() }
        }
        syncLibrary()
    }

    func discoverModels() async {
        let before = AppState.shared.models.embedder?.name
        AppState.shared.models = await Models.discover()
        let m = AppState.shared.models
        modelsSummary = m.summary
        fastReady = m.fast != nil
        qualityReady = m.quality != nil
        if m.embedder?.name != before, !Library.shared.folders.isEmpty, !Library.shared.isBuilding,
           Library.shared.index.embedderName != m.embedder?.name {
            rebuild()
        }
    }

    // MARK: Asking

    // MARK: Live suggestions

    private var lastLiveLookup = Date.distantPast
    private var lastLiveWindow = ""
    /// After you ask or pick something yourself, live suggestions hold off so they don't replace it.
    private var holdLiveUntil = Date.distantPast
    private var liveTask: Task<Void, Never>?

    /// What's being said right now: the line in progress, or the last finished line. One line, so an earlier
    /// topic doesn't drown out a new question. Their side first when they've just spoken.
    private var conversationWindow: String {
        func latest(_ c: Channel) -> String? {
            if let p = live.partials[c], Lexicon.terms(p).count >= 3 { return p }
            if let u = live.transcript.last(where: { $0.channel == c }), Date().timeIntervalSince(u.at) < 20 { return u.text }
            return nil
        }
        let line = latest(.them) ?? latest(.you) ?? ""
        // Within a long line, the most recent sentence or two.
        let sentences = Lexicon.sentences(line)
        let recent = sentences.suffix(2).joined(separator: " ")
        return Lexicon.words(Lexicon.terms(recent).count >= 3 ? recent : line).suffix(30).joined(separator: " ")
    }

    /// While people talk, look up what they're talking about every couple of seconds, no question needed.
    func suggestFromConversation(force: Bool = false) {
        guard sessionActive, Date() > holdLiveUntil,
              force || Date().timeIntervalSince(lastLiveLookup) > 2.5 else { return }
        let window = conversationWindow
        // One meaningful word is enough ("...about Synopsys"): headings and prepared questions are short too.
        guard Lexicon.terms(window).count >= 1, window != lastLiveWindow else { return }
        lastLiveLookup = Date()
        lastLiveWindow = window
        let lib = Library.shared
        let retriever = Retriever(index: lib.index, primaryFolder: lib.primaryFolder, embedder: AppState.shared.models.embedder)
        let answerer = Answerer()  // no model: suggestions must keep up with speech
        liveTask?.cancel()
        liveTask = Task { @MainActor in
            let hits = await retriever.retrieve(window)
            guard !Task.isCancelled, Date() > self.holdLiveUntil else { return }
            let index = lib.index
            let (results, similar) = await Task.detached(priority: .userInitiated) {
                let r = Self.withTitleMatches(index, window, index.sections(for: hits.filter { answerer.isAlternative($0) }, question: window))
                return (r, index.similarSections(to: window, excluding: Set(r.map(\.id)), limit: 8))
            }.value
            guard !Task.isCancelled else { return }
            guard !results.isEmpty else {
                // Say so instead of staying silent; keep the last suggestion on screen.
                self.live.listenStatus = "Nothing in your docs for \u{201C}\(window.suffix(60))\u{201D}"
                return
            }
            self.live.listenStatus = "Listening"
            let card = await answerer.answer(window, hits: hits)
            var item = Asked(question: window)
            item.live = true
            item.answering = false
            item.card = card
            item.results = results
            item.similar = similar
            // Keep the same item while the top match is unchanged, so the view doesn't jump.
            if let cur = self.current, cur.live, cur.results.first?.id == results.first?.id { item.id = cur.id }
            self.current = item
            self.overlayItem = item
        }
    }

    /// A section whose heading says what was asked goes first, even when its body uses other words.
    nonisolated static func withTitleMatches(_ index: CorpusIndex, _ question: String, _ results: [SectionMatch]) -> [SectionMatch] {
        var titled = index.titleMatches(question)
        // Keep what search found inside a titled section, so its answer sentences stay marked.
        for i in titled.indices {
            if let found = results.first(where: { $0.id == titled[i].id }) {
                titled[i].matched = found.matched
                titled[i].primary = found.primary
            }
        }
        let ids = Set(titled.map(\.id))
        return titled + results.filter { !ids.contains($0.id) }
    }

    func holdLiveSuggestions(_ seconds: TimeInterval = 20) { holdLiveUntil = Date().addingTimeInterval(seconds) }

    func ask(_ question: String, fromSession: Bool = false) {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        liveTask?.cancel()
        holdLiveSuggestions(fromSession ? 12 : 20)
        let lib = Library.shared
        let models = AppState.shared.models
        let retriever = Retriever(index: lib.index, primaryFolder: lib.primaryFolder, embedder: models.embedder)
        let answerer = Answerer(fast: models.fast, quality: models.quality)
        let previous = session.isActive ? session.log.recentQuestions() : history.prefix(1).map(\.question)
        let started = Date()
        let item = Asked(question: q)
        let id = item.id
        current = item
        overlayItem = item
        live.heardPartial = ""
        askTask?.cancel()
        askTask = Task { @MainActor in
            let hits = await retriever.retrieve(q, previous: previous)
            let index = lib.index
            let (results, similar) = await Task.detached(priority: .userInitiated) {
                let r = Self.withTitleMatches(index, q, index.sections(for: hits.filter { answerer.isAlternative($0) }, question: q))
                return (r, index.similarSections(to: q, excluding: Set(r.map(\.id))))
            }.value
            let card = await answerer.answer(q, hits: hits, started: started) { source in
                Task { @MainActor in
                    guard self.current?.id == id else { return }
                    self.current?.card = source
                    self.current?.results = results
                    self.current?.similar = similar
                    self.overlayItem = self.current
                }
            }
            guard !Task.isCancelled, self.current?.id == id else { return }
            var finished = item
            finished.results = results
            finished.similar = similar
            finished.card = card
            finished.answering = false
            self.current = finished
            self.overlayItem = finished
            self.history.insert(finished, at: 0)
            if self.history.count > 30 { self.history.removeLast() }
            if self.session.isActive { self.session.log.review.append(ReviewItem(card: card)) }
        }
    }

    /// Shows one section as the current result, for a similar question picked from the list.
    func open(_ match: SectionMatch) {
        var item = Asked(question: match.section.title)
        item.answering = false
        item.results = [match]
        item.similar = Library.shared.index.similarSections(to: match.section.title, excluding: [match.id])
        current = item
        overlayItem = item
    }

    func askLastExchange() {
        if let last = session.log.lastExchange { ask(last) } else { focusOverlay() }
    }

    func focusOverlay() { overlayFocusTick += 1 }

    // MARK: Sessions

    func startSession(_ consent: ConsentGate, primary: String?) {
        live.transcript = []
        live.partials = [:]
        live.levels = [:]
        live.listenStatus = ""
        Library.shared.primaryFolder = primary
        syncLibrary()
        session.start(consent)
        syncSession()
    }

    func endSession() {
        if let log = session.end() { review = log }
        live.transcript = []
        live.partials = [:]
        live.levels = [:]
        syncSession()
    }

    func syncSession() {
        if sessionActive != session.isActive { PrivacyGuard.setDiscreet(session.isActive, statusItem: statusItem) }
        sessionActive = session.isActive
        sessionStatus = session.statusLine
        sessionHearing = session.hearing
        dictating = session.dictating
    }

    /// Writes misses to the primary pack and drops the transcript unless asked to keep it.
    func finishReview(saveTranscript: Bool) {
        guard let log = review else { return }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH-mm"
        let stamp = f.string(from: session.started)
        let title = "Interview \(stamp)"
        let misses = log.missesMarkdown(title: title)
        if !misses.isEmpty, let folder = Library.shared.primaryFolder ?? Library.shared.folders.first {
            let url = URL(fileURLWithPath: folder).appendingPathComponent("_second-chair misses \(stamp).md")
            try? misses.write(to: url, atomically: true, encoding: .utf8)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
        if saveTranscript {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "\(title) transcript.md"
            if panel.runModal() == .OK, let url = panel.url {
                try? log.transcriptMarkdown(title: title).write(to: url, atomically: true, encoding: .utf8)
            }
        }
        log.discardTranscript()
        log.review.removeAll()
        review = nil
    }

    // MARK: Gate

    var gatePassed: Bool { gate?.passed == true }

    func runGate(_ url: URL) {
        guard let data = try? Data(contentsOf: url), let questions = try? JSONDecoder().decode([GateQuestion].self, from: data) else {
            warning = ("Couldn't read that file", "The gate file is a JSON list of questions. See examples/gate-questions.json for the format.")
            return
        }
        let lib = Library.shared
        let models = AppState.shared.models
        let retriever = Retriever(index: lib.index, primaryFolder: lib.primaryFolder, embedder: models.embedder)
        let answerer = Answerer(fast: models.fast, quality: models.quality)
        gateRunning = true
        Task { @MainActor in
            let result = await Gate.run(questions, retriever: retriever, answerer: answerer)
            GateStore.save(result)
            self.gate = result
            self.gateFailures = GateStore.consecutiveFailures
            self.gateRunning = false
            self.showGateResult = true
        }
    }
}

/// Fast-changing session state: words in progress, the running transcript, input levels.
@MainActor
final class LiveState: ObservableObject {
    @Published var heardPartial = ""
    /// The live transcript, newest last. Kept only for the session; deleted with it.
    @Published var transcript: [Utterance] = []
    @Published var partials: [Channel: String] = [:]
    @Published var levels: [Channel: Float] = [:]
    @Published var listenStatus = ""
}
