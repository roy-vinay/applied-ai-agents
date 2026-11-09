import AppKit
import SwiftUI
import UniformTypeIdentifiers
import SecondChairCore

/// One question and what came back, for the answer view and its history.
struct Asked: Identifiable {
    let id = UUID()
    var question: String
    var card: AnswerCard?
    var answering = true
    var askedAt = Date()
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
    @Published var heardPartial = ""

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
    private var askTask: Task<Void, Never>?

    init() {
        Library.shared.onChange = { [weak self] in Task { @MainActor in self?.syncLibrary() } }
        session.onQuestion = { [weak self] q in Task { @MainActor in self?.ask(q, fromSession: true) } }
        session.onPartial = { [weak self] _, t in Task { @MainActor in self?.heardPartial = String(t.suffix(160)) } }
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

    func ask(_ question: String, fromSession: Bool = false) {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
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
        heardPartial = ""
        askTask?.cancel()
        askTask = Task { @MainActor in
            let hits = await retriever.retrieve(q, previous: previous)
            let card = await answerer.answer(q, hits: hits, started: started) { source in
                Task { @MainActor in
                    guard self.current?.id == id else { return }
                    self.current?.card = source
                    self.overlayItem?.card = source
                }
            }
            guard !Task.isCancelled, self.current?.id == id else { return }
            var finished = item
            finished.card = card
            finished.answering = false
            self.current = finished
            self.overlayItem = finished
            self.history.insert(finished, at: 0)
            if self.history.count > 30 { self.history.removeLast() }
            if self.session.isActive { self.session.log.review.append(ReviewItem(card: card)) }
        }
    }

    func askLastExchange() {
        if let last = session.log.lastExchange { ask(last) } else { focusOverlay() }
    }

    func focusOverlay() { overlayFocusTick += 1 }

    // MARK: Sessions

    func startSession(_ consent: ConsentGate, primary: String?) {
        Library.shared.primaryFolder = primary
        syncLibrary()
        session.start(consent)
        syncSession()
    }

    func endSession() {
        if let log = session.end() { review = log }
        syncSession()
    }

    func syncSession() {
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
