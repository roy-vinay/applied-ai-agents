import Foundation
import SecondChairCore

enum Settings {
    enum Engine: String, CaseIterable {
        case apple, whisper
        var title: String { self == .apple ? "Apple on-device speech" : "whisper.cpp server (local)" }
    }

    static var engine: Engine {
        get { Engine(rawValue: UserDefaults.standard.string(forKey: "engine") ?? "") ?? .apple }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "engine") }
    }

    static func makeEngine() -> SpeechEngine {
        engine == .whisper ? WhisperServerEngine() : AppleSpeechEngine()
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
