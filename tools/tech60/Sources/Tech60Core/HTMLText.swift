import Foundation

/// Turns feed HTML into plain text, and pulls the readable paragraphs out of an announcement page.
public enum HTMLText {
    private static let entities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
        "rsquo": "\u{2019}", "lsquo": "\u{2018}", "rdquo": "\u{201D}", "ldquo": "\u{201C}",
        "mdash": "\u{2014}", "ndash": "\u{2013}", "hellip": "\u{2026}", "trade": "\u{2122}",
        "reg": "\u{00AE}", "copy": "\u{00A9}", "eacute": "\u{00E9}",
    ]

    public static func decodeEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        let regex = try! NSRegularExpression(pattern: "&(#x[0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);")
        let ns = s as NSString
        var out = ""
        var last = 0
        for m in regex.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let name = ns.substring(with: m.range(at: 1))
            var replacement: String?
            if name.hasPrefix("#x"), let v = UInt32(name.dropFirst(2), radix: 16), let u = Unicode.Scalar(v) {
                replacement = String(Character(u))
            } else if name.hasPrefix("#"), let v = UInt32(name.dropFirst()), let u = Unicode.Scalar(v) {
                replacement = String(Character(u))
            } else {
                replacement = entities[name.lowercased()]
            }
            out += replacement ?? ns.substring(with: m.range)
            last = m.range.location + m.range.length
        }
        out += ns.substring(from: last)
        return out
    }

    /// Plain text from an HTML fragment: no scripts, no tags, entities decoded, whitespace collapsed.
    public static func plain(_ html: String) -> String {
        var s = html
        s = s.replacingOccurrences(of: "(?is)<(script|style)[^>]*>.*?</\\1>", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "(?i)<br\\s*/?>|</(p|li|h[1-6]|div|tr)>", with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        s = decodeEntities(s)
        // WordPress feeds end with "The post ... appeared first on ...".
        s = s.replacingOccurrences(of: "(?s)The post .{0,300}? appeared first on .{0,120}?\\.?\\s*$", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "[ \\t\\u00A0]+", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: " *\\n[ \\n]*", with: "\n", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The readable paragraphs of an announcement page, or nil when there aren't enough.
    public static func articleText(fromHTML data: Data, minimum: Int = 300) -> String? {
        #if os(macOS)
        guard let doc = try? XMLDocument(data: data, options: [.documentTidyHTML]) else { return nil }
        func paragraphs(_ xpath: String) -> [String] {
            ((try? doc.nodes(forXPath: xpath)) ?? [])
                .compactMap { $0.stringValue?.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression) }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.count > 40 }
        }
        var paras = paragraphs("//article//p | //main//p")
        if paras.joined().count < 300 { paras = paragraphs("//p") }
        if paras.joined().count < 300 {
            // Pages that render with scripts (many Show HN projects) have few paragraphs; fall back to
            // the description the page gives for link previews, plus its headings and list items.
            let meta = ((try? doc.nodes(forXPath: "//meta[@name='description' or @property='og:description' or @name='twitter:description']/@content")) ?? [])
                .compactMap { $0.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let headings = ((try? doc.nodes(forXPath: "//h1 | //h2 | //h3 | //li")) ?? [])
                .compactMap { $0.stringValue?.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression) }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.count > 25 }
            var seen = Set<String>()
            paras = (meta + paras + headings).filter { seen.insert($0).inserted }
        }
        let text = paras.joined(separator: "\n")
        return text.count >= minimum ? String(text.prefix(12_000)) : nil
        #else
        return nil
        #endif
    }

    /// An https URL, or nil. Pictures are only loaded over https.
    public static func httpsURL(_ raw: String) -> URL? {
        let s = decodeEntities(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        guard let url = URL(string: s), url.scheme?.lowercased() == "https", url.host != nil else { return nil }
        return url
    }

    /// The first <img src> in a piece of feed HTML.
    public static func firstImage(inHTML html: String) -> URL? {
        guard let r = html.range(of: "<img[^>]+src=[\"']([^\"']+)[\"']", options: [.regularExpression, .caseInsensitive]) else { return nil }
        let tag = String(html[r])
        guard let q = tag.range(of: "src=[\"']", options: [.regularExpression, .caseInsensitive]) else { return nil }
        let rest = tag[q.upperBound...]
        return httpsURL(String(rest.prefix { $0 != "\"" && $0 != "'" }))
    }

    /// The picture a page gives for link previews (og:image or twitter:image).
    public static func previewImage(inHTML html: String) -> URL? {
        let head = String(html.prefix(200_000))
        let pattern = "<meta[^>]+(?:property|name)=[\"'](?:og:image(?::secure_url)?|twitter:image)[\"'][^>]*>"
        var search = head.startIndex..<head.endIndex
        while let r = head.range(of: pattern, options: [.regularExpression, .caseInsensitive], range: search) {
            let tag = String(head[r])
            if let c = tag.range(of: "content=[\"']", options: [.regularExpression, .caseInsensitive]) {
                let value = tag[c.upperBound...].prefix { $0 != "\"" && $0 != "'" }
                if let url = httpsURL(String(value)) { return url }
            }
            search = r.upperBound..<head.endIndex
        }
        // Some pages put content before property.
        let reversed = "<meta[^>]+content=[\"']([^\"']+)[\"'][^>]+(?:property|name)=[\"'](?:og:image|twitter:image)[\"']"
        if let r = head.range(of: reversed, options: [.regularExpression, .caseInsensitive]) {
            let tag = String(head[r])
            if let c = tag.range(of: "content=[\"']", options: [.regularExpression, .caseInsensitive]) {
                return httpsURL(String(tag[c.upperBound...].prefix { $0 != "\"" && $0 != "'" }))
            }
        }
        return nil
    }
}
