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
                    text += (text.isEmpty ? "" : "\n\n") + String(repeating: "#", count: min(6, i - path.count + 3)) + " " + h
                }
            }
            lastHeadings = m.headings
            text += (text.isEmpty ? "" : "\n\n") + m.text
            if text.count > maxCharacters { text += "\n\n…"; break }
        }
        let q = members.first(where: { $0.headings == path })?.question
        return Section(id: file + "#" + path.joined(separator: "›"), file: file, title: path.last ?? "",
                       parents: Array(path.dropLast()), text: text, question: q)
    }

    /// The section a passage belongs to, at the heading level that best fits the question:
    /// the heading sharing the most words with it, or the passage's own heading when none do.
    /// A document's top title is never chosen when there's anything below it.
    public func section(containing chunk: Chunk, for question: String = "") -> Section {
        if let q = chunk.question, chunk.headings.last != q {
            return Section(id: chunk.id, file: chunk.file, title: q, parents: chunk.headings, text: chunk.text, question: q)
        }
        let headings = chunk.headings
        guard !headings.isEmpty else {
            let first = Lexicon.sentences(chunk.text).first ?? chunk.fileName
            return Section(id: chunk.id, file: chunk.file, title: String(first.prefix(90)), parents: [], text: chunk.text)
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
    public func similarSections(to question: String, excluding: Set<String> = [], limit: Int = 12) -> [SectionMatch] {
        let q = Set(Lexicon.terms(question))
        guard !q.isEmpty else { return [] }
        var seen = Set<String>()
        var scored: [(SectionMatch, Double)] = []
        func consider(_ key: String, _ title: String, _ make: () -> Section, prepared: Bool) {
            guard !excluding.contains(key), seen.insert(key).inserted else { return }
            let t = Set(Lexicon.terms(title))
            guard !t.isEmpty else { return }
            let overlap = Double(q.intersection(t).count) / Double(min(q.count, t.count))
            guard overlap > 0 else { return }
            scored.append((SectionMatch(section: make(), matched: [], prepared: prepared, primary: false), overlap))
        }
        for chunk in chunks {
            if let question = chunk.question, chunk.headings.last != question {
                consider(chunk.id, question, { section(containing: chunk) }, prepared: true)
            }
            let h = chunk.headings
            for depth in 1...max(1, h.count) where !h.isEmpty && !(depth == 1 && h.count > 1) {
                let path = Array(h.prefix(depth))
                consider(chunk.file + "#" + path.joined(separator: "›"), path.last!, { section(file: chunk.file, path: path) },
                         prepared: depth == h.count && chunk.question != nil)
            }
        }
        return scored.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
    }
}
