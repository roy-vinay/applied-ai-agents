import Foundation

/// Works out which notes slide goes with the slide on screen, either from a slide number that
/// Keynote or PowerPoint reports, or from the text read off the screen.
public enum SlideMatcher {

    // MARK: - By slide number

    /// The slide number a notes slide declares in its first heading: "## 7. Title", "Slide 7: Title" or "7) Title".
    public static func declaredNumber(of slide: Slide) -> Int? {
        guard let first = NotesParser.blocks(in: slide.text).first, case .heading(_, let title) = first else { return nil }
        return leadingNumber(title)
    }

    static func leadingNumber(_ title: String) -> Int? {
        var s = Substring(title.trimmingCharacters(in: .whitespaces))
        if s.lowercased().hasPrefix("slide ") { s = s.dropFirst(6) }
        let digits = s.prefix(while: { $0.isNumber })
        guard !digits.isEmpty, digits.count <= 3, let n = Int(digits) else { return nil }
        let rest = s.dropFirst(digits.count)
        guard let mark = rest.first, ".:)-".contains(mark) || mark == " " else { return nil }
        return n
    }

    /// The notes slide for a slide number reported by the presentation app (1 is the first slide).
    /// When the notes number their slides ("## 7. …"), those numbers win; otherwise slides line up in order.
    public static func index(forSlideNumber number: Int, in slides: [Slide]) -> Int? {
        guard number >= 1, !slides.isEmpty else { return nil }
        let declared = slides.map(declaredNumber(of:))
        if declared.contains(where: { $0 != nil }) {
            if let exact = declared.firstIndex(of: number) { return exact }
            // A slide without its own notes: stay on the closest earlier one.
            let earlier = declared.enumerated().compactMap { i, n in n.flatMap { $0 < number ? (i, $0) : nil } }
            return earlier.max(by: { $0.1 < $1.1 })?.0
        }
        return number <= slides.count ? number - 1 : nil
    }

    // MARK: - By what's on screen

    public struct Match: Equatable {
        public let index: Int
        /// 0 to 1: how well the screen matches this slide's title.
        public let score: Double
        /// How far ahead of the best slide with a different title. Low means ambiguous.
        public let margin: Double
    }

    static let stopWords: Set<String> = ["the", "a", "an", "and", "or", "of", "to", "in", "on", "for", "with", "is",
                                          "are", "it", "its", "at", "by", "from", "as", "be", "this", "that", "your",
                                          "our", "we", "you", "how", "what", "slide"]

    /// The words that identify a title, lowercased, without numbering, punctuation or filler words.
    public static func keyWords(_ text: String) -> [String] {
        var t = text
        if let n = leadingNumber(t) {
            // Drop "7." or "Slide 7:" from the front.
            if let r = t.range(of: "\(n)") { t = String(t[r.upperBound...]) }
        }
        let cleaned = t.lowercased().map { $0.isLetter || $0.isNumber ? $0 : " " }
        return String(cleaned).split(separator: " ").map(String.init)
            .filter { $0.count >= 2 && !stopWords.contains($0) }
    }

    /// The title a notes slide is known by: its first heading, or its first line.
    public static func title(of slide: Slide) -> String { slide.title }

    /// Two words count as the same if they're equal, or one letter apart when long enough
    /// (text recognition misreads a letter now and then: "Keepinq").
    static func sameWord(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        guard a.count >= 5, b.count >= 5, abs(a.count - b.count) <= 1 else { return false }
        return editDistance(Array(a), Array(b), limit: 1) <= 1
    }

    static func editDistance(_ a: [Character], _ b: [Character], limit: Int) -> Int {
        var prev = Array(0...b.count)
        for i in 1...max(a.count, 1) where !a.isEmpty {
            var cur = [i] + Array(repeating: 0, count: b.count)
            for j in 1...max(b.count, 1) where !b.isEmpty {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            if cur.min()! > limit { return limit + 1 }
            prev = cur
        }
        return prev[b.count]
    }

    /// How many of `words` have a match in `other`.
    static func overlap(_ words: [String], _ other: [String]) -> Int {
        words.filter { w in other.contains { sameWord(w, $0) } }.count
    }

    /// Finds the notes slide whose title is the title on screen.
    ///
    /// Only the slide's title counts, not every word on screen: slides share words, and an editor shows the
    /// titles of other slides around the one you're on. A notes slide matches when nearly all of its title's
    /// words are in the title on screen, and the title on screen is mostly made of its words.
    /// - Parameters:
    ///   - screenTitle: the title read off the slide (its largest text near the top).
    ///   - screenLines: kept for callers; not used for scoring.
    ///   - near: the slide showing now. Ties go to the closest slide.
    public static func match(screenTitle: String?, screenLines: [String] = [], slides: [Slide], near: Int) -> Match? {
        let screen = keyWords(screenTitle ?? "")
        guard !screen.isEmpty else { return nil }

        var scored: [(index: Int, score: Double, key: String)] = []
        for (i, slide) in slides.enumerated() {
            let words = keyWords(slide.title)
            guard !words.isEmpty else { continue }
            let shared = Double(overlap(words, screen))
            let recall = shared / Double(words.count)                 // how much of this slide's title is on screen
            let precision = Double(overlap(screen, words)) / Double(screen.count) // how much of the screen title is this title
            var score = recall + precision == 0 ? 0 : 2 * recall * precision / (recall + precision)
            // One shared word proves little unless the title is that one word.
            if shared < 2 && !(words.count == 1 && screen.count == 1) { score = min(score, 0.5) }
            scored.append((i, score, words.joined(separator: " ")))
        }
        guard !scored.isEmpty else { return nil }

        let bestScore = scored.map { $0.score }.max()!
        // Ties (two "Thank you" slides): take the one closest to where you are.
        let best = scored.filter { abs($0.score - bestScore) < 0.001 }
            .min(by: { abs($0.index - near) < abs($1.index - near) })!
        let runnerUp = scored.filter { $0.key != best.key }.map { $0.score }.max() ?? 0
        return Match(index: best.index, score: best.score, margin: best.score - runnerUp)
    }

    /// Whether a match is sure enough to move the notes on its own. A jump of more than a few slides
    /// needs a near-exact title.
    public static func isConfident(_ m: Match, from current: Int? = nil) -> Bool {
        let far = current.map { abs(m.index - $0) > 3 } ?? false
        return m.score >= (far ? 0.9 : 0.75) && m.margin >= 0.2
    }
}
