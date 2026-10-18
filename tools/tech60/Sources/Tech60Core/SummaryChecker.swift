import Foundation

/// Checks a summary against the source text with plain code, before it can be shown.
///
/// A summary passes only if it is short enough, every number and proper name in it appears in the
/// source, and every sentence is supported by a source sentence (enough shared content words, and no
/// negation the source doesn't have). One failure withholds the whole summary.
public enum SummaryChecker {
    public static let maxWords = 60
    public static let minimumSupport = 0.5

    public struct Result: Equatable, Sendable {
        public var passed: Bool
        public var reason: String?
        public var evidence: [SummaryEvidence]
    }

    public static func check(summary raw: String, source: String, maxWords: Int = maxWords,
                             minimumSupport: Double = minimumSupport) -> Result {
        let summary = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        func fail(_ why: String) -> Result { Result(passed: false, reason: why, evidence: []) }

        guard !summary.isEmpty else { return fail("The model returned nothing.") }
        let words = summary.split(whereSeparator: { $0.isWhitespace }).count
        guard words <= maxWords else { return fail("Too long: \(words) words (limit \(maxWords)).") }

        let sourceFlat = flatten(source)
        for number in numbers(in: summary) where !sourceFlat.contains(number) {
            return fail("The number \"\(number)\" isn't in the source.")
        }
        for name in properNames(in: summary) where !sourceFlat.contains(name.lowercased()) {
            return fail("The name \"\(name)\" isn't in the source.")
        }

        let sourceSentences = sentences(in: source)
        guard !sourceSentences.isEmpty else { return fail("The source has no text to check against.") }
        var evidence: [SummaryEvidence] = []
        for sentence in sentences(in: summary) {
            let words = contentWords(sentence)
            if words.isEmpty { continue }
            var best: (score: Double, text: String) = (0, "")
            for candidate in sourceSentences {
                let score = Double(words.intersection(contentWords(candidate)).count) / Double(words.count)
                if score > best.score { best = (score, candidate) }
            }
            guard best.score >= minimumSupport else {
                return fail("This sentence isn't supported by the source: \"\(sentence)\"")
            }
            if hasNegation(sentence) && !hasNegation(best.text) {
                return fail("This sentence adds a negation the source doesn't have: \"\(sentence)\"")
            }
            evidence.append(SummaryEvidence(sentence: sentence, support: best.text))
        }
        guard !evidence.isEmpty else { return fail("The summary had no checkable sentences.") }
        return Result(passed: true, reason: nil, evidence: evidence)
    }

    // MARK: - Pieces

    /// Lowercased, with thousands separators removed, so "1,200" matches "1200".
    static func flatten(_ s: String) -> String {
        s.lowercased().replacingOccurrences(of: "(?<=\\d),(?=\\d{3})", with: "", options: .regularExpression)
    }

    static func numbers(in s: String) -> [String] {
        let flat = flatten(s)
        let regex = try! NSRegularExpression(pattern: "\\d+(?:\\.\\d+)?")
        let ns = flat as NSString
        return regex.matches(in: flat, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
    }

    /// Capitalized words that aren't at the start of a sentence, plus acronyms anywhere.
    static func properNames(in s: String) -> [String] {
        var names: [String] = []
        for sentence in sentences(in: s) {
            let tokens = sentence.split(whereSeparator: { $0.isWhitespace }).map {
                $0.trimmingCharacters(in: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-.")).inverted)
            }
            for (i, token) in tokens.enumerated() where token.count > 1 {
                let core = token.trimmingCharacters(in: CharacterSet(charactersIn: "."))
                guard let first = core.unicodeScalars.first, CharacterSet.uppercaseLetters.contains(first) else { continue }
                let isAcronym = core.count >= 2 && core.unicodeScalars.filter { CharacterSet.uppercaseLetters.contains($0) }.count >= 2
                if (i > 0 || isAcronym) && !commonCapitalized.contains(core) { names.append(core) }
            }
        }
        return names
    }

    private static let commonCapitalized: Set<String> = ["I", "It", "The", "A", "An", "This", "That", "These", "Those", "It's",
                                                         "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    static func sentences(in s: String) -> [String] {
        s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .components(separatedBy: CharacterSet(charactersIn: "\n"))
            .flatMap { line -> [String] in
                line.replacingOccurrences(of: "(?<=[.!?])\\s+(?=[A-Z0-9\"\u{201C}])", with: "\u{1F}", options: .regularExpression)
                    .components(separatedBy: "\u{1F}")
            }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count > 3 }
    }

    private static let stopWords: Set<String> = [
        "the", "and", "for", "with", "that", "this", "from", "into", "their", "they", "them", "have", "has", "had",
        "will", "would", "can", "could", "are", "was", "were", "been", "being", "its", "it's", "our", "your", "you",
        "about", "more", "most", "also", "than", "then", "which", "what", "when", "where", "who", "how", "all",
        "new", "now", "use", "uses", "using", "able", "make", "makes", "just", "very", "over", "such", "these", "those",
    ]

    static func contentWords(_ s: String) -> Set<String> {
        let tokens = s.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
        return Set(tokens.filter { $0.count > 2 && !stopWords.contains($0) }.map(stem))
    }

    static func stem(_ w: String) -> String {
        for suffix in ["ing", "ed", "es", "s"] where w.count > suffix.count + 3 && w.hasSuffix(suffix) {
            return String(w.dropLast(suffix.count))
        }
        return w
    }

    private static let negations: Set<String> = ["not", "no", "never", "none", "without", "cannot", "isn", "aren", "doesn", "don", "won", "didn", "wasn"]

    static func hasNegation(_ s: String) -> Bool {
        let tokens = s.lowercased().components(separatedBy: CharacterSet.letters.inverted)
        return tokens.contains { negations.contains($0) }
    }
}
