import AVFoundation
import ScreenCaptureKit
import Speech
import SecondChairCore

/// A simple energy voice-activity detector with a moving noise floor. It decides when an
/// utterance has ended, which is when retrieval starts.
final class EnergyVAD {
    private var floor: Float = 0.002
    private(set) var lastRMS: Float = 0
    var pause: TimeInterval = 0.7

    func isSpeech(_ buffer: AVAudioPCMBuffer) -> Bool {
        guard let data = buffer.floatChannelData, buffer.frameLength > 0 else { return false }
        let n = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<n { sum += data[0][i] * data[0][i] }
        let rms = (sum / Float(n)).squareRoot()
        lastRMS = rms
        let speech = rms > max(0.006, floor * 3)
        // The floor follows quiet stretches slowly, so a fan or hum doesn't count as speech.
        if !speech { floor = floor * 0.98 + rms * 0.02 }
        return speech
    }
}

/// Something that turns one utterance's audio into text on this Mac.
protocol SpeechEngine: AnyObject {
    var onFinal: ((String) -> Void)? { get set }
    var onPartial: ((String) -> Void)? { get set }
    func begin()
    func feed(_ buffer: AVAudioPCMBuffer)
    /// The utterance is over: finalise and call onFinal once.
    func end()
}

/// Apple's on-device speech recognition. Requires on-device mode: nothing goes to a server.
final class AppleSpeechEngine: SpeechEngine {
    var onFinal: ((String) -> Void)?
    var onPartial: ((String) -> Void)?
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var generation = 0

    static var supportsOnDevice: Bool { SFSpeechRecognizer(locale: Locale(identifier: "en-US"))?.supportsOnDeviceRecognition == true }

    func begin() {
        guard let recognizer, recognizer.supportsOnDeviceRecognition else {
            DispatchQueue.main.async { self.onPartial?("[This Mac has no on-device model for the older recognizer. Turn on Dictation in System Settings › Keyboard, or switch Transcription back to Apple on-device speech.]") }
            return
        }
        generation += 1
        let mine = generation
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.taskHint = .dictation
        self.request = request
        var delivered = false
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let text = result.bestTranscription.formattedString
                DispatchQueue.main.async {
                    if result.isFinal {
                        if !delivered, !text.isEmpty { delivered = true; self.onFinal?(text) }
                    } else if mine == self.generation {
                        self.onPartial?(text)
                    }
                }
            } else if let error {
                DispatchQueue.main.async {
                    delivered = true
                    let code = (error as NSError).code
                    // 1110 is "no speech detected": normal for a cough or a click.
                    if code != 1110 { self.onPartial?("[Speech recognizer error: \(error.localizedDescription)]") }
                }
            }
        }
    }

    func feed(_ buffer: AVAudioPCMBuffer) { request?.append(buffer) }

    func end() {
        request?.endAudio()
        request = nil
        task = nil
    }
}

/// Apple's macOS 26 speech-to-text (SpeechAnalyzer). Always on the device; its model downloads
/// once through the system, and then nothing leaves the Mac.
final class AnalyzerEngine: SpeechEngine {
    var onFinal: ((String) -> Void)?
    var onPartial: ((String) -> Void)?
    nonisolated(unsafe) static var locale = Locale(identifier: "en-US")
    nonisolated(unsafe) static var format: AVAudioFormat?
    private var input: AsyncStream<AnalyzerInput>.Continuation?
    private var analyzer: SpeechAnalyzer?
    private var results: Task<Void, Never>?
    private var converter: AVAudioConverter?

