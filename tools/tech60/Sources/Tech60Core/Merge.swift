import Foundation

public enum StoryMerge {
    /// Removes fragments and common tracking parameters, so the same article from two feeds matches.
    public static func normalized(_ url: URL) -> String {
        if let paper = Research.canonicalArxiv(url) { return paper }
        guard var c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url.absoluteString }
        c.fragment = nil
        c.scheme = c.scheme?.lowercased()
        c.host = c.host?.lowercased()
        let tracking: Set<String> = ["fbclid", "gclid", "ref", "ref_src"]
        c.queryItems = c.queryItems?.filter { !$0.name.lowercased().hasPrefix("utm_") && !tracking.contains($0.name.lowercased()) }
        if c.queryItems?.isEmpty == true { c.queryItems = nil }
        var s = c.string ?? url.absoluteString
        if s.hasSuffix("/") { s.removeLast() }
        return s
    }

    public static func stories(from items: [FeedItem], source: Source, now: Date) -> [Story] {
        items.compactMap { item in
            guard let url = item.link else { return nil }
            if source.kind == .research {
                guard !Research.isReplacement(item) else { return nil }
                let page = Research.canonicalArxiv(url).flatMap(URL.init(string:)) ?? url
                var paper = Story(id: "\(source.id)|\(item.id)", sourceID: source.id, sourceName: source.name,
                                  title: item.title.split(whereSeparator: \.isWhitespace).joined(separator: " "), url: page, published: item.published, firstSeen: now, sourceText: Research.abstract(item.text),
                                  isPrimary: false)
                paper.isResearch = true
                let abstract = paper.sourceText
                paper.paperGroup = PaperSignals.keywordGroup(title: paper.title, abstract: abstract).rawValue
                paper.paperVenue = PaperSignals.venue(fromComment: item.comment)
                paper.paperHasCode = PaperSignals.hasCode(abstract + " " + item.comment)
                return paper
            }
            var story = Story(id: "\(source.id)|\(item.id)", sourceID: source.id, sourceName: source.name, title: item.title,
                              url: url, published: item.published, firstSeen: now,
                              sourceText: source.isPrimary || source.kind == .hackerNews ? item.text : "", isPrimary: source.isPrimary,
                              summary: source.isPrimary ? .pending : .none)
            story.points = item.points
            story.comments = item.comments
            story.imageURL = item.image
            return story
        }
    }

    /// Merges fresh stories into the stored ones: keeps first-seen times and checked summaries,
    /// drops duplicates by id or normalized URL, prunes old stories, newest first.
    public static func merge(existing: [Story], incoming: [Story], now: Date,
                             retention: TimeInterval = 7 * 86_400, limit: Int = 2_000) -> [Story] {
        var byID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var urlToID = Dictionary(existing.map { (normalized($0.url), $0.id) }, uniquingKeysWith: { a, _ in a })
        for var story in incoming {
            let key = normalized(story.url)
            if let old = byID[story.id] ?? urlToID[key].flatMap({ byID[$0] }) {
                var updated = old
                // An HN post linking to a story we already have: keep its points as a heat signal.
                if let points = story.points { updated.points = max(points, old.points ?? 0) }
                if let comments = story.comments { updated.comments = max(comments, old.comments ?? 0) }
                if updated.imageURL == nil { updated.imageURL = story.imageURL }
                // A paper arriving after a Hacker News post that links to it: the post gains the abstract.
                if story.isResearch == true, updated.sourceText.isEmpty { updated.sourceText = story.sourceText }
                if old.sourceID != story.sourceID {
                    byID[old.id] = updated
                    continue
                }
                updated.title = story.title
                updated.published = story.published ?? old.published
                if story.isResearch == true {
                    // Papers saved before signals existed pick them up on the next fetch.
                    updated.paperVenue = story.paperVenue ?? old.paperVenue
                    updated.paperHasCode = story.paperHasCode ?? old.paperHasCode
                    if old.paperGroup == nil { updated.paperGroup = story.paperGroup }
                }
                if story.isPrimary, story.sourceText != old.sourceText, story.sourceText.count > old.sourceText.count {
                    updated.sourceText = story.sourceText
                    updated.summary = .pending
                }
                byID[old.id] = updated
            } else {
                story.firstSeen = now
                byID[story.id] = story
                urlToID[key] = story.id
            }
        }
        return byID.values
            // Papers nobody has picked up stay two days from when Tech60 first saw them. (A paper's own date is
            // when it was submitted, often days before arXiv announces it.)
            .filter { $0.isResearch == true && $0.points == nil
                ? now.timeIntervalSince($0.firstSeen) < min(retention, Research.retention)
                : now.timeIntervalSince($0.displayDate) < retention }
            .sorted { $0.displayDate > $1.displayDate }
            .prefix(limit)
            .map { $0 }
    }
}

/// Saves the snapshot as JSON in Application Support.
public struct SnapshotFile: Sendable {
    public var url: URL

    public init(url: URL) { self.url = url }

    public static func standard() -> SnapshotFile {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return SnapshotFile(url: base.appendingPathComponent("Tech60/snapshot.json"))
    }

    public func load() -> Snapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Snapshot.self, from: data)
    }

    public func save(_ snapshot: Snapshot) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(snapshot).write(to: url, options: .atomic)
    }
}
