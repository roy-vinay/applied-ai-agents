import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Writes a short summary of an official announcement. The result is always checked by SummaryChecker.
public protocol Summarizer: Sendable {
    var name: String { get }
    func availability() async -> String?
    func summarize(title: String, text: String) async throws -> String
    /// Explains a research paper in four labeled parts (see PaperExplainer).
    func explain(title: String, text: String) async throws -> String
    /// Loads the model ahead of the first summary, so the first one isn't slow.
    func prewarm()
    /// Loads the model for paper explainers, when the reader opens Research.
    func prewarmExplainer()
}

public extension Summarizer {
    func prewarm() {}
    func prewarmExplainer() {}
    /// Rates headlines 1-5 (see EditorPrompt). The default rates nothing.
    func rate(headlines: [String]) async throws -> [Int?] { headlines.map { _ in nil } }
    /// Rates papers (see PaperRatingPrompt). The default rates nothing.
    func ratePapers(_ papers: [(title: String, abstract: String)]) async throws -> [PaperRatingPrompt.Rating?] {
        papers.map { _ in nil }
    }
    /// Summarizers without a paper prompt use their summary.
    func explain(title: String, text: String) async throws -> String { try await summarize(title: title, text: text) }
}

public enum SummaryPrompt {
    public static let instructions = """
    You summarize official technology announcements for a news card. Write one paragraph of at most \
    45 words in plain language. Use only facts stated in the text. Copy numbers, product names, company \
    names, and dates exactly as written. Do not add opinions, predictions, or anything the text doesn't say. \
    Do not start with "The text", "This post", or "The announcement".
    """

    public static func prompt(title: String, text: String) -> String {
        "Title: \(title)\n\nText:\n\(String(text.prefix(4_000)))"
    }
}

/// Used when no on-device model is available: stories keep showing headline and link.
public struct NoSummarizer: Summarizer {
    public let reason: String
    public init(reason: String) { self.reason = reason }
    public var name: String { "None" }
    public func availability() async -> String? { reason }
    public func summarize(title: String, text: String) async throws -> String { throw CancellationError() }
    public func explain(title: String, text: String) async throws -> String { throw CancellationError() }
}

#if canImport(FoundationModels)
/// Apple's on-device model (macOS 26 with Apple Intelligence). Nothing leaves the Mac.
@available(macOS 26.0, *)
public struct AppleSummarizer: Summarizer {
    public init() {}
    public var name: String { "Apple on-device model" }

    public func rate(headlines: [String]) async throws -> [Int?] {
        let session = LanguageModelSession(instructions: EditorPrompt.instructions)
        let response = try await session.respond(to: EditorPrompt.prompt(headlines))
        return EditorPrompt.parse(response.content, count: headlines.count)
    }

    public func prewarm() {
        guard case .available = SystemLanguageModel.default.availability else { return }
        LanguageModelSession(instructions: SummaryPrompt.instructions).prewarm()
    }

    public func prewarmExplainer() {
        guard case .available = SystemLanguageModel.default.availability else { return }
        LanguageModelSession(instructions: PaperExplainer.instructions).prewarm()
    }

    public func availability() async -> String? {
        switch SystemLanguageModel.default.availability {
        case .available: return nil
        case .unavailable(let why): return "Apple's on-device model isn't available (\(why))."
        }
    }

    public func summarize(title: String, text: String) async throws -> String {
        let session = LanguageModelSession(instructions: SummaryPrompt.instructions)
        let response = try await session.respond(to: SummaryPrompt.prompt(title: title, text: text))
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func ratePapers(_ papers: [(title: String, abstract: String)]) async throws -> [PaperRatingPrompt.Rating?] {
        let session = LanguageModelSession(instructions: PaperRatingPrompt.instructions)
        let response = try await session.respond(to: PaperRatingPrompt.prompt(papers))
        return PaperRatingPrompt.parse(response.content, count: papers.count)
    }

    public func explain(title: String, text: String) async throws -> String {
        let session = LanguageModelSession(instructions: PaperExplainer.instructions)
        let response = try await session.respond(to: PaperExplainer.prompt(title: title, text: text))
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
#endif

public enum Summarizers {
    /// The best summarizer this Mac can run.
    public static func onDevice() -> Summarizer {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) { return AppleSummarizer() }
        #endif
        return NoSummarizer(reason: "Summaries need macOS 26 with Apple Intelligence turned on.")
    }
}
