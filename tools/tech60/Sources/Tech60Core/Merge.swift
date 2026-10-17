import Foundation

public enum StoryMerge {
    /// Removes fragments and common tracking parameters, so the same article from two feeds matches.
    public static func normalized(_ url: URL) -> String {
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
            return Story(id: "\(source.id)|\(item.id)", sourceID: source.id, sourceName: source.name, title: item.title,
                         url: url, published: item.published, firstSeen: now,
                         sourceText: source.isPrimary ? item.text : "", isPrimary: source.isPrimary,
                         summary: source.isPrimary ? .pending : .none)
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
                updated.title = story.title
                updated.published = story.published ?? old.published
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
            .filter { now.timeIntervalSince($0.displayDate) < retention }
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
