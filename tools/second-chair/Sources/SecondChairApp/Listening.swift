import AVFoundation
import ScreenCaptureKit
import Speech
import SecondChairCore

/// A simple energy voice-activity detector with a moving noise floor. It decides when an
/// utterance has ended, which is when retrieval starts.
final class EnergyVAD {
    private var floor: Float = 0.002
    var pause: TimeInterval = 0.7

    func isSpeech(_ buffer: AVAudioPCMBuffer) -> Bool {
        guard let data = buffer.floatChannelData, buffer.frameLength > 0 else { return false }
        let n = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<n { sum += data[0][i] * data[0][i] }
        let rms = (sum / Float(n)).squareRoot()
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
        guard let recognizer, recognizer.supportsOnDeviceRecognition else { return }
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
            } else if error != nil {
                DispatchQueue.main.async { delivered = true }
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
    private let engine: SpeechEngine
    private let vad = EnergyVAD()
    private var open = false
    private var heardSpeech = false
    private var lastSpeech = Date()
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
            if speech {
                if !open { engine.begin(); open = true; heardSpeech = false }
                heardSpeech = true
                lastSpeech = Date()
            }
            guard open else { return }
            engine.feed(buffer)
            if heardSpeech, !speech, Date().timeIntervalSince(lastSpeech) > vad.pause { close() }
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
        if speech != .authorized, Settings.engine == .apple { return "Speech Recognition access is off for Second Chair in System Settings › Privacy & Security." }
        return nil
    }

    func start() throws {
        guard !running else { return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in self?.onBuffer?(buffer) }
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
