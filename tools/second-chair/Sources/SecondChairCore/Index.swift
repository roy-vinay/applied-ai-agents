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
        lengths = []
        for (i, chunk) in chunks.enumerated() {
            // Headings and file names are part of what a passage is about.
            let terms = Lexicon.terms(chunk.text + " " + chunk.headings.joined(separator: " ") + " " + (chunk.question ?? "") + " "
                                   + (chunk.fileName as NSString).deletingPathExtension.replacingOccurrences(of: "-", with: " "))
            lengths.append(terms.count)
            for t in terms { postings[t, default: [:]][i, default: 0] += 1 }
        }
        averageLength = lengths.isEmpty ? 1 : Double(lengths.reduce(0, +)) / Double(lengths.count)
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
    func keywordSearch(_ weighted: [String: Double]) -> [(Int, Double, Double)] {
        guard !weighted.isEmpty, !chunks.isEmpty else { return [] }
        let k1 = 1.2, b = 0.75
        let n = Double(chunks.count)
        var scores: [Int: Double] = [:]
        var matched: [Int: Double] = [:]
        for (term, weight) in weighted {
            guard let posting = postings[term] else { continue }
            let idf = log(1 + (n - Double(posting.count) + 0.5) / (Double(posting.count) + 0.5))
            for (doc, tf) in posting {
                let f = Double(tf)
                let norm = f * (k1 + 1) / (f + k1 * (1 - b + b * Double(lengths[doc]) / averageLength))
                scores[doc, default: 0] += weight * idf * norm
                matched[doc, default: 0] += weight
            }
        }
        // A question word that appears nowhere in your documents is usually paraphrase ("biggest", "wrong"),
        // so it counts half against coverage. Off-topic questions still score near zero: nothing matches.
        // Coverage counts only the question's own words; words carried over from a previous question
        // help ranking but never make a match look weaker. With no own words, everything counts.
        let own = weighted.filter { $0.value >= 1 }
        let basis = own.isEmpty ? weighted : own
        var ownMatched: [Int: Double] = [:]
        for (term, weight) in basis { for doc in (postings[term] ?? [:]).keys { ownMatched[doc, default: 0] += weight } }
        let total = basis.reduce(0.0) { $0 + (postings[$1.key] == nil ? $1.value * 0.5 : $1.value) }
        return scores.map { ($0.key, $0.value, min(1, (ownMatched[$0.key] ?? 0) / max(total, 0.0001))) }.sorted { $0.1 > $1.1 }
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
