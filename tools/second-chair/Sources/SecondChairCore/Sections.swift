import Foundation

/// A whole section of one of your documents, as it reads there: a title and everything under it.
public struct Section: Sendable, Identifiable, Equatable {
    /// File plus heading path (or the chunk id for a passage outside any heading).
    public var id: String
    public var file: String
    public var title: String
    /// Headings above the title, outermost first.
    public var parents: [String]
    /// The section's Markdown, sub-headings included.
    public var text: String
    /// When this is a prepared answer, the question you wrote.
    public var question: String?
    /// The heading path this section sits under, title included (empty for a passage outside any heading).
    public var path: [String] = []
    /// For a section that is a single passage (a Q:/A: answer, or text outside any heading), that passage.
    public var anchorChunk: String?

    /// Does this passage belong to the section?
    public func contains(_ chunk: Chunk) -> Bool {
        guard chunk.file == file else { return false }
        if let anchorChunk { return chunk.id == anchorChunk }
        return chunk.headings.starts(with: path)
    }

    public var fileName: String { (file as NSString).lastPathComponent }
    public var breadcrumb: String { ([fileName] + parents).joined(separator: " › ") }
}

/// A section that came up for a question, with the passages inside it that matched.
public struct SectionMatch: Sendable, Identifiable, Equatable {
    public var section: Section
    /// Texts of the passages that matched, to mark the answer in place.
    public var matched: [String]
    public var prepared: Bool
    public var primary: Bool
    public var id: String { section.id }
}

extension Chunk {
    /// Position in its file, from the id ("file#12").
    public var ordinal: Int { Int(id.split(separator: "#").last ?? "") ?? 0 }
}

extension CorpusIndex {
    /// The section under a heading path in a file: the heading and everything beneath it, in document order.
    public func section(file: String, path: [String], maxCharacters: Int = 8000) -> Section {
        let members = chunks.filter { $0.file == file && $0.headings.starts(with: path) }.sorted { $0.ordinal < $1.ordinal }
        var text = ""
        var lastHeadings = path
        for m in members {
            if m.headings != lastHeadings, m.headings.count > path.count {
                // Re-insert sub-headings so the section reads as it does in the document.
                for (i, h) in m.headings.enumerated() where i >= path.count && (i >= lastHeadings.count || lastHeadings[i] != h) {
                    text += (text.isEmpty ? "" : "\n\n") + String(repeating: "#", count: min(6, i - path.count + (path.isEmpty ? 1 : 3))) + " " + h
                }
            }
            lastHeadings = m.headings
            text += (text.isEmpty ? "" : "\n\n") + m.text
            if text.count > maxCharacters { text += "\n\n…"; break }
        }
        let q = members.first(where: { $0.headings == path })?.question
        return Section(id: file + "#" + path.joined(separator: "›"), file: file, title: path.last ?? "",
                       parents: Array(path.dropLast()), text: text, question: q, path: path)
    }

    /// The section a passage belongs to, at the heading level that best fits the question:
    /// the heading sharing the most words with it, or the passage's own heading when none do.
    /// A document's top title is never chosen when there's anything below it.
    public func section(containing chunk: Chunk, for question: String = "") -> Section {
        if let q = chunk.question, chunk.headings.last != q {
            return Section(id: chunk.id, file: chunk.file, title: q, parents: chunk.headings, text: chunk.text, question: q,
                           path: chunk.headings, anchorChunk: chunk.id)
        }
        let headings = chunk.headings
        guard !headings.isEmpty else {
            let first = Lexicon.sentences(chunk.text).first ?? chunk.fileName
            return Section(id: chunk.id, file: chunk.file, title: String(first.prefix(90)), parents: [], text: chunk.text,
                           anchorChunk: chunk.id)
        }
        var depth = headings.count
        let q = Set(Lexicon.terms(question))
        if !q.isEmpty {
            var best = 0
            for (i, h) in headings.enumerated() where !(i == 0 && headings.count > 1) {
                let overlap = q.intersection(Lexicon.terms(h)).count
                if overlap > 0, overlap >= best { best = overlap; depth = i + 1 }
            }
        }
        return section(file: chunk.file, path: Array(headings.prefix(depth)))
    }

