import AppKit
import SecondChairCore

/// One interview's listening: which channels are on, and what they heard. Setup, consent and review
/// are SwiftUI sheets; this class only starts what the consent gate allows.
final class SessionController: NSObject {
    private(set) var gate: ConsentGate?
    private(set) var log = SessionLog()
    private var mic: MicCapture?
    private var system: SystemAudioCapture?
    private var you: ChannelListener?
    private var them: ChannelListener?
    private(set) var dictating = false
    private(set) var started = Date()

    var onQuestion: ((String) -> Void)?
    var onPartial: ((Channel, String) -> Void)?
    var onChange: (() -> Void)?
    var onWarning: ((String, String) -> Void)?
    var isActive: Bool { gate != nil }

    var hearing: [String] {
        guard let gate else { return [] }
        var h: [String] = []
        if mic?.running == true { h.append(dictating && !gate.mayListenContinuously ? "You (dictating)" : "You") }
        if system != nil { h.append("Them") }
        return h
    }

    /// "Remote interview · Announced · hearing You + Them"
    var statusLine: String {
        guard let gate else { return "No session" }
        return "\(gate.kind.title) · \(gate.mode.title) · " + (hearing.isEmpty ? "not listening" : "hearing " + hearing.joined(separator: " + "))
    }

    func start(_ consent: ConsentGate) {
        guard !isActive, !consent.needsAttestation else { return }
        gate = consent
        log = SessionLog()
        started = Date()
        Task { @MainActor in
            if consent.mode != .off, let problem = await MicCapture.requestPermissions() {
                self.onWarning?("Can't listen", problem)
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
            onWarning?("Microphone didn't start", error.localizedDescription)
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
            self?.onWarning?("System audio stopped", reason)
        }
        do {
            try await capture.start()
            system = capture
            them = listener
        } catch {
            onWarning?("Can't hear the other side",
                       "Second Chair needs Screen Recording permission (System Settings › Privacy & Security › Screen & System Audio Recording). macOS puts system audio capture behind it. Nothing is recorded to disk.")
        }
        onChange?()
    }

    private func heard(_ u: Utterance) {
        guard let gate else { return }
        log.add(u)
        if dictating && !gate.mayListenContinuously {
            onQuestion?(u.text)  // your own paraphrase: always ask it
        } else if gate.detectsQuestions(on: u.channel), QuestionDetector.isQuestion(u.text) {
            onQuestion?(u.text)
        }
    }

    /// ⌃⌥D: dictate your paraphrase. In My Voice Only this is the only time the microphone is on.
    func toggleDictation() {
        guard let gate, gate.mayDictate, !gate.mayListenContinuously else { return }
        if !dictating {
            dictating = true
            Task { @MainActor in
                if let problem = await MicCapture.requestPermissions() {
                    self.onWarning?("Can't listen", problem)
                    self.dictating = false
                    self.onChange?()
                    return
                }
                self.startMic()
            }
        } else {
            stopMic()
            // Keep accepting the last words for a moment, then stop treating speech as dictation.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                guard let self, self.mic == nil else { return }
                self.dictating = false
                self.onChange?()
            }
        }
        onChange?()
    }

    /// Stops every channel and hands back the log for review.
    func end() -> SessionLog? {
        guard gate != nil else { return nil }
        stopMic()
        system?.stop()
        system = nil
        you = nil
        them = nil
        gate = nil
        dictating = false
        onChange?()
        return log
    }
}
