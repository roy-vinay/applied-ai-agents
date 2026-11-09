import AppKit
import SecondChairCore

/// One interview, start to finish: checklist and consent before, listening during, review after.
final class SessionController: NSObject {
    private(set) var gate: ConsentGate?
    private(set) var log = SessionLog()
    private var mic: MicCapture?
    private var system: SystemAudioCapture?
    private var you: ChannelListener?
    private var them: ChannelListener?
    private(set) var dictating = false
    private var started = Date()

    var onQuestion: ((String) -> Void)?
    var onPartial: ((Channel, String) -> Void)?
    var onChange: (() -> Void)?
    var isActive: Bool { gate != nil }

    /// "Session: Remote interview · Announced · hearing You + Them"
    var statusLine: String {
        guard let gate else { return "No session" }
        var hearing: [String] = []
        if mic?.running == true { hearing.append(dictating && !gate.mayListenContinuously ? "You (dictating)" : "You") }
        if system != nil { hearing.append("Them") }
        return "\(gate.kind.title) · \(gate.mode.title) · " + (hearing.isEmpty ? "not listening" : "hearing " + hearing.joined(separator: " + "))
    }

    // MARK: Before

    func begin() {
        guard !isActive else { return }
        let library = Library.shared
        let alert = NSAlert()
        alert.messageText = "Start an interview session"
        alert.informativeText = """
            \(library.statusLine)

            Checklist: wear headphones for remote calls. Turn on Do Not Disturb. Close tabs playing audio or video. \
            The window never appears in a screen share.
            """
        let kind = NSPopUpButton(), mode = NSPopUpButton(), pack = NSPopUpButton()
        kind.addItems(withTitles: SessionKind.allCases.map(\.title))
        mode.addItems(withTitles: CaptureMode.allCases.map(\.title))
        pack.addItem(withTitle: "No primary pack")
        for f in library.folders { pack.addItem(withTitle: (f as NSString).lastPathComponent); pack.lastItem?.representedObject = f }
        if let p = library.primaryFolder, let i = library.folders.firstIndex(of: p) { pack.selectItem(at: i + 1) }
        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Where:"), kind],
            [NSTextField(labelWithString: "Listening:"), mode],
            [NSTextField(labelWithString: "Primary prep pack:"), pack],
        ])
        grid.frame = NSRect(x: 0, y: 0, width: 360, height: 90)
        alert.accessoryView = grid
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")
        if library.isStale, !library.folders.isEmpty { alert.addButton(withTitle: "Rebuild Index First") }
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertThirdButtonReturn {
            Library.shared.rebuild(embedder: AppState.shared.models.embedder) { [weak self] in self?.begin() }
            return
        }
        guard response == .alertFirstButtonReturn else { return }
        library.primaryFolder = pack.selectedItem?.representedObject as? String

        var consent = ConsentGate(kind: SessionKind.allCases[kind.indexOfSelectedItem],
                                  mode: CaptureMode.allCases[mode.indexOfSelectedItem])

        // Live listening to another person is locked until the answering half passes the gate.
        if consent.mode == .announced, consent.kind != .rehearsal, !GateStore.passed {
            let locked = NSAlert()
            locked.messageText = "Live listening is locked"
            locked.informativeText = GateStore.latest == nil
                ? "Run the gate on your own question set first (menu › Run Gate…). Until it passes, use My Voice Only: dictate the question with ⌃⌥D, or type it."
                : "The last gate run failed: \(GateStore.latest?.failures.joined(separator: "; ") ?? ""). Fix the prep pack or thresholds and run it again. Until then, use My Voice Only."
            locked.addButton(withTitle: "Use My Voice Only")
            locked.addButton(withTitle: "Cancel")
            guard locked.runModal() == .alertFirstButtonReturn else { return }
            consent = ConsentGate(kind: consent.kind, mode: .myVoiceOnly)
        }

        if consent.needsAttestation, !attest(&consent) { return }
        start(consent)
    }

    /// The per-session announcement. Capture of anyone else starts only after you confirm it here.
    private func attest(_ consent: inout ConsentGate) -> Bool {
        let say = NSAlert()
        say.messageText = "Say this when the call starts"
        say.informativeText = "\u{201C}\(ConsentGate.disclosure)\u{201D}\n\nListening to them starts only after you confirm below."
        say.addButton(withTitle: "I said it, no objection")
        say.addButton(withTitle: "They objected")
        say.addButton(withTitle: "Cancel")
        let copy = NSButton(title: "Copy sentence", target: nil, action: nil)
        copy.bezelStyle = .rounded
        copy.target = self
        copy.action = #selector(copyDisclosure)
        say.accessoryView = copy
        switch say.runModal() {
        case .alertFirstButtonReturn:
            consent.attest(saidIt: true, objection: false)
        case .alertSecondButtonReturn:
            consent.attest(saidIt: true, objection: true)
            let ok = NSAlert()
            ok.messageText = "Switched to My Voice Only"
            ok.informativeText = "Nothing of theirs will be captured. Dictate your paraphrase with ⌃⌥D, or type it."
            ok.runModal()
        default:
            return false
        }
        return true
    }

    @objc private func copyDisclosure() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ConsentGate.disclosure, forType: .string)
    }

    // MARK: During

    private func start(_ consent: ConsentGate) {
        gate = consent
        log = SessionLog()
        started = Date()
        Task { @MainActor in
            if consent.mode != .off, let problem = await MicCapture.requestPermissions() {
                self.warn("Can't listen", problem)
            }
            if consent.mayListenContinuously { self.startMic() }
            if consent.mayCaptureSystemAudio { await self.startSystemAudio() }
            self.onChange?()
        }
        onChange?()
    }

    private func makeListener(_ channel: Channel) -> ChannelListener {
        let l = ChannelListener(channel: channel, engine: Settings.makeEngine())
        l.onPartial = { [weak self] c, t in self?.onPartial?(c, t) }
        l.onUtterance = { [weak self] u in self?.heard(u) }
        return l
    }

    private func startMic() {
        guard mic == nil else { return }
        let listener = makeListener(.you)
        let capture = MicCapture()
        capture.onBuffer = { listener.append($0) }
        do {
            try capture.start()
            mic = capture
            you = listener
        } catch {
            warn("Microphone didn't start", error.localizedDescription)
        }
        onChange?()
    }

    private func stopMic() {
        you?.flush()
        mic?.stop()
        mic = nil
        onChange?()
    }

    @MainActor private func startSystemAudio() async {
        let listener = makeListener(.them)
        let capture = SystemAudioCapture()
        capture.onBuffer = { listener.append($0) }
        capture.onStop = { [weak self] reason in
            self?.system = nil
            self?.onChange?()
            self?.warn("System audio stopped", reason)
        }
        do {
            try await capture.start()
            system = capture
            them = listener
        } catch {
            warn("Can't hear the other side",
                 "Second Chair needs Screen Recording permission (System Settings › Privacy & Security › Screen & System Audio Recording). macOS puts system audio capture behind it. Nothing is recorded to disk. Error: \(error.localizedDescription)")
        }
        onChange?()
    }

    private func heard(_ u: Utterance) {
        guard let gate else { return }
        log.add(u)
        if dictating && !gate.mayListenContinuously {
            // Dictation is your own paraphrase of the question: always ask it.
            onQuestion?(u.text)
        } else if gate.detectsQuestions(on: u.channel), QuestionDetector.isQuestion(u.text) {
            onQuestion?(u.text)
        }
    }

    /// ⌃⌥D: dictate your paraphrase. In My Voice Only this is the only time the microphone is on.
    func toggleDictation() {
        guard let gate, gate.mayDictate else { return }
        if gate.mayListenContinuously { return } // already listening; nothing to toggle
        dictating.toggle()
        if dictating {
            Task { @MainActor in
                if let problem = await MicCapture.requestPermissions() { self.warn("Can't listen", problem); self.dictating = false; return }
                self.startMic()
            }
        } else {
            stopMic()
            // Leave dictating true until the last words arrive, then turn it off.
            dictating = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                guard let self, self.mic == nil else { return }
                self.dictating = false
                self.onChange?()
            }
        }
        onChange?()
    }

    // MARK: After

    func end() {
        guard gate != nil else { return }
        stopMic()
        system?.stop()
        system = nil
        you = nil
        them = nil
        gate = nil
        dictating = false
        onChange?()
        ReviewWindow.show(log: log, started: started)
    }

    private func warn(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.runModal()
    }
}