    /// Search hits grouped into whole sections, best first, each section once.
    public func sections(for hits: [Hit], question: String = "") -> [SectionMatch] {
        var out: [SectionMatch] = []
        var position: [String: Int] = [:]
        for hit in hits {
            let s = section(containing: hit.chunk, for: question)
            if let i = position[s.id] {
                out[i].matched.append(hit.chunk.text)
            } else {
                position[s.id] = out.count
                out.append(SectionMatch(section: s, matched: [hit.chunk.text], prepared: hit.via == .prepared, primary: hit.primary))
            }
        }
        return out
    }

    /// Section titles and questions you wrote that resemble this question, for browsing nearby answers.
    /// Titles are scored first; only the ones kept are built into sections.
    public func similarSections(to question: String, excluding: Set<String> = [], limit: Int = 12) -> [SectionMatch] {
        let q = Set(Lexicon.terms(question))
        guard !q.isEmpty else { return [] }
        struct Candidate { var key: String; var score: Double; var prepared: Bool; var chunk: Chunk; var path: [String]? }
        var seen = Set<String>()
        var found: [Candidate] = []
        func consider(_ key: String, _ title: String, _ c: Candidate) {
            guard !excluding.contains(key), seen.insert(key).inserted else { return }
            let t = Set(Lexicon.terms(title))
            guard !t.isEmpty else { return }
            let overlap = Double(q.intersection(t).count) / Double(min(q.count, t.count))
            guard overlap > 0 else { return }
            var c = c
            c.score = overlap
            found.append(c)
        }
        for chunk in chunks {
            if let question = chunk.question, chunk.headings.last != question {
                consider(chunk.id, question, Candidate(key: chunk.id, score: 0, prepared: true, chunk: chunk, path: nil))
            }
            let h = chunk.headings
            guard !h.isEmpty else { continue }
            for depth in 1...h.count where !(depth == 1 && h.count > 1) {
                let path = Array(h.prefix(depth))
                consider(chunk.file + "#" + path.joined(separator: "›"), path.last!,
                         Candidate(key: "", score: 0, prepared: depth == h.count && chunk.question != nil, chunk: chunk, path: path))
            }
        }
        return found.sorted { $0.score > $1.score }.prefix(limit).map { c in
            let s = c.path.map { section(file: c.chunk.file, path: $0) } ?? section(containing: c.chunk)
            return SectionMatch(section: s, matched: [], prepared: c.prepared, primary: false)
        }
    }

    /// Sections whose heading (or prepared question) says what the question asks, like "Copilot adoption" for
    /// "How would you increase the adoption of a copilot?". Most of the heading's words must be in the question.
    public func titleMatches(_ question: String, limit: Int = 3) -> [SectionMatch] {
        let q = Set(Lexicon.terms(question))
        guard q.count >= 1 else { return [] }
        var best: [(SectionMatch, Double)] = []
        for m in similarSections(to: question, limit: 40) {
            let t = Set(Lexicon.terms(m.section.title))
            guard !t.isEmpty else { continue }
            let shared = Double(q.intersection(t).count)
            let ofTitle = shared / Double(t.count)
            guard shared >= min(2, Double(t.count)), ofTitle >= 0.66 else { continue }
            best.append((m, ofTitle + shared / 10))
        }
        return best.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
    }

    /// The whole document a section comes from, as Markdown blocks tagged with the passage they came from,
    /// in order, headings re-inserted.
    public func documentParts(file: String) -> [(headings: [String], chunk: Chunk?, text: String)] {
        var out: [(headings: [String], chunk: Chunk?, text: String)] = []
        var last: [String] = []
        for c in chunks.filter({ $0.file == file }).sorted(by: { $0.ordinal < $1.ordinal }) {
            if c.headings != last {
                // Headings from the first one that changed onward.
                var common = 0
                while common < min(last.count, c.headings.count), last[common] == c.headings[common] { common += 1 }
                for i in common..<c.headings.count {
                    out.append((Array(c.headings.prefix(i + 1)), nil, String(repeating: "#", count: min(6, i + 1)) + " " + c.headings[i]))
                }
                last = c.headings
            }
            out.append((c.headings, c, c.text))
        }
        return out
    }
}
