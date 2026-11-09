import AppKit
import Carbon.HIToolbox
import UniformTypeIdentifiers
import SecondChairCore

/// Shared state: which models are running right now.
final class AppState {
    static let shared = AppState()
    var models = Models.Available(fast: nil, quality: nil, embedder: nil, summary: "Checking local models…")
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let overlay = Overlay()
    private let session = SessionController()
    private let hotKeys = HotKeys()
    private var askTask: Task<Void, Never>?
    private var freshnessTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "chair", accessibilityDescription: "Second Chair")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        overlay.onAsk = { [weak self] q in self?.ask(q) }
        session.onQuestion = { [weak self] q in self?.ask(q) }
        session.onPartial = { [weak self] c, t in self?.overlay.showPartial(c, t) }
        session.onChange = { [weak self] in self?.refreshStatus() }
        Library.shared.onChange = { [weak self] in self?.refreshStatus() }

        hotKeys.register(kVK_Space) { [weak self] in self?.overlay.focusQuery() }
        hotKeys.register(kVK_ANSI_S) { [weak self] in self?.overlay.toggle() }
        hotKeys.register(kVK_ANSI_A) { [weak self] in self?.askLastExchange() }
        hotKeys.register(kVK_ANSI_D) { [weak self] in self?.session.toggleDictation() }

        Library.shared.load()
        overlay.panel.orderFrontRegardless()
        refreshStatus()
        Task { @MainActor in
            AppState.shared.models = await Models.discover()
            self.refreshStatus()
            if Library.shared.isStale, !Library.shared.folders.isEmpty { self.rebuild() }
        }
        // The index watches its folders between sessions; it never rebuilds mid-interview.
        freshnessTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self, !self.session.isActive else { return }
            Library.shared.checkFreshness()
            if Library.shared.isStale, !Library.shared.isBuilding, !Library.shared.folders.isEmpty { self.rebuild() }
        }
    }

    private func refreshStatus() {
        let lib = Library.shared
        let pack = lib.primaryFolder.map { "pack: \(($0 as NSString).lastPathComponent)" } ?? "no primary pack"
        overlay.setStatus([session.isActive ? session.statusLine : lib.statusLine, pack].joined(separator: " · "))
        statusItem.button?.image = NSImage(systemSymbolName: session.isActive ? "chair.fill" : "chair",
                                           accessibilityDescription: "Second Chair")
    }

    // MARK: Asking

    private func ask(_ question: String) {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        let lib = Library.shared
        let models = AppState.shared.models
        var retriever = Retriever(index: lib.index, primaryFolder: lib.primaryFolder, embedder: models.embedder)
        retriever.settings.maxHits = 4
        let answerer = Answerer(fast: models.fast, quality: models.quality)
        let previous = session.isActive ? session.log.recentQuestions() : []
        let started = Date()
        overlay.showSearching(q)
        askTask?.cancel()
        askTask = Task { @MainActor in
            let hits = await retriever.retrieve(q, previous: previous)
            let card = await answerer.answer(q, hits: hits, started: started) { card in
                DispatchQueue.main.async { self.overlay.showSource(card) }
            }
            guard !Task.isCancelled else { return }
            self.overlay.showAnswer(card)
            if self.session.isActive { self.session.log.review.append(ReviewItem(card: card)) }
        }
    }

    private func askLastExchange() {
        if let last = session.log.lastExchange { ask(last) } else { overlay.focusQuery() }
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let lib = Library.shared
        @discardableResult func item(_ title: String, _ action: Selector?, _ key: String = "", enabled: Bool = true) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
            i.target = self
            i.isEnabled = enabled
            menu.addItem(i)
            return i
        }
        func info(_ title: String) { let i = NSMenuItem(title: title, action: nil, keyEquivalent: ""); i.isEnabled = false; menu.addItem(i) }

        info(lib.statusLine)
        info(AppState.shared.models.summary)
        if let g = GateStore.latest {
            info(g.passed ? "Gate passed \(g.date.formatted(date: .abbreviated, time: .shortened))"
                          : "Gate failed (\(GateStore.consecutiveFailures)x): live listening locked")
        } else {
            info("Gate not run: live listening locked")
        }
        menu.addItem(.separator())
        item("Ask My Docs  ⌃⌥Space", #selector(askMenu))
        item(overlay.panel.isVisible ? "Hide Window  ⌃⌥S" : "Show Window  ⌃⌥S", #selector(toggleWindow))
        item("Ask About Last Exchange  ⌃⌥A", #selector(askLast), enabled: session.isActive)
        menu.addItem(.separator())
        if session.isActive {
            info(session.statusLine)
            item(session.dictating ? "Stop Dictating  ⌃⌥D" : "Dictate Question  ⌃⌥D", #selector(dictate))
            item("End Session and Review", #selector(endSession))
        } else {
            item("Start Session…", #selector(startSession), enabled: !lib.folders.isEmpty)
        }
        menu.addItem(.separator())

        let folders = NSMenu()
        for f in lib.folders {
            let i = NSMenuItem(title: (f as NSString).abbreviatingWithTildeInPath, action: nil, keyEquivalent: "")
            let sub = NSMenu()
            let pin = NSMenuItem(title: lib.primaryFolder == f ? "Primary Prep Pack ✓" : "Make Primary Prep Pack", action: #selector(pinFolder(_:)), keyEquivalent: "")
            pin.representedObject = f; pin.target = self
            let rm = NSMenuItem(title: "Remove", action: #selector(removeFolder(_:)), keyEquivalent: "")
            rm.representedObject = f; rm.target = self
            sub.addItem(pin); sub.addItem(rm)
            i.submenu = sub
            folders.addItem(i)
        }
        if !lib.folders.isEmpty { folders.addItem(.separator()) }
        let add = NSMenuItem(title: "Add Folder…", action: #selector(addFolder), keyEquivalent: "")
        add.target = self
        folders.addItem(add)
        let foldersItem = item("Folders (\(lib.folders.count))", nil)
        foldersItem.submenu = folders
        item(lib.isBuilding ? "Indexing…" : "Rebuild Index", #selector(rebuildMenu), enabled: !lib.isBuilding && !session.isActive)
        if !lib.index.skipped.isEmpty { item("Skipped Files (\(lib.index.skipped.count))…", #selector(showSkipped)) }
        menu.addItem(.separator())

        item("Run Gate…", #selector(runGate), enabled: !lib.index.chunks.isEmpty && !session.isActive)
        if GateStore.latest != nil { item("Open Last Gate Report", #selector(openGateReport)) }

        let settings = NSMenu()
        for e in Settings.Engine.allCases {
            let i = NSMenuItem(title: e.title, action: #selector(setEngine(_:)), keyEquivalent: "")
            i.representedObject = e.rawValue; i.target = self; i.state = Settings.engine == e ? .on : .off
            settings.addItem(i)
        }
        settings.addItem(.separator())
        let embedTitles: [Models.EmbeddingChoice: String] = [.ollama: "Embeddings: EmbeddingGemma via Ollama", .apple: "Embeddings: Apple built-in", .none: "Embeddings: off (keyword only)"]
        for c in Models.EmbeddingChoice.allCases {
            let i = NSMenuItem(title: embedTitles[c] ?? c.rawValue, action: #selector(setEmbedding(_:)), keyEquivalent: "")
            i.representedObject = c.rawValue; i.target = self; i.state = Models.embeddingChoice == c ? .on : .off
            settings.addItem(i)
        }
        settings.addItem(.separator())
        let recheck = NSMenuItem(title: "Recheck Local Models", action: #selector(recheckModels), keyEquivalent: "")
        recheck.target = self
        settings.addItem(recheck)
        let settingsItem = item("Settings", nil)
        settingsItem.submenu = settings
        menu.addItem(.separator())
        item("Quit Second Chair", #selector(NSApplication.terminate(_:)), "q").target = NSApp
    }

    @objc private func askMenu() { overlay.focusQuery() }
    @objc private func toggleWindow() { overlay.toggle() }
    @objc private func askLast() { askLastExchange() }
    @objc private func dictate() { session.toggleDictation() }
    @objc private func startSession() { session.begin() }
    @objc private func endSession() { session.end(); overlay.showIdle() }

    @objc private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.message = "Choose folders to answer from: your Obsidian vault, an interview prep pack. Nothing else on the Mac is read."
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        var folders = Library.shared.folders
        for url in panel.urls where !folders.contains(url.path) { folders.append(url.path) }
        Library.shared.folders = folders
        rebuild()
    }

    @objc private func removeFolder(_ sender: NSMenuItem) {
        guard let f = sender.representedObject as? String else { return }
        Library.shared.folders.removeAll { $0 == f }
        if Library.shared.primaryFolder == f { Library.shared.primaryFolder = nil }
        rebuild()
    }

    @objc private func pinFolder(_ sender: NSMenuItem) {
        guard let f = sender.representedObject as? String else { return }
        Library.shared.primaryFolder = Library.shared.primaryFolder == f ? nil : f
    }

    @objc private func rebuildMenu() { rebuild() }

    private func rebuild() {
        Library.shared.rebuild(embedder: AppState.shared.models.embedder) { [weak self] in self?.refreshStatus() }
    }

    @objc private func showSkipped() {
        let a = NSAlert()
        a.messageText = "Skipped (no text layer or not a supported format)"
        a.informativeText = Library.shared.index.skipped.prefix(40).map { ($0 as NSString).abbreviatingWithTildeInPath }.joined(separator: "\n")
        a.runModal()
    }

    @objc private func runGate() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.message = "Choose your labelled gate questions (JSON). See examples/gate-questions.json for the format."
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url), let questions = try? JSONDecoder().decode([GateQuestion].self, from: data) else { return }
        let lib = Library.shared
        let models = AppState.shared.models
        let retriever = Retriever(index: lib.index, primaryFolder: lib.primaryFolder, embedder: models.embedder)
        let answerer = Answerer(fast: models.fast, quality: models.quality)
        overlay.setStatus("Running the gate on \(questions.count) questions…")
        Task { @MainActor in
            let result = await Gate.run(questions, retriever: retriever, answerer: answerer)
            GateStore.save(result)
            self.refreshStatus()
            let a = NSAlert()
            a.messageText = result.passed ? "Gate passed: live listening unlocked" : "Gate failed: live listening stays locked"
            var text = result.failures.isEmpty ? "Every bar met." : result.failures.joined(separator: "\n")
            if !result.passed, GateStore.consecutiveFailures >= 2 {
                text += "\n\nThat's two failures in a row. Use Ask My Docs (type or dictate) until a run passes."
            }
            a.informativeText = text
            a.addButton(withTitle: "Open Report")
            a.addButton(withTitle: "OK")
            if a.runModal() == .alertFirstButtonReturn { self.openGateReport() }
        }
    }

    @objc private func openGateReport() {
        NSWorkspace.shared.open(Library.supportDirectory.appendingPathComponent("gate-report.md"))
    }

    @objc private func setEngine(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let e = Settings.Engine(rawValue: raw) else { return }
        Settings.engine = e
        if e == .whisper {
            Task { @MainActor in
                if !(await WhisperServerEngine.isRunning()) {
                    let a = NSAlert()
                    a.messageText = "whisper.cpp server isn't running"
                    a.informativeText = "Start it with: whisper-server -m <model.bin> --port \(WhisperServerEngine.port)\nUntil then, sessions can't transcribe."
                    a.runModal()
                }
            }
        }
    }

    @objc private func setEmbedding(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let c = Models.EmbeddingChoice(rawValue: raw) else { return }
        Models.embeddingChoice = c
        recheckModels()
    }

    @objc private func recheckModels() {
        Task { @MainActor in
            let before = AppState.shared.models.embedder?.name
            AppState.shared.models = await Models.discover()
            if AppState.shared.models.embedder?.name != before { self.rebuild() }
            self.refreshStatus()
        }
    }
}