    static func makeTranscriber() -> SpeechTranscriber {
        SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults], attributeOptions: [])
    }

    /// Makes sure the speech model is on this Mac (downloading it if needed) and picks the audio format.
    /// Returns a problem to show, or nil when ready.
    static func prepare(status: @escaping (String) -> Void) async -> String? {
        // Use the locale exactly as the speech system names it, or reservation silently misses.
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en-US")) else {
            return "Apple's on-device speech doesn't support English on this Mac."
        }
        locale = supported
        let transcriber = makeTranscriber()
        do {
            let reserved = await AssetInventory.reservedLocales
            if !reserved.contains(where: { $0.identifier(.bcp47) == supported.identifier(.bcp47) }) {
                let ok = try await AssetInventory.reserve(locale: supported)
                NSLog("Second Chair: reserve \(supported.identifier(.bcp47)) -> \(ok)")
                if !ok { return "macOS wouldn't reserve the English speech model for Second Chair." }
            }
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                status("Downloading Apple's on-device speech model (one time)…")
                try await request.downloadAndInstall()
            }
            format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
            return nil
        } catch {
            return "Apple's on-device speech model isn't available: \(error.localizedDescription)"
        }
    }

    func begin() {
        let transcriber = Self.makeTranscriber()
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        self.analyzer = analyzer
        input = continuation
        let onPartial = self.onPartial, onFinal = self.onFinal
        results = Task {
            var finals: [String] = []
            do {
                try await analyzer.start(inputSequence: stream)
                for try await result in transcriber.results {
                    let text = String(result.text.characters).trimmingCharacters(in: .whitespaces)
                    if result.isFinal {
                        if !text.isEmpty { finals.append(text) }
                        let sofar = finals.joined(separator: " ")
                        DispatchQueue.main.async { onPartial?(sofar) }
                    } else {
                        let live = (finals + [text]).joined(separator: " ")
                        DispatchQueue.main.async { onPartial?(live) }
                    }
                }
            } catch {
                NSLog("Second Chair: transcription error \(error)")
            }
            let all = finals.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            if !all.isEmpty { DispatchQueue.main.async { onFinal?(all) } }
        }
    }

    func feed(_ buffer: AVAudioPCMBuffer) {
        guard let input else { return }
        if let target = Self.format, target != buffer.format {
            if converter == nil || converter?.inputFormat != buffer.format { converter = AVAudioConverter(from: buffer.format, to: target) }
            guard let converter else { return }
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * target.sampleRate / buffer.format.sampleRate) + 64
            guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
            var fed = false
            var error: NSError?
            converter.convert(to: out, error: &error) { _, status in
                if fed { status.pointee = .noDataNow; return nil }
                fed = true
                status.pointee = .haveData
                return buffer
            }
            if out.frameLength > 0 { input.yield(AnalyzerInput(buffer: out)) }
        } else {
            input.yield(AnalyzerInput(buffer: buffer))
        }
    }

    func end() {
        input?.finish()
        input = nil
        let analyzer = self.analyzer
        self.analyzer = nil
        Task { try? await analyzer?.finalizeAndFinishThroughEndOfInput() }
    }
}

/// whisper.cpp's server running on this Mac (`whisper-server -m model.bin --port 8178`).
/// Each utterance is posted as a WAV to the loopback address only.
final class WhisperServerEngine: SpeechEngine {
    var onFinal: ((String) -> Void)?
    var onPartial: ((String) -> Void)?
    static var port: Int { let p = UserDefaults.standard.integer(forKey: "whisperPort"); return p == 0 ? 8178 : p }
    private var samples: [Float] = []
    private var converter: AVAudioConverter?
    private let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!

    static func isRunning() async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(port)/") else { return false }
        return (try? await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 1))) != nil
    }

    func begin() { samples.removeAll(keepingCapacity: true) }

    func feed(_ buffer: AVAudioPCMBuffer) {
        if converter == nil || converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: target)
        }
        guard let converter else { return }
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * 16_000 / buffer.format.sampleRate) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
        var fed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        if let data = out.floatChannelData { samples.append(contentsOf: UnsafeBufferPointer(start: data[0], count: Int(out.frameLength))) }
    }

    func end() {
        let audio = samples
        samples.removeAll()
        guard audio.count > 16_000 / 4 else { return }
        Task {
            let text = await Self.transcribe(audio)
            await MainActor.run { if !text.isEmpty { self.onFinal?(text) } }
        }
    }

    static func transcribe(_ audio: [Float]) async -> String {
        guard let url = URL(string: "http://127.0.0.1:\(port)/inference") else { return "" }
        let boundary = "SecondChair\(UUID().uuidString)"
        var body = Data()
        func add(_ s: String) { body.append(s.data(using: .utf8)!) }
        add("--\(boundary)\r\nContent-Disposition: form-data; name=\"response_format\"\r\n\r\njson\r\n")
        add("--\(boundary)\r\nContent-Disposition: form-data; name=\"temperature\"\r\n\r\n0\r\n")
        add("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"u.wav\"\r\nContent-Type: audio/wav\r\n\r\n")
        body.append(wav(audio))
        add("\r\n--\(boundary)--\r\n")
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        guard let result = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: result.0) as? [String: Any] else { return "" }
        return ((json["text"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func wav(_ samples: [Float]) -> Data {
        var d = Data()
        func u32(_ v: UInt32) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: UInt16) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 2)) }
        let bytes = UInt32(samples.count * 2)
        d.append("RIFF".data(using: .ascii)!); u32(36 + bytes); d.append("WAVEfmt ".data(using: .ascii)!)
        u32(16); u16(1); u16(1); u32(16_000); u32(32_000); u16(2); u16(16)
        d.append("data".data(using: .ascii)!); u32(bytes)
        for s in samples { u16(UInt16(bitPattern: Int16(max(-1, min(1, s)) * 32_767))) }
        return d
    }
}

