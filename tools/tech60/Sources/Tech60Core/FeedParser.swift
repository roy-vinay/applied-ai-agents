import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

public struct FeedItem: Equatable, Sendable {
    public var id: String
    public var title: String
    public var link: URL?
    public var published: Date?
    /// Plain text from the feed: the longer of its summary and its full content.
    public var text: String
    /// Hacker News points and comment count, when the story came from there.
    public var points: Int?
    public var comments: Int?

    public init(id: String, title: String, link: URL?, published: Date?, text: String, points: Int? = nil, comments: Int? = nil) {
        self.id = id
        self.title = title
        self.link = link
        self.published = published
        self.text = text
        self.points = points
        self.comments = comments
    }
}

/// Parses RSS 2.0 and Atom 1.0. External entities are never resolved.
public enum FeedParser {
    public static func parse(_ data: Data, now: Date = Date()) throws -> [FeedItem] {
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        let delegate = Delegate(now: now)
        parser.delegate = delegate
        guard parser.parse() || !delegate.items.isEmpty else { throw Tech60Error.notAFeed }
        if !delegate.sawFeed { throw Tech60Error.notAFeed }
        return delegate.items
    }

    final class Delegate: NSObject, XMLParserDelegate {
        struct Partial { var id = "", title = "", link = "", published = "", updated = "", summary = "", content = "" }
        let now: Date
        var items: [FeedItem] = []
        var current: Partial?
        var buffer = ""
        var sawFeed = false
        var depthInItem = 0

        init(now: Date) { self.now = now }

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes: [String: String] = [:]) {
            let name = elementName.lowercased()
            if name == "rss" || name == "feed" || name == "rdf:rdf" { sawFeed = true }
            if name == "item" || name == "entry" {
                current = Partial()
                depthInItem = 0
            } else if current != nil {
                depthInItem += 1
                if name == "link", let href = attributes["href"] {
                    let rel = attributes["rel"] ?? "alternate"
                    if rel == "alternate", current?.link.isEmpty == true { current?.link = href }
                }
            }
            buffer = ""
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { buffer += string }

        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            buffer += String(decoding: CDATABlock, as: UTF8.self)
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            let name = elementName.lowercased()
            guard current != nil else { return }
            let text = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if name == "item" || name == "entry" {
                if let p = current { finish(p) }
                current = nil
                return
            }
            // Only direct children of the item, so a nested <source><title> doesn't win.
            if depthInItem == 1 {
                switch name {
                case "title": current?.title = text
                case "link": if !text.isEmpty, current?.link.isEmpty == true { current?.link = text }
                case "guid", "id": current?.id = text
                case "pubdate", "published", "dc:date", "issued": current?.published = text
                case "updated", "modified": current?.updated = text
                case "description", "summary": current?.summary = buffer
                case "content:encoded", "content": current?.content = buffer
                default: break
                }
            }
            depthInItem = max(0, depthInItem - 1)
            buffer = ""
        }

        private func finish(_ p: Partial) {
            let title = HTMLText.plain(p.title)
            guard !title.isEmpty else { return }
            let link = URL(string: p.link.trimmingCharacters(in: .whitespacesAndNewlines))
            let summary = HTMLText.plain(p.summary)
            let content = HTMLText.plain(p.content)
            let published = FeedDates.parse(p.published, now: now) ?? FeedDates.parse(p.updated, now: now)
            let id = p.id.isEmpty ? (link?.absoluteString ?? title) : p.id
            items.append(FeedItem(id: id, title: title, link: link, published: published,
                                  text: content.count > summary.count ? content : summary))
        }
    }
}

public enum FeedDates {
    private static let rfc822: [DateFormatter] = [
        "EEE, dd MMM yyyy HH:mm:ss Z", "EEE, dd MMM yyyy HH:mm:ss zzz", "EEE, d MMM yyyy HH:mm:ss Z",
        "EEE, d MMM yyyy HH:mm:ss zzz", "dd MMM yyyy HH:mm:ss Z", "EEE, dd MMM yyyy HH:mm Z", "EEE, dd MMM yyyy",
    ].map { format in
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = format
        return f
    }

    /// A feed date, or nil when it's missing, unreadable, or more than a day in the future.
    public static func parse(_ raw: String, now: Date = Date()) -> Date? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        var date: Date?
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        date = iso.date(from: s)
        if date == nil {
            iso.formatOptions = [.withInternetDateTime]
            date = iso.date(from: s)
        }
        if date == nil {
            for f in rfc822 { if let d = f.date(from: s) { date = d; break } }
        }
        guard let date, date.timeIntervalSince(now) < 86_400 else { return nil }
        return date
    }
}
