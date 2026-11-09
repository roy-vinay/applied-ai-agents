import Foundation

/// One passage from one of your documents. It always knows where it came from:
/// no chunk exists without a source the display can name.
public struct Chunk: Codable, Equatable, Hashable, Sendable {
    public var id: String
    /// Path of the file, as indexed.
    public var file: String
    /// Headings above the passage, outermost first ("Stories › Scaling the ops team").
    public var headings: [String]
    /// The passage, verbatim. For a prepared answer, the answer you wrote.
    public var text: String
    /// The folder this file was added under, so a whole prep pack can be pinned as primary.
    public var folder: String
    /// When you wrote this passage as the answer to a question, that question.
    public var question: String?

    public init(id: String, file: String, headings: [String], text: String, folder: String, question: String? = nil) {
        self.id = id
        self.file = file
        self.headings = headings
        self.text = text
        self.folder = folder
        self.question = question
    }

    public var fileName: String { (file as NSString).lastPathComponent }
    public var headingPath: String { headings.joined(separator: " › ") }
    /// "story-bank.md › Stories › Scaling ops"
    public var sourceLine: String { headings.isEmpty ? fileName : "\(fileName) › \(headingPath)" }
}

/// Splits a document into passages small enough to read at a glance, by heading and paragraph.
/// Questions you've written answers to become prepared answers, kept whole:
///   ## Why are you looking for a new job?      (a heading that ends in a question mark)
///   Q: What's your management style?  A: ...   (Q: and A: lines)
///   **How do you handle conflict?**            (a question on its own line, answer below)
public enum Chunker {
    /// Passages are merged up to about this many characters, and split above `hardLimit`.
    public static var target = 600
    public static var hardLimit = 900

    public static func chunk(text: String, file: String, folder: String, markdown: Bool) -> [Chunk] {
        var chunks: [Chunk] = []
        var headings: [String] = []
        var levels: [Int] = []
        var buffer = ""
        /// The question the buffered text answers, if it's a prepared answer.
        var question: String?

        func flush() {
            let body = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            buffer = ""
            defer { question = nil }
            guard !body.isEmpty else { return }
            // A prepared answer stays whole, so it can be shown exactly as you wrote it.
            let pieces = question == nil ? split(body) : [body]
            for piece in pieces {
                chunks.append(Chunk(id: "\(file)#\(chunks.count)", file: file, headings: headings,
                                    text: piece, folder: folder, question: question))
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
            var p = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            paragraph = ""
            guard !p.isEmpty else { return }
            // "Q: ...\nA: ..." in one paragraph, or a question line on its own.
            if let (q, rest) = questionLead(p) {
                flush()
                // A new question ends the previous question heading's section.
                if let last = headings.last, isQuestion(last) { headings.removeLast(); levels.removeLast() }
                question = q
                p = rest
                guard !p.isEmpty else { return }
            } else if question == nil, !buffer.isEmpty, buffer.count + p.count + 2 > target {
                flush()
            }
            buffer += buffer.isEmpty ? p : "\n\n" + p
        }

        for line in lines {
            if markdown, let (level, title) = heading(line) {
                endParagraph()
                flush()
                while let last = levels.last, last >= level { levels.removeLast(); headings.removeLast() }
                levels.append(level)
                headings.append(title)
                if isQuestion(title) { question = clean(title) }
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

    /// If a paragraph opens with a question you've answered, the question and the answer text after it.
    static func questionLead(_ p: String) -> (String, String)? {
        var lines = p.components(separatedBy: "\n")
        let first = lines.removeFirst().trimmingCharacters(in: .whitespaces)
        let lower = first.lowercased()
        var q: String?
        for prefix in ["q:", "**q:**", "q.", "question:", "**question:**"] where lower.hasPrefix(prefix) {
            q = clean(String(first.dropFirst(prefix.count)))
        }
        // A bare question line counts, but not a bulleted list of questions (questions to ask them).
        func bullet(_ s: String) -> Bool {
            let t = s.trimmingCharacters(in: .whitespaces)
            return t.hasPrefix("- ") || t.hasPrefix("* ") || t.hasPrefix("• ")
        }
        let bulletList = bullet(first) && (lines.isEmpty || lines.allSatisfy(bullet))
        let restAreQuestions = !lines.isEmpty && lines.allSatisfy { isQuestion($0) }
        if q == nil, !bulletList, !restAreQuestions, isQuestion(first), first.count <= 220 { q = clean(first) }
        guard let q, !q.isEmpty else { return nil }
        var rest = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["A:", "**A:**", "A.", "Answer:", "**Answer:**"] where rest.hasPrefix(prefix) {
            rest = String(rest.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        return (q, rest)
    }

    static func isQuestion(_ s: String) -> Bool {
        clean(s).hasSuffix("?") && Lexicon.words(s).count >= 3
    }

    /// Strips list markers, numbering and emphasis from a question.
    static func clean(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespaces)
        while let f = t.first, "-*•>#".contains(f) { t = String(t.dropFirst()).trimmingCharacters(in: .whitespaces) }
        if let dot = t.firstIndex(where: { $0 == "." || $0 == ")" }), t[..<dot].allSatisfy(\.isNumber), !t[..<dot].isEmpty {
            t = String(t[t.index(after: dot)...]).trimmingCharacters(in: .whitespaces)
        }
        return t.trimmingCharacters(in: CharacterSet(charactersIn: "*_ ")).trimmingCharacters(in: .whitespaces)
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
        for sentence in Lexicon.sentences(body) {
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
