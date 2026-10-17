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
        if paras.joined().count < minimum { paras = paragraphs("//p") }
        let text = paras.joined(separator: "\n")
        return text.count >= minimum ? String(text.prefix(12_000)) : nil
        #else
        return nil
        #endif
    }
}
