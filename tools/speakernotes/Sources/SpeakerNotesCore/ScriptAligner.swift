import Foundation

/// One word of the script, as matched against speech.
public struct ScriptWord: Equatable {
    /// Lowercased, without punctuation.
    public let text: String
    /// Where it is in the text that was given.
    public let range: NSRange
    /// False for filler words ("the", "and"), which count for little on their own.
    public let isContent: Bool
}

/// Follows a speaker through a script: given the last few words heard, finds where in the text they are.
///
/// Speech recognition only supplies words; this decides where you are, cautiously:
/// - a few words ahead moves at once,
/// - further ahead needs a stronger match, confirmed by two readings in a row,
/// - going back needs a long, near-exact match (you're rereading), also confirmed twice,
/// - filler words alone never move it, and words that aren't in the script just lower the match.
public final class ScriptAligner {
    public let words: [ScriptWord]
    /// The last word you've said, or -1 before the first.
    public private(set) var position = -1
    private var pending: Int?

    static let filler: Set<String> = SlideMatcher.stopWords.union([
        "i", "so", "um", "uh", "like", "just", "then", "there", "they", "their", "them", "was", "were", "has",
        "have", "had", "will", "can", "do", "does", "did", "not", "but", "if", "all", "also", "more", "very",
        "into", "about", "which", "who", "he", "she", "his", "her", "us", "me", "my", "okay", "ok", "yeah", "right",
    ])

    public init(text: String) {
        words = Self.tokenize(text)
    }

    public static func normalize(_ word: String) -> String {
        word.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    public static func tokenize(_ text: String) -> [ScriptWord] {
        var out: [ScriptWord] = []
        let ns = text as NSString
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byWords) { sub, range, _, _ in
            guard let sub else { return }
            let n = normalize(sub)
            guard !n.isEmpty else { return }
            out.append(ScriptWord(text: n, range: range, isContent: !filler.contains(n)))
        }
        return out
    }

    /// Start over, for example on a new slide.
    public func reset(to position: Int = -1) {
        self.position = min(max(position, -1), words.count - 1)
        pending = nil
    }

    /// Feeds what the recognizer heard most recently (its latest words, oldest first).
    /// Returns the new position when it moves, nil when it stays.
    @discardableResult
    public func update(heard raw: [String]) -> Int? {
        let heard = Array(raw.flatMap { $0.split(separator: " ").map(String.init) }.map(Self.normalize)
            .filter { !$0.isEmpty }.suffix(8))
        guard heard.count >= 2, !words.isEmpty else { return nil }
        let lo = max(0, position - 25), hi = min(words.count - 1, position + 40)
        guard lo <= hi else { return nil }
        let last = heard[heard.count - 1], second = heard[heard.count - 2]

        var best: (end: Int, score: Double, content: Int, adjusted: Double)?
        for e in lo...hi {
            // The last word heard (or the one before it, if the last was misheard) anchors the match.
            guard SlideMatcher.sameWord(words[e].text, last) || SlideMatcher.sameWord(words[e].text, second) else { continue }
            let start = max(0, e - heard.count - 3)
            let (score, content) = Self.align(heard, Array(words[start...e]))
            let adjusted = score - 0.004 * Double(abs(e - (position + 1)))
            if best == nil || adjusted > best!.adjusted + 0.0001 {
                best = (e, score, content, adjusted)
            }
        }
        guard let b = best else { return nil }
        let delta = b.end - position
        guard delta != 0 else { pending = nil; return nil }

        let accept: Bool, confirm: Bool
        if delta < 0 {
            accept = b.score >= 0.85 && b.content >= 3
            confirm = true
        } else if delta <= 8 {
            accept = b.score >= 0.5 && b.content >= 1
            confirm = false
        } else {
            accept = b.score >= 0.7 && b.content >= 2
            confirm = true
        }
        guard accept else { return nil }
        if confirm {
            if let p = pending, abs(p - b.end) <= 3 {
                pending = nil
            } else {
                pending = b.end
                return nil
            }
        }
        position = b.end
        return position
    }

    /// How well the heard words line up with a stretch of the script, in order, allowing words
    /// to be skipped on either side. Filler words count for less. Also returns how many content words matched.
    static func align(_ heard: [String], _ script: [ScriptWord]) -> (score: Double, content: Int) {
        let n = heard.count, m = script.count
        var value = Array(repeating: Array(repeating: 0.0, count: m + 1), count: n + 1)
        var content = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in 1...n {
            for j in 1...m {
                if SlideMatcher.sameWord(heard[i - 1], script[j - 1].text) {
                    value[i][j] = value[i - 1][j - 1] + (script[j - 1].isContent ? 1 : 0.35)
                    content[i][j] = content[i - 1][j - 1] + (script[j - 1].isContent ? 1 : 0)
                } else if value[i - 1][j] >= value[i][j - 1] {
                    value[i][j] = value[i - 1][j]
                    content[i][j] = content[i - 1][j]
                } else {
                    value[i][j] = value[i][j - 1]
                    content[i][j] = content[i][j - 1]
                }
            }
        }
        let total = heard.reduce(0.0) { $0 + (filler.contains($1) ? 0.35 : 1) }
        return (total == 0 ? 0 : value[n][m] / total, content[n][m])
    }
}