/// One labelled channel: audio in, utterances out, split at pauses.
final class ChannelListener {
    let channel: Channel
    var onUtterance: ((Utterance) -> Void)?
    var onPartial: ((Channel, String) -> Void)?
    /// Input loudness 0...1, about ten times a second, so you can see it hears you.
    var onLevel: ((Channel, Float) -> Void)?
    private let engine: SpeechEngine
    private let vad = EnergyVAD()
    private var open = false
    private var heardSpeech = false
    private var lastSpeech = Date()
    private var openedAt = Date()
    /// Continuous talk is cut into lines this long, so questions inside a monologue still get caught.
    var maxUtterance: TimeInterval = 12
    private var lastLevel = Date.distantPast
    /// The last moment of audio before speech is detected, so the first word isn't clipped.
    private var preroll: [AVAudioPCMBuffer] = []
    private let queue = DispatchQueue(label: "secondchair.listener")

    init(channel: Channel, engine: SpeechEngine) {
        self.channel = channel
        self.engine = engine
        engine.onFinal = { [weak self] text in
            guard let self else { return }
            self.onUtterance?(Utterance(channel: self.channel, text: text))
        }
        engine.onPartial = { [weak self] text in
            guard let self else { return }
            self.onPartial?(self.channel, text)
        }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        queue.async { [self] in
            let speech = vad.isSpeech(buffer)
            if Date().timeIntervalSince(lastLevel) > 0.1 {
                lastLevel = Date()
                let level = min(1, vad.lastRMS * 12)
                let ch = channel
                DispatchQueue.main.async { self.onLevel?(ch, level) }
            }
            if speech {
                if !open {
                    engine.begin()
                    open = true
                    openedAt = Date()
                    heardSpeech = false
                    for b in preroll { engine.feed(b) }
                    preroll.removeAll()
                }
                heardSpeech = true
                lastSpeech = Date()
            }
            guard open else {
                preroll.append(buffer)
                if preroll.count > 6 { preroll.removeFirst() }
                return
            }
            engine.feed(buffer)
            if heardSpeech, !speech, Date().timeIntervalSince(lastSpeech) > vad.pause { close() }
            // No pause for a long time: end the line at the next quieter moment, or force it.
            else if Date().timeIntervalSince(openedAt) > maxUtterance, !speech || Date().timeIntervalSince(openedAt) > maxUtterance + 4 { close() }
        }
    }

    /// Ends the current utterance now (end of dictation, end of session).
    func flush() { queue.async { [self] in if open { close() } } }

    private func close() {
        open = false
        engine.end()
    }
}

/// Channel 1: your microphone.
final class MicCapture {
    private let engine = AVAudioEngine()
    var onBuffer: ((AVAudioPCMBuffer) -> Void)?
    private(set) var running = false

    static func requestPermissions() async -> String? {
        if !(await AVCaptureDevice.requestAccess(for: .audio)) { return "Microphone access is off for Second Chair in System Settings › Privacy & Security." }
        let speech = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) } }
        if speech != .authorized, Settings.engine == .legacy { return "Speech Recognition access is off for Second Chair in System Settings › Privacy & Security." }
        return nil
    }

    func start() throws {
        guard !running else { return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            // The engine reuses this buffer after the callback returns; keep our own copy.
            if let copy = buffer.copy() as? AVAudioPCMBuffer { self?.onBuffer?(copy) }
        }
        engine.prepare()
        try engine.start()
        running = true
    }

    func stop() {
        guard running else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        running = false
    }
}

/// Channel 2: the whole system audio output, through ScreenCaptureKit. macOS has no per-app audio tap,
/// so this is the mix: the call, and anything else playing on the Mac.
final class SystemAudioCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    var onBuffer: ((AVAudioPCMBuffer) -> Void)?
    var onStop: ((String) -> Void)?
    private let queue = DispatchQueue(label: "secondchair.systemaudio")

    func start() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else { throw NSError(domain: "SecondChair", code: 1) }
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48_000
        config.channelCount = 1
        // Video is required by the API; keep it to a postage stamp once a second and ignore it.
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() {
        let s = stream
        stream = nil
        Task { try? await s?.stopCapture() }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid, let pcm = Self.pcm(sampleBuffer) else { return }
        onBuffer?(pcm)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { self.onStop?(error.localizedDescription) }
    }

    static func pcm(_ sample: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let desc = sample.formatDescription else { return nil }
        let format = AVAudioFormat(cmAudioFormatDescription: desc)
        let frames = AVAudioFrameCount(sample.numSamples)
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buffer.frameLength = frames
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(sample, at: 0, frameCount: Int32(frames),
                                                                   into: buffer.mutableAudioBufferList)
        return status == noErr ? buffer : nil
    }
}
