import Foundation

public enum SourceKind: String, Codable, Sendable {
    case feed
    case hackerNews
}

/// A place stories come from. Official (primary) sources are eligible for summaries;
/// news publishers and Hacker News are shown as headline and link only.
public struct Source: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var kind: SourceKind
    public var url: URL?
    public var isPrimary: Bool
    public var isEnabled: Bool

    public init(id: String, name: String, kind: SourceKind = .feed, url: URL?, isPrimary: Bool, isEnabled: Bool = true) {
        self.id = id
        self.name = name
        self.kind = kind
        self.url = url
        self.isPrimary = isPrimary
        self.isEnabled = isEnabled
    }
}

/// One sentence of a summary and the source passage that supports it.
public struct SummaryEvidence: Codable, Hashable, Sendable {
    public var sentence: String
    public var support: String

    public init(sentence: String, support: String) {
        self.sentence = sentence
        self.support = support
    }
}

public enum SummaryState: Codable, Hashable, Sendable {
    /// Not summarized in the background (publisher or Hacker News); the reader can still ask for one.
    case none
    /// Eligible and waiting for the on-device model.
    case pending
    /// Passed every check; shown with its evidence.
    case checked(text: String, evidence: [SummaryEvidence])
    /// Failed a check or had too little source text; the row shows headline and link only.
    case withheld(reason: String)
}

public struct Story: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var sourceID: String
    public var sourceName: String
    public var title: String
    public var url: URL
    public var published: Date?
    public var firstSeen: Date
    /// Plain text the source itself provides (feed content, or the linked announcement page).
    public var sourceText: String
    public var isPrimary: Bool
    public var summary: SummaryState
    /// Hacker News points and comments: from the HN listing itself, or from an HN post linking to this story.
    public var points: Int?
    public var comments: Int?
    /// The story's picture, from the feed or the page's link preview.
    public var imageURL: URL?
    /// True once Tech60 has looked for a picture on the page, so it doesn't look again.
    public var imageChecked: Bool?

    public init(id: String, sourceID: String, sourceName: String, title: String, url: URL, published: Date?,
                firstSeen: Date, sourceText: String, isPrimary: Bool, summary: SummaryState = .none) {
        self.id = id
        self.sourceID = sourceID
        self.sourceName = sourceName
        self.title = title
        self.url = url
        self.published = published
        self.firstSeen = firstSeen
        self.sourceText = sourceText
        self.isPrimary = isPrimary
        self.summary = summary
    }

    /// Publication time when the feed gives a valid one, otherwise when Tech60 first saw it.
    public var displayDate: Date { published ?? firstSeen }
}

public struct SourceStatus: Codable, Hashable, Sendable {
    public var lastAttempt: Date?
    public var lastSuccess: Date?
    public var lastError: String?

    public init(lastAttempt: Date? = nil, lastSuccess: Date? = nil, lastError: String? = nil) {
        self.lastAttempt = lastAttempt
        self.lastSuccess = lastSuccess
        self.lastError = lastError
    }
}

public struct Snapshot: Codable, Hashable, Sendable {
    public var stories: [Story]
    public var lastViewed: Date?
    public var status: [String: SourceStatus]

    public init(stories: [Story] = [], lastViewed: Date? = nil, status: [String: SourceStatus] = [:]) {
        self.stories = stories
        self.lastViewed = lastViewed
        self.status = status
    }

    /// Stories that arrived after the person last looked at the card.
    public func isNew(_ story: Story) -> Bool {
        guard let lastViewed else { return false }
        return story.firstSeen > lastViewed
    }

    public var newCount: Int { stories.filter(isNew).count }
}

public enum Tech60Error: Error, LocalizedError, Equatable {
    case insecureURL
    case badStatus(Int)
    case tooLarge
    case notAFeed

    public var errorDescription: String? {
        switch self {
        case .insecureURL: return "Only https addresses are supported."
        case .badStatus(let code): return code == 429 ? "The source asked us to slow down (429)." : "The source answered with status \(code)."
        case .tooLarge: return "The source sent more data than Tech60 accepts."
        case .notAFeed: return "That address isn't an RSS or Atom feed."
        }
    }
}
