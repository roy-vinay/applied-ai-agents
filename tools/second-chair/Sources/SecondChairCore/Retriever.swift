import Foundation

/// A passage found for a question, with why it was found.
public struct Hit: Sendable, Equatable {
    public enum Via: String, Sendable { case keyword, embedding }
    public var chunk: Chunk
    /// Share of the question's terms the passage contains (keyword hits), 0...1.
    public var coverage: Double
    /// Cosine similarity (embedding hits), 0...1.
    public var similarity: Double
    public var score: Double
    public var via: Via
    public var primary: Bool

    /// One strength number on a common scale, for labelling and sorting.
    public var strength: Double { via == .keyword ? coverage : similarity }
}

public struct RetrievalSettings: Sendable {
    /// Below this best keyword coverage, keyword search counts as thin and embeddings are tried.
    public var thinCoverage = 0.5
    /// Multiplier on scores of passages in the pinned prep pack.
    public var primaryBoost = 1.6
    /// Weight of terms carried over from the previous question in a follow-up.
    public var followUpWeight = 0.5
    public var maxHits = 4

    public init() {}
}

/// Keyword search first, embeddings only when keyword search is thin, the pinned prep pack first,
/// and the last exchange as context for short follow-ups.
public struct Retriever: Sendable {
    public var index: CorpusIndex
    public var primaryFolder: String?
    public var settings = RetrievalSettings()
    public var embedder: Embedder?

    public init(index: CorpusIndex, primaryFolder: String? = nil, embedder: Embedder? = nil) {
        self.index = index
        self.primaryFolder = primaryFolder
        self.embedder = embedder
    }

    static let followUpCues: Set<String> = ["that", "it", "this", "those", "these", "there", "then", "else",
                                            "more", "why", "how", "example", "again", "instead", "result"]

    /// Is this a follow-up that leans on the previous question ("why was that?", "what happened next")?
    public static func isFollowUp(_ question: String) -> Bool {
        let words = Lexicon.words(question.lowercased())
        return Lexicon.terms(question).count <= 3 || (words.count <= 8 && words.contains(where: followUpCues.contains))
    }

    public func weightedTerms(_ question: String, previous: [String]) -> [String: Double] {
        var weights: [String: Double] = [:]
        for t in Lexicon.terms(question) { weights[t] = 1 }
        if Self.isFollowUp(question), let last = previous.last {
            for t in Lexicon.terms(last) where weights[t] == nil { weights[t] = settings.followUpWeight }
        }
        return weights
    }

    public func retrieve(_ question: String, previous: [String] = []) async -> [Hit] {
        let weighted = weightedTerms(question, previous: previous)
        var hits: [Hit] = index.keywordSearch(weighted).prefix(settings.maxHits * 3).map { item in
            let (i, score, coverage) = item
            let chunk = index.chunks[i]
            let primary = chunk.folder == primaryFolder
            return Hit(chunk: chunk, coverage: coverage, similarity: 0,
                       score: score * (primary ? settings.primaryBoost : 1), via: .keyword, primary: primary)
        }
        hits.sort { $0.score > $1.score }

        let best = hits.map(\.coverage).max() ?? 0
        if best < settings.thinCoverage, let embedder, !index.vectors.isEmpty, index.embedderName == embedder.name {
            let query = (Self.isFollowUp(question) ? (previous.last ?? "") + " " : "") + question
            if let qv = try? await embedder.embed([query]).first {
                let q = Vector.normalized(qv)
                var semantic: [Hit] = index.chunks.compactMap { chunk in
                    guard let v = index.vectors[chunk.id] else { return nil }
                    let sim = Double(max(0, Vector.dot(q, v)))
                    let primary = chunk.folder == primaryFolder
                    return Hit(chunk: chunk, coverage: 0, similarity: sim,
                               score: sim * (primary ? settings.primaryBoost : 1), via: .embedding, primary: primary)
                }
                semantic.sort { $0.score > $1.score }
                // Keep keyword hits that are still decent, then fill with the best semantic ones.
                let kept = hits.filter { $0.coverage >= settings.thinCoverage * 0.6 }
                var seen = Set(kept.map(\.chunk.id))
                hits = kept
                for h in semantic where !seen.contains(h.chunk.id) {
                    hits.append(h)
                    seen.insert(h.chunk.id)
                    if hits.count >= settings.maxHits { break }
                }
                hits.sort { $0.strength * ($0.primary ? 1.15 : 1) > $1.strength * ($1.primary ? 1.15 : 1) }
            }
        }
        return Array(hits.prefix(settings.maxHits))
    }
}
