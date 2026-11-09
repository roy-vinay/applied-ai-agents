import Foundation
import SecondChairCore

enum Settings {
    enum Engine: String, CaseIterable {
        /// Raw value kept as "apple" so earlier settings carry over to the new default.
        case analyzer = "apple"
        case legacy = "appleLegacy"
        case whisper
        var title: String {
            switch self {
            case .analyzer: return "Apple on-device speech (macOS 26, recommended)"
            case .legacy: return "Apple speech recognizer (older)"
            case .whisper: return "whisper.cpp server (local)"
            }
        }
    }

    static var engine: Engine {
        get { Engine(rawValue: UserDefaults.standard.string(forKey: "engine") ?? "") ?? .analyzer }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "engine") }
    }

    static func makeEngine() -> SpeechEngine {
        switch engine {
        case .analyzer: return AnalyzerEngine()
        case .legacy: return AppleSpeechEngine()
        case .whisper: return WhisperServerEngine()
        }
    }
}

/// The latest accuracy check on your own question set. It informs; it doesn't lock anything.
enum GateStore {
    static var url: URL { Library.supportDirectory.appendingPathComponent("gate.json") }

    static var latest: GateResult? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return try? d.decode(GateResult.self, from: data)
    }

    static var passed: Bool { latest?.passed == true }

    /// Consecutive failed runs. After two, the PRD's fallback stands: Ask My Docs only, until a pass.
    static var consecutiveFailures: Int {
        get { UserDefaults.standard.integer(forKey: "gateFailures") }
        set { UserDefaults.standard.set(newValue, forKey: "gateFailures") }
    }

    static func save(_ result: GateResult) {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? e.encode(result) { try? data.write(to: url, options: .atomic) }
        try? result.markdown.write(to: Library.supportDirectory.appendingPathComponent("gate-report.md"), atomically: true, encoding: .utf8)
        consecutiveFailures = result.passed ? 0 : consecutiveFailures + 1
    }
}
