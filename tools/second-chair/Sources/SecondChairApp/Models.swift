import Foundation
import FoundationModels
import NaturalLanguage
import SecondChairCore

/// The fast path: Apple Intelligence on the device. Its job is compressing a passage into speaking length.
struct AppleFastModel: ModelClient {
    var name: String { "Apple Intelligence" }

    static var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available: return nil
        case .unavailable(.deviceNotEligible): return "This Mac can't run Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled): return "Apple Intelligence is off in System Settings."
        case .unavailable(.modelNotReady): return "Apple Intelligence is still getting ready."
        case .unavailable: return "Apple Intelligence isn't available."
        }
    }

    func complete(system: String, prompt: String) async throws -> String {
        let session = LanguageModelSession(instructions: system)
        let options = GenerationOptions(sampling: .greedy, temperature: 0, maximumResponseTokens: 160)
        return try await session.respond(to: prompt, options: options).content
    }
}

/// Talks to Ollama on this Mac only. Any URL that isn't the loopback address is refused.
enum Ollama {
    static let base = URL(string: "http://127.0.0.1:11434")!

    struct LocalOnly: Error {}

    static func post(_ path: String, _ body: [String: Any], timeout: TimeInterval) async throws -> [String: Any] {
        let url = base.appendingPathComponent(path)
        guard url.host == "127.0.0.1" else { throw LocalOnly() }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw NSError(domain: "Ollama", code: (response as? HTTPURLResponse)?.statusCode ?? -1,
                          userInfo: [NSLocalizedDescriptionKey: String(data: data, encoding: .utf8) ?? ""])
        }
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    /// Names of the models Ollama has pulled, or nil when Ollama isn't running.
    static func installedModels() async -> [String]? {
        var request = URLRequest(url: base.appendingPathComponent("api/tags"), timeoutInterval: 1.5)
        request.httpMethod = "GET"
        guard let result = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: result.0) as? [String: Any],
              let models = json["models"] as? [[String: Any]] else { return nil }
        return models.compactMap { $0["name"] as? String }
    }

    static func has(_ model: String, in installed: [String]) -> Bool {
        installed.contains { $0 == model || $0 == model + ":latest" || $0.hasPrefix(model + ":") }
    }
}

/// The quality path: Qwen3 8B (or whichever model you set) through Ollama.
struct OllamaModel: ModelClient {
    var model: String
    var name: String { model }

    func complete(system: String, prompt: String) async throws -> String {
        let json = try await Ollama.post("api/chat", [
            "model": model,
            "stream": false,
            "think": false,
            "keep_alive": "30m",
            "options": ["temperature": 0, "num_predict": 200],
            "messages": [["role": "system", "content": system], ["role": "user", "content": prompt]],
        ], timeout: 20)
        return ((json["message"] as? [String: Any])?["content"] as? String) ?? ""
    }
}

/// EmbeddingGemma (or whichever embedding model you set) through Ollama.
struct OllamaEmbedder: Embedder {
    var model: String
    var name: String { "ollama:" + model }

    func embed(_ texts: [String]) async throws -> [[Float]] {
        let json = try await Ollama.post("api/embed", ["model": model, "input": texts], timeout: 60)
        guard let rows = json["embeddings"] as? [[Double]], rows.count == texts.count else {
            throw NSError(domain: "Ollama", code: -2, userInfo: [NSLocalizedDescriptionKey: "no embeddings returned"])
        }
        return rows.map { $0.map(Float.init) }
    }
}

/// Apple's built-in sentence embedding: always on the Mac, weaker than EmbeddingGemma, no setup.
struct AppleEmbedder: Embedder {
    var name: String { "apple:sentence" }

    func embed(_ texts: [String]) async throws -> [[Float]] {
        guard let model = NLEmbedding.sentenceEmbedding(for: .english) else {
            throw NSError(domain: "NLEmbedding", code: -1, userInfo: [NSLocalizedDescriptionKey: "no English sentence embedding"])
        }
        return texts.map { text in (model.vector(for: String(text.prefix(2000))) ?? []).map(Float.init) }
    }
}

/// Which models are configured and which are actually running right now.
enum Models {
    static var qualityModel: String { UserDefaults.standard.string(forKey: "qualityModel") ?? "qwen3:8b" }
    static var embeddingModel: String { UserDefaults.standard.string(forKey: "embeddingModel") ?? "embeddinggemma" }

    enum EmbeddingChoice: String, CaseIterable { case ollama, apple, none }
    static var embeddingChoice: EmbeddingChoice {
        get { EmbeddingChoice(rawValue: UserDefaults.standard.string(forKey: "embeddingChoice") ?? "") ?? .ollama }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "embeddingChoice") }
    }

    struct Available {
        var fast: ModelClient?
        var quality: ModelClient?
        var embedder: Embedder?
        var summary: String
    }

    static func discover() async -> Available {
        let installed = await Ollama.installedModels()
        let fast: ModelClient? = AppleFastModel.unavailableReason == nil ? AppleFastModel() : nil
        let quality: ModelClient? = installed.map { Ollama.has(qualityModel, in: $0) } == true ? OllamaModel(model: qualityModel) : nil
        var embedder: Embedder?
        switch embeddingChoice {
        case .ollama:
            embedder = installed.map { Ollama.has(embeddingModel, in: $0) } == true ? OllamaEmbedder(model: embeddingModel) : AppleEmbedder()
        case .apple: embedder = AppleEmbedder()
        case .none: embedder = nil
        }
        var parts: [String] = []
        parts.append(fast == nil ? "fast path off (\(AppleFastModel.unavailableReason ?? ""))" : "fast: Apple Intelligence")
        if installed == nil {
            parts.append("quality path off (Ollama not running)")
        } else {
            parts.append(quality == nil ? "quality path off (run: ollama pull \(qualityModel))" : "quality: \(qualityModel)")
        }
        parts.append("embeddings: \(embedder?.name ?? "off")")
        return Available(fast: fast, quality: quality, embedder: embedder, summary: parts.joined(separator: " · "))
    }
}
