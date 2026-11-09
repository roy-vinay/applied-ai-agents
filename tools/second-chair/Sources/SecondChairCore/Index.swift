import Foundation

/// Turns passages into vectors. On the Mac this is a small local embedding model; tests use a fake.
public protocol Embedder: Sendable {
    var name: String { get }
    func embed(_ texts: [String]) async throws -> [[Float]]
}

/// Everything the app knows about your documents: passages, their terms, and (when an embedder
/// was available at build time) their vectors. Saved as one file in Application Support.
public struct CorpusIndex: Codable, Sendable {
    public var chunks: [Chunk] = []
    public var builtAt: Date = .distantPast
    /// Files that were found but could not be read as text (images, scanned PDFs), listed, never included.
    public var skipped: [String] = []
    /// Name of the embedder that made `vectors`, or nil when the index is keyword-only.
    public var embedderName: String?
    public var vectors: [String: [Float]] = [:]
    /// Vectors of the questions you've written answers to, keyed by chunk id.
    public var questionVectors: [String: [Float]] = [:]

    // Keyword index, rebuilt from chunks on load.
    var postings: [String: [Int: Int]] = [:]
    /// Words in a passage's headings: its own heading counts 1, headings above it 0.5.
    var headPostings: [String: [Int: Double]] = [:]
    var vocabulary: [String] = []
    var lengths: [Int] = []
    var averageLength: Double = 1

    enum CodingKeys: String, CodingKey { case chunks, builtAt, skipped, embedderName, vectors, questionVectors }

    public init(chunks: [Chunk] = [], builtAt: Date = Date(), skipped: [String] = []) {
        self.chunks = chunks
        self.builtAt = builtAt
        self.skipped = skipped
        buildKeywordIndex()
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        chunks = try c.decode([Chunk].self, forKey: .chunks)
        builtAt = try c.decode(Date.self, forKey: .builtAt)
        skipped = try c.decodeIfPresent([String].self, forKey: .skipped) ?? []
        embedderName = try c.decodeIfPresent(String.self, forKey: .embedderName)
        vectors = try c.decodeIfPresent([String: [Float]].self, forKey: .vectors) ?? [:]
        questionVectors = try c.decodeIfPresent([String: [Float]].self, forKey: .questionVectors) ?? [:]
        buildKeywordIndex()
    }

