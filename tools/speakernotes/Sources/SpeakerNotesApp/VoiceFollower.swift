import AVFoundation
import Speech

/// Listens to your microphone (only your voice, never the call's audio) with Apple's on-device speech
/// recognition, and passes on the latest words heard. Nothing is sent anywhere or saved.
final class VoiceFollower {
    /// The most recent words heard, oldest first. Called on the main thread.
    var onHeard: (([String]) -> Void)?
    var onStatus: ((String) -> Void)?
    var onChange: (() -> Void)?
    /// Words from the script, to help the recognizer with names and jargon.
    var hints: [String] = [] {
        didSet { if isOn, Set(hints) != Set(oldValue) { startTask() } }
    }
    /// A little more of what was heard, for prefilling a parked question.
    private(set) var recentText = ""

    private(set) var isOn = false
    private let engine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var taskID = UUID()
    private var restartTimer: Timer?
    private let lock = NSLock()

    func start() {
        guard !isOn else { return }
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                guard status == .authorized else {
                    self.onStatus?("Allow Speech Recognition for SpeakerNotes in System Settings > Privacy & Security")
                    return
                }
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    DispatchQueue.main.async {
                        guard granted else {
                            self.onStatus?("Allow the microphone for SpeakerNotes in System Settings > Privacy & Security")
                            return
                        }
                        self.begin()
                    }
                }
            }
        }
    }

    private func begin() {
        guard !isOn else { return }
        let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        guard let recognizer, recognizer.isAvailable else {
            onStatus?("Speech recognition isn't available right now")
            return
        }
        guard recognizer.supportsOnDeviceRecognition else {
            onStatus?("This Mac can't recognize speech on device, so voice following stays off")
            return
        }
        self.recognizer = recognizer
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { [weak self] buffer, _ in
            guard let self else { return }
            self.lock.lock()
            let request = self.request
            self.lock.unlock()
            request?.append(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            onStatus?("Couldn't start the microphone: \(error.localizedDescription)")
            return
        }
        isOn = true
        startTask()
        // Short recognition sessions keep the recognizer quick and its guesses focused on what you just said.
        restartTimer = Timer.scheduledTimer(withTimeInterval: 45, repeats: true) { [weak self] _ in self?.startTask() }
        onChange?()
    }

    func stop() {
        guard isOn else { return }
        isOn = false
        restartTimer?.invalidate()
        restartTimer = nil
        taskID = UUID()
        task?.cancel()
        task = nil
        lock.lock()
        request?.endAudio()
        request = nil
        lock.unlock()
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        recentText = ""
        onChange?()
    }

    private func startTask() {
        guard isOn, let recognizer else { return }
        let id = UUID()
        taskID = id
        task?.cancel()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.addsPunctuation = false
        request.contextualStrings = Array(hints.prefix(100))
        lock.lock()
        self.request?.endAudio()
        self.request = request
        lock.unlock()
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self, self.taskID == id else { return }
                if let result {
                    let segments = result.bestTranscription.segments.map(\.substring)
                    self.recentText = segments.suffix(24).joined(separator: " ")
                    self.onHeard?(Array(segments.suffix(10)))
                }
                if error != nil || result?.isFinal == true {
                    // The session ended (silence, or an error): start a fresh one shortly.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        if self.isOn, self.taskID == id { self.startTask() }
                    }
                }
            }
        }
    }
}
