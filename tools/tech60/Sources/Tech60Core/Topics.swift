import Foundation

/// Something the reader follows. A story matches when its headline or opening text uses one of the keywords.
public struct Topic: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var keywords: [String]

    public init(id: String, name: String, keywords: [String]) {
        self.id = id
        self.name = name
        self.keywords = keywords
    }
}

public enum Topics {
    public static let builtIn: [Topic] = [
        Topic(id: "agents", name: "AI agents", keywords: [
            "agent", "agents", "agentic", "computer use", "mcp", "model context protocol", "autonomous", "copilot", "assistant"]),
        Topic(id: "models", name: "Models and LLMs", keywords: [
            "llm", "llms", "language model", "language models", "gpt", "claude", "gemini", "llama", "mistral", "deepseek",
            "qwen", "open-weight", "open weights", "frontier model", "reasoning model", "foundation model", "context window",
            "coding model", "benchmark"]),
        Topic(id: "apple", name: "Apple", keywords: [
            "apple", "iphone", "ipad", "macos", "mac", "macbook", "ios", "vision pro", "wwdc", "xcode", "siri", "apple intelligence"]),
        Topic(id: "chips", name: "Chips and hardware", keywords: [
            "chip", "chips", "chipmaker", "gpu", "gpus", "nvidia", "amd", "intel", "tsmc", "semiconductor", "semiconductors",
            "processor", "npu", "qualcomm", "data center", "datacenter"]),
        Topic(id: "funding", name: "Funding and deals", keywords: [
            "raises", "raised", "funding", "series a", "series b", "series c", "seed round", "valuation", "acquires",
            "acquisition", "acquired", "ipo", "layoffs", "quarterly results", "earnings"]),
        Topic(id: "devtools", name: "Developer tools", keywords: [
            "github", "api", "sdk", "developer", "developers", "ide", "vs code", "compiler", "programming", "framework",
            "database", "text editor", "terminal"]),
        Topic(id: "security", name: "Security", keywords: [
            "security", "vulnerability", "vulnerabilities", "breach", "exploit", "cve", "ransomware", "hacked", "hackers",
            "zero-day", "malware", "phishing", "patch"]),
        Topic(id: "opensource", name: "Open source", keywords: [
            "open source", "open-source", "linux", "rust", "maintainer", "maintainers", "license"]),
        Topic(id: "policy", name: "Policy and law", keywords: [
            "regulation", "regulators", "antitrust", "ftc", "doj", "ai act", "lawsuit", "sued", "court", "copyright",
            "export controls", "congress", "senate"]),
    ]

    /// A topic the reader typed: "Robotics: robot, robots, humanoid".
    public static func custom(name: String, keywords: String) -> Topic? {
        let name = name.trimmingCharacters(in: .whitespaces)
        var words = keywords.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
        if words.isEmpty, !name.isEmpty { words = [name.lowercased()] }
        guard !name.isEmpty else { return nil }
        return Topic(id: "custom-" + UUID().uuidString.prefix(8), name: name, keywords: words)
    }

    /// The topics a story matches, judged on its headline and the start of its text.
    public static func matches(_ story: Story, in topics: [Topic]) -> [Topic] {
        guard !topics.isEmpty else { return [] }
        let text = " " + (story.title + " " + story.sourceText.prefix(400)).lowercased() + " "
        return topics.filter { topic in topic.keywords.contains { contains(text, word: $0) } }
    }

    /// Whole-word match, so "mac" doesn't match "machine" and "api" doesn't match "capital".
    static func contains(_ text: String, word: String) -> Bool {
        var searchRange = text.startIndex..<text.endIndex
        while let r = text.range(of: word, options: [], range: searchRange) {
            let before = r.lowerBound > text.startIndex ? text[text.index(before: r.lowerBound)] : " "
            let after = r.upperBound < text.endIndex ? text[r.upperBound] : " "
            if !before.isLetter, !before.isNumber, !after.isLetter, !after.isNumber { return true }
            searchRange = r.upperBound..<text.endIndex
        }
        return false
    }
}
