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

    /// Finds the notes slide whose title is on screen.
    /// - Parameters:
    ///   - screenTitle: the line that looks like the slide's title (the largest text near the top), if any.
    ///   - screenLines: every line of text read from the screen.
    ///   - near: the slide showing now; among equally good matches, the closest one wins.
    public static func match(screenTitle: String?, screenLines: [String], slides: [Slide], near: Int) -> Match? {
        let titleWords = Set(keyWords(screenTitle ?? ""))
        let allWords = Set(screenLines.flatMap(keyWords))
        guard !titleWords.isEmpty || !allWords.isEmpty else { return nil }

        var scored: [(index: Int, score: Double, key: String)] = []
        for (i, slide) in slides.enumerated() {
            let words = keyWords(slide.title)
            guard !words.isEmpty else { continue }
            let set = Set(words)
            // How alike the on-screen title and this slide's title are (Dice coefficient).
            let dice = titleWords.isEmpty ? 0 : 2 * Double(set.intersection(titleWords).count) / Double(set.count + titleWords.count)
            // How much of this slide's title appears anywhere on screen. Short titles prove less.
            let contained = Double(set.intersection(allWords).count) / Double(set.count)
            let weight = set.count >= 3 ? 0.85 : set.count == 2 ? 0.7 : 0.5
            scored.append((i, max(dice, contained * weight), words.joined(separator: " ")))
        }
        guard !scored.isEmpty else { return nil }

        let bestScore = scored.map { $0.score }.max()!
        // Ties (two "Thank you" slides): take the one closest to where you are.
        let best = scored.filter { abs($0.score - bestScore) < 0.001 }
            .min(by: { abs($0.index - near) < abs($1.index - near) })!
        let runnerUp = scored.filter { $0.key != best.key }.map { $0.score }.max() ?? 0
        return Match(index: best.index, score: best.score, margin: best.score - runnerUp)
    }

    /// Whether a match is sure enough to move the notes on its own.
    public static func isConfident(_ m: Match) -> Bool { m.score >= 0.6 && m.margin >= 0.15 }
}
