import AppKit
import AVFoundation
import Speech
import SecondChairCore

/// Command-line modes, for CI and for running the gate from a terminal:
///   SecondChair --gate questions.json --corpus folder [--primary folder] [--report out.md]
///               [--embeddings none|apple|ollama] [--models none|local]
///   SecondChair --ask "question" --corpus folder [same options]
///   SecondChair --window-check     prints whether the overlay is excluded from screen capture
enum CLI {
    static func value(_ flag: String) -> String? {
        let a = CommandLine.arguments
        guard let i = a.firstIndex(of: flag), i + 1 < a.count else { return nil }
        return a[i + 1]
    }

    static func runIfRequested() -> Int32? {
        let a = CommandLine.arguments
        if a.contains("--window-check") {
            _ = NSApplication.shared
            let hidden = MainActor.assumeIsolated { Overlay(model: AppModel.shared).panel.sharingType == .none }
            print("overlay sharingType: \(hidden ? "none (excluded from capture)" : "VISIBLE TO CAPTURE")")
            return hidden ? 0 : 1
        }
        if let path = value("--transcribe") { return transcribe(path) }
        guard a.contains("--gate") || a.contains("--ask") else { return nil }
        guard let corpus = value("--corpus") else { print("--corpus <folder> is required"); return 2 }
        final class Box: @unchecked Sendable { var code: Int32 = 0 }
        let box = Box()
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            box.code = await run(corpus: corpus)
            done.signal()
        }
        done.wait()
        return box.code
    }

    /// Plays an audio file through the same listening pipeline a session uses (voice detection, then the
    /// configured speech engine) and prints each utterance. For CI and for checking a Mac's setup.
    static func transcribe(_ path: String) -> Int32 {
        final class Box: @unchecked Sendable { var lines: [String] = []; var problem: String? }
        let box = Box()
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            if Settings.engine == .analyzer, let p = await AnalyzerEngine.prepare(status: { print($0) }) {
                print("SpeechAnalyzer not ready: \(p)")
                guard AppleSpeechEngine.supportsOnDevice else { box.problem = p; done.signal(); return }
                print("Falling back to the older on-device recognizer")
                Settings.engine = .legacy
            }
            print("Engine: \(Settings.engine.title)")
            if Settings.engine == .legacy {
                let auth = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) } }
                print("Speech recognition permission: \(auth == .authorized ? "granted" : "NOT granted (\(auth.rawValue))"); on-device model: \(AppleSpeechEngine.supportsOnDevice ? "yes" : "no")")
            }
            guard let file = try? AVAudioFile(forReading: URL(fileURLWithPath: path)) else { box.problem = "can't read \(path)"; done.signal(); return }
            let listener = ChannelListener(channel: .them, engine: Settings.makeEngine())
            listener.onUtterance = { u in box.lines.append(u.text); print("heard: \(u.text)") }
            listener.onPartial = { _, t in print("partial: \(t)") }
            let format = file.processingFormat
            while file.framePosition < file.length {
                guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096), (try? file.read(into: buf)) != nil else { break }
                listener.append(buf)
                try? await Task.sleep(nanoseconds: UInt64(Double(buf.frameLength) / format.sampleRate * 1_000_000_000))
            }
            // A second of silence ends the utterance, as a pause would.
            if let silence = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(format.sampleRate / 10)) {
                silence.frameLength = silence.frameCapacity
                for _ in 0..<12 { listener.append(silence); try? await Task.sleep(nanoseconds: 100_000_000) }
            }
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            done.signal()
        }
        // Main-queue callbacks need the run loop turning while we wait.
        while done.wait(timeout: .now()) == .timedOut { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        if let p = box.problem { print("Problem: \(p)"); return 1 }
        print("Transcript: \(box.lines.joined(separator: " "))")
        return box.lines.isEmpty ? 1 : 0
    }

    static func run(corpus: String) async -> Int32 {
        let folders = corpus.split(separator: ",").map { URL(fileURLWithPath: String($0)).standardizedFileURL.path }
        let primary = value("--primary").map { URL(fileURLWithPath: $0).standardizedFileURL.path } ?? folders.first
        var embedder: Embedder?
        switch value("--embeddings") ?? "none" {
        case "apple": embedder = AppleEmbedder()
        case "ollama": embedder = OllamaEmbedder(model: Models.embeddingModel)
        default: embedder = nil
        }
        var fast: ModelClient?, quality: ModelClient?
        if value("--models") == "local" {
            let found = await Models.discover()
            fast = found.fast
            quality = found.quality
            print(found.summary)
        }
        let index = await DocumentReader.build(folders: folders, embedder: embedder)
        print("Indexed \(index.chunks.count) passages from \(folders.count) folder(s); embeddings: \(index.embedderName ?? "none"); skipped \(index.skipped.count)")
        let retriever = Retriever(index: index, primaryFolder: primary, embedder: embedder)
        let answerer = Answerer(fast: fast, quality: quality)

        if let q = value("--ask") {
            let hits = await retriever.retrieve(q)
            let card = await answerer.answer(q, hits: hits)
            print("[\(card.label.rawValue)] \(card.passages.first?.chunk.sourceLine ?? "")")
            for p in card.passages { print("> " + p.chunk.text.replacingOccurrences(of: "\n", with: "\n> ")) }
            print(card.answer ?? card.withheld ?? "")
            return 0
        }
        guard let path = value("--gate"), let data = FileManager.default.contents(atPath: path),
              let questions = try? JSONDecoder().decode([GateQuestion].self, from: data) else {
            print("Could not read gate questions"); return 2
        }
        let result = await Gate.run(questions, retriever: retriever, answerer: answerer)
        print(result.markdown)
        if let out = value("--report") { try? result.markdown.write(toFile: out, atomically: true, encoding: .utf8) }
        if !result.passed { print("Gate failed: " + result.failures.joined(separator: "; ")) }
        return result.passed ? 0 : 1
    }
}

if let code = CLI.runIfRequested() { exit(code) }

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    withExtendedLifetime(delegate) { app.run() }
}
