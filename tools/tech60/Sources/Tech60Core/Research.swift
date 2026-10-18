import Foundation

/// Papers from research feeds. They live in their own tab, and reach Top or Latest only once the news
/// picks them up: today that means a Hacker News post linking to the paper.
public enum Research {
    /// How often a research feed is fetched. arXiv publishes once a day.
    public static let refreshInterval: TimeInterval = 6 * 3600
    /// How long to wait after arXiv refuses or fails, and the gap between requests for paper pages.
    public static let retryAfterError: TimeInterval = 3600
    public static let requestSpacing: TimeInterval = 3.5
    /// Papers kept per fetch, and how long they stay.
    public static let itemsPerFetch = 300
    public static let retention: TimeInterval = 2 * 86_400
    /// Hacker News points that make a paper news.
    public static let newsPoints = 150

    /// A paper nobody in the news has picked up yet: shown in the Research tab only.
    public static func isPaperOnly(_ story: Story) -> Bool {
        story.isResearch == true && (story.points ?? 0) < newsPoints
    }

    /// arXiv's feed lists new papers, cross-lists from other fields, and replaced versions of old ones.
    /// Replacements aren't new, so they're skipped.
    public static func isReplacement(_ item: FeedItem) -> Bool {
        item.text.range(of: #"Announce Type:\s*replace"#, options: .regularExpression) != nil
    }

    /// The abstract alone, without arXiv's "arXiv:2410.01234v1 Announce Type: new Abstract:" prefix.
    public static func abstract(_ text: String) -> String {
        guard let r = text.range(of: #"^\s*arXiv:\S+\s+Announce Type:\s*\S+\s+Abstract:\s*"#, options: .regularExpression) else {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(text[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The canonical abstract page for an arXiv link, so a Hacker News post linking the PDF or another version
    /// matches the paper: arxiv.org/pdf/2410.01234v2.pdf becomes arxiv.org/abs/2410.01234.
    public static func canonicalArxiv(_ url: URL) -> String? {
        guard let host = url.host?.lowercased(), host == "arxiv.org" || host == "www.arxiv.org" || host == "export.arxiv.org" else {
            return nil
        }
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count >= 2, ["abs", "pdf", "html"].contains(parts[0]) else { return nil }
        var id = parts[1...].joined(separator: "/")
        if id.hasSuffix(".pdf") { id.removeLast(4) }
        if let r = id.range(of: #"v[0-9]+$"#, options: .regularExpression) { id.removeSubrange(r) }
        return "https://arxiv.org/abs/" + id
    }
}
