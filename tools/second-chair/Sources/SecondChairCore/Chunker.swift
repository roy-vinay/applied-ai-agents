import Foundation

/// One passage from one of your documents. It always knows where it came from:
/// no chunk exists without a source the display can name.
public struct Chunk: Codable, Equatable, Hashable, Sendable {
    public var id: String
    /// Path of the file, as indexed.
    public var file: String
    /// Headings above the passage, outermost first ("Stories › Scaling the ops team").
    public var headings: [String]
    /// The passage, verbatim.
    public var text: String
    /// The folder this file was added under, so a whole prep pack can be pinned as primary.
    public var folder: String

    public init(id: String, file: String, headings: [String], text: String, folder: String) {
        self.id = id
        self.file = file
        self.headings = headings
        self.text = text
        self.folder = folder
    }

    public var fileName: String { (file as NSString).lastPathComponent }
    public var headingPath: String { headings.joined(separator: " › ") }
    /// "story-bank.md › Stories › Scaling ops"
    public var sourceLine: String { headings.isEmpty ? fileName : "\(fileName) › \(headingPath)" }
}

/// Splits a document into passages small enough to read at a glance, by heading and paragraph.
public enum Chunker {
    /// Passages are merged up to about this many characters, and split above `hardLimit`.
    public static var target = 600
    public static var hardLimit = 900

    public static func chunk(text: String, file: String, folder: String, markdown: Bool) -> [Chunk] {
        var chunks: [Chunk] = []
        var headings: [String] = []
        var levels: [Int] = []
        var buffer = ""

        func flush() {
            let body = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            buffer = ""
            guard !body.isEmpty else { return }
            for piece in split(body) {
                let id = "\(file)#\(chunks.count)"
                chunks.append(Chunk(id: id, file: file, headings: headings, text: piece, folder: folder))
            }
        }

        var lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        // YAML front matter (Obsidian properties) is metadata, not prose.
        if markdown, lines.first?.trimmingCharacters(in: .whitespaces) == "---",
           let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) {
            lines.removeSubrange(0...end)
        }

        var paragraph = ""
        func endParagraph() {
            let p = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            paragraph = ""
            guard !p.isEmpty else { return }
            if !buffer.isEmpty, buffer.count + p.count + 2 > target { flush() }
            buffer += buffer.isEmpty ? p : "\n\n" + p
        }

        for line in lines {
            if markdown, let (level, title) = heading(line) {
                endParagraph()
                flush()
                while let last = levels.last, last >= level { levels.removeLast(); headings.removeLast() }
                levels.append(level)
                headings.append(title)
            } else if line.trimmingCharacters(in: .whitespaces).isEmpty {
                endParagraph()
            } else {
                paragraph += paragraph.isEmpty ? line : "\n" + line
            }
        }
        endParagraph()
        flush()
        return chunks
    }

    static func heading(_ line: String) -> (Int, String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("#") else { return nil }
        let level = trimmed.prefix(while: { $0 == "#" }).count
        guard level <= 6 else { return nil }
        let rest = trimmed.dropFirst(level)
        guard rest.first == " " else { return nil }
        let title = rest.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            .trimmingCharacters(in: .whitespaces)
        return title.isEmpty ? nil : (level, title)
    }

    /// Splits an over-long passage at sentence boundaries.
    static func split(_ body: String) -> [String] {
        guard body.count > hardLimit else { return [body] }
        var out: [String] = []
        var current = ""
        for sentence in Text.sentences(body) {
            if !current.isEmpty, current.count + sentence.count + 1 > target {
                out.append(current)
                current = ""
            }
            current += current.isEmpty ? sentence : " " + sentence
        }
        if !current.isEmpty { out.append(current) }
        return out
    }
}