/// The post-session review: every detected question, what was shown, and its label. You mark misses;
/// misses go to the prep pack as a to-do note. The transcript is deleted unless you save it.
enum ReviewWindow {
    static func show(log: SessionLog, started: Date) {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH-mm"
        let title = "Interview \(f.string(from: started))"

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        var boxes: [NSButton] = []
        if log.review.isEmpty {
            stack.addArrangedSubview(NSTextField(labelWithString: "No questions were handled this session."))
        }
        for item in log.review {
            let box = NSButton(checkboxWithTitle: "Missed", target: nil, action: nil)
            boxes.append(box)
            let text = NSTextField(wrappingLabelWithString:
                "\(item.question)\n\(item.label.rawValue)\(item.source.map { " · \($0)" } ?? "")\(item.answer.map { "\n\u{201C}\($0)\u{201D}" } ?? "")\(item.withheld.map { "\n\($0)" } ?? "")")
            text.font = .systemFont(ofSize: 12)
            text.preferredMaxLayoutWidth = 480
            let row = NSStackView(views: [box, text])
            row.alignment = .top
            stack.addArrangedSubview(row)
        }

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 420))
        let doc = FlippedView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(stack)
        scroll.documentView = doc
        scroll.hasVerticalScroller = true
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: doc.leadingAnchor), stack.trailingAnchor.constraint(equalTo: doc.trailingAnchor),
            stack.topAnchor.constraint(equalTo: doc.topAnchor), stack.bottomAnchor.constraint(equalTo: doc.bottomAnchor),
            doc.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
        ])

        let alert = NSAlert()
        alert.messageText = "Review: \(log.review.count) question\(log.review.count == 1 ? "" : "s")"
        alert.informativeText = "Tick what the tool missed. Misses go to your primary prep pack as a to-do note. The transcript is deleted unless you save it."
        alert.accessoryView = scroll
        alert.addButton(withTitle: "Done, delete transcript")
        alert.addButton(withTitle: "Save transcript too")
        NSApp.activate(ignoringOtherApps: true)
        let saveTranscript = alert.runModal() == .alertSecondButtonReturn

        for (i, box) in boxes.enumerated() where box.state == .on { log.review[i].missed = true }
        let folder = Library.shared.primaryFolder ?? Library.shared.folders.first
        if let folder, !log.missesMarkdown(title: title).isEmpty {
            let url = URL(fileURLWithPath: folder).appendingPathComponent("_second-chair misses \(f.string(from: started)).md")
            try? log.missesMarkdown(title: title).write(to: url, atomically: true, encoding: .utf8)
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
    }
}

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