    public mutating func buildKeywordIndex() {
        postings = [:]
        headPostings = [:]
        lengths = []
        for (i, chunk) in chunks.enumerated() {
            // Headings and file names are part of what a passage is about. Pictures count by their description only.
            let body = chunk.text.replacingOccurrences(of: #"!\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
            let terms = Lexicon.terms(body + " " + chunk.headings.joined(separator: " ") + " " + (chunk.question ?? "") + " "
                                   + (chunk.fileName as NSString).deletingPathExtension.replacingOccurrences(of: "-", with: " "))
            lengths.append(terms.count)
            for t in terms { postings[t, default: [:]][i, default: 0] += 1 }
            for (depth, heading) in chunk.headings.enumerated() {
                let weight = depth == chunk.headings.count - 1 ? 1.0 : 0.5
                for t in Set(Lexicon.terms(heading)) where (headPostings[t]?[i] ?? 0) < weight { headPostings[t, default: [:]][i] = weight }
            }
        }
        vocabulary = Array(postings.keys)
        averageLength = lengths.isEmpty ? 1 : Double(lengths.reduce(0, +)) / Double(lengths.count)
    }

    /// How informative a word is: rare words high, words in every passage near zero.
    public func idf(_ term: String) -> Double {
        let n = Double(chunks.count)
        guard let p = postings[term] else { return log(1 + n) }
        return log(1 + (n - Double(p.count) + 0.5) / (Double(p.count) + 0.5))
    }

    /// The rest of a compound is a word in its own right ("engineer" in AgentEngineer, not "iation").
    func isWord(_ rest: String) -> Bool {
        rest.count >= 3 && (postings[rest] != nil || postings[Lexicon.stem(rest)] != nil)
    }

    /// A question word that isn't in your documents, or appears only once or twice, next to a much more common
    /// word one or two letters away, is a mishearing or a typo: use the common word ("synopsis" -> Synopsys).
    public func corrected(_ weighted: [String: Double]) -> [String: Double] {
        var out: [String: Double] = [:]
        for (t, w) in weighted {
            let count = postings[t]?.count ?? 0
            if t.count >= 5, !t.contains(where: \.isNumber), count <= 2 {
                var best: String?
                for v in vocabulary where v != t && abs(v.count - t.count) <= 2 {
                    guard let vc = postings[v]?.count, vc >= max(5, 5 * count),
                          Lexicon.editDistance(v, t, limit: t.count >= 7 ? 2 : 1) else { continue }
                    if best == nil || vc > (postings[best!]?.count ?? 0) { best = v }
                }
                if let best { out[best] = max(out[best] ?? 0, w); continue }
            }
            out[t] = max(out[t] ?? 0, w)
        }
        return out
    }

    /// Other words in your documents a question word should also find, each with its source and a lower weight:
    /// compounds that contain it ("pilot" -> autopilot, "agent" -> agentengineer, 0.6), the root of a longer
    /// question word ("expectation" -> expect, 0.6), and near spellings of a word not in your documents (0.8).
    func expansions(_ weighted: [String: Double]) -> [String: (source: String, weight: Double)] {
        var out: [String: (source: String, weight: Double)] = [:]
        func add(_ v: String, _ source: String, _ w: Double) { if (out[v]?.weight ?? 0) < w { out[v] = (source, w) } }
        for (t, w) in weighted where !t.contains(where: \.isNumber) {
            if t.count >= 5 {
                var found = 0
                for v in vocabulary where v.count >= t.count + 2 && weighted[v] == nil {
                    let compound = (v.hasPrefix(t) && isWord(String(v.dropFirst(t.count)))) || (v.hasSuffix(t) && v.count - t.count >= 2)
                    guard compound else { continue }
                    add(v, t, w * 0.6)
                    found += 1
                    if found >= 16 { break }
                }
            }
            if postings[t] == nil, t.count >= 7 {
                for v in vocabulary where v.count >= 5 && t.count >= v.count + 3 && t.hasPrefix(v) && weighted[v] == nil { add(v, t, w * 0.6) }
            }
            if postings[t] == nil, t.count >= 5 {
                for v in vocabulary where weighted[v] == nil && abs(v.count - t.count) <= 2
                    && Lexicon.editDistance(v, t, limit: t.count >= 7 ? 2 : 1) { add(v, t, w * 0.8) }
            }
        }
        return out
    }

    /// Adds vectors for every passage. Without this the index still works, keyword-only.
    public mutating func embed(with embedder: Embedder, batch: Int = 32) async throws {
        var out: [String: [Float]] = [:]
        var i = 0
        while i < chunks.count {
            let slice = Array(chunks[i..<min(i + batch, chunks.count)])
            let vs = try await embedder.embed(slice.map { $0.headingPath + "\n" + $0.text })
            for (chunk, v) in zip(slice, vs) { out[chunk.id] = Vector.normalized(v) }
            i += batch
        }
        vectors = out
        let asked = chunks.filter { $0.question != nil }
        var qv: [String: [Float]] = [:]
        if !asked.isEmpty {
            let vs = try await embedder.embed(asked.map { $0.question ?? "" })
            for (chunk, v) in zip(asked, vs) { qv[chunk.id] = Vector.normalized(v) }
        }
        questionVectors = qv
        embedderName = embedder.name
    }

    /// BM25 over weighted query terms. Returns (chunk index, score, share of query terms matched).
    /// BM25 over the question's words and their expansions, plus a bonus for words in the passage's headings.
    /// Returns (chunk index, score, coverage), coverage being the share of the question's own words found.
    func keywordSearch(_ input: [String: Double]) -> [(Int, Double, Double)] {
        let weighted = corrected(input)
        guard !weighted.isEmpty, !chunks.isEmpty else { return [] }
        let k1 = 1.2, b = 0.75
        let expanded = expansions(weighted)
        var all: [String: Double] = weighted
        for (v, e) in expanded { all[v] = e.weight }

        var scores: [Int: Double] = [:]
        for (term, weight) in all {
            guard let posting = postings[term] else { continue }
            let idf = self.idf(term)
            for (doc, tf) in posting {
                let f = Double(tf)
                let norm = f * (k1 + 1) / (f + k1 * (1 - b + b * Double(lengths[doc]) / averageLength))
                scores[doc, default: 0] += weight * idf * norm
            }
        }
        // A heading says what its section answers: its words count again.
        for (term, weight) in all {
            guard let heads = headPostings[term] else { continue }
            let idf = self.idf(term)
            for (doc, hw) in heads where scores[doc] != nil { scores[doc]! += weight * idf * hw }
        }

        // Coverage counts the question's own words (a word found only inside a longer one counts 0.6). Words carried
        // over from a previous question help ranking but never lower coverage; with no own words everything counts.
        // A question word found nowhere in your documents is usually paraphrase, so it counts half against coverage.
        let own = weighted.filter { $0.value >= 1 }
        let basis = own.isEmpty ? weighted : own
        var credit: [Int: [String: Double]] = [:]
        for (term, weight) in basis {
            for doc in (postings[term] ?? [:]).keys { credit[doc, default: [:]][term] = weight }
        }
        for (v, e) in expanded {
            guard let sw = basis[e.source] else { continue }
            for doc in (postings[v] ?? [:]).keys where (credit[doc]?[e.source] ?? 0) < 0.6 * sw {
                credit[doc, default: [:]][e.source] = 0.6 * sw
            }
        }
        let total = basis.reduce(0.0) { sum, kv in
            let present = postings[kv.key] != nil || expanded.values.contains { $0.source == kv.key }
            return sum + (present ? kv.value : kv.value * 0.5)
        }
        return scores.map { doc, score in
            (doc, score, min(1, (credit[doc]?.values.reduce(0, +) ?? 0) / max(total, 0.0001)))
        }.sorted { $0.1 > $1.1 }
    }
}

enum Vector {
    static func normalized(_ v: [Float]) -> [Float] {
        let n = sqrt(v.reduce(0) { $0 + $1 * $1 })
        return n > 0 ? v.map { $0 / n } : v
    }

    static func dot(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0 }
        var s: Float = 0
        for i in 0..<a.count { s += a[i] * b[i] }
        return s
    }
}
