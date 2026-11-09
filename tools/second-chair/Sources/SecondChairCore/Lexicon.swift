import Foundation

/// Turning text into search terms, sentences and numbers. Deliberately simple and predictable,
/// so a miss can be explained by looking at the words.
public enum Lexicon {
    static let stopwords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "been", "but", "by", "can", "could", "did", "do", "does",
        "for", "from", "had", "has", "have", "how", "i", "if", "in", "into", "is", "it", "its", "me", "my",
        "of", "on", "or", "our", "so", "that", "the", "their", "them", "then", "there", "these", "they",
        "this", "those", "to", "was", "we", "were", "what", "when", "where", "which", "who", "why", "will",
        "with", "would", "you", "your", "about", "tell", "walk", "through", "give", "us", "just", "some",
        "any", "all", "also", "more", "most", "very", "really", "kind", "sort", "like", "one", "time",
        "talk", "describe", "share", "explain", "example", "maybe", "um", "uh", "okay", "yeah", "well",
        "much", "many", "think", "get", "got", "go", "went", "thing", "things", "something", "ever", "been",
        "being", "am", "here", "now", "please", "let", "let's", "say", "said", "know", "want", "make", "times", "ca", "wo",
    ]

    /// Lowercased words and numbers, without stopwords, lightly stemmed.
    public static func terms(_ text: String) -> [String] {
        words(text).compactMap { w in
            var lower = w.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
            for contraction in ["'s", "'re", "'ve", "'ll", "'d", "'m", "n't"] where lower.hasSuffix(contraction) {
                lower.removeLast(contraction.count)
                break
            }
            if stopwords.contains(lower) { return nil }
            if lower.count < 2, !lower.allSatisfy(\.isNumber) { return nil }
            return stem(lower)
        }
    }

    /// Raw words, keeping digits joined to decimal points, percent and currency signs.
    public static func words(_ text: String) -> [String] {
        var out: [String] = []
        var current = ""
        let chars = Array(text)
        for (i, c) in chars.enumerated() {
            let next = i + 1 < chars.count ? chars[i + 1] : " "
            let keepsNumber = (c == "." || c == ",") && current.last?.isNumber == true && next.isNumber
            if c.isLetter || c.isNumber || c == "%" || c == "$" || c == "'" || keepsNumber {
                current.append(c)
            } else if !current.isEmpty {
                out.append(current)
                current = ""
            }
        }
        if !current.isEmpty { out.append(current) }
        return out.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "'")) }.filter { !$0.isEmpty }
    }

    /// Irregular past tenses that interview stories use a lot.
    static let irregular: [String: String] = [
        "grew": "grow", "grown": "grow", "led": "lead", "built": "build", "ran": "run", "took": "take",
        "brought": "bring", "taught": "teach", "fell": "fall", "won": "win", "lost": "lose", "sold": "sell",
        "began": "begin", "chose": "choose", "wrote": "write", "felt": "feel", "kept": "keep", "met": "meet",
        "paid": "pay", "spent": "spend", "drove": "drive",
        "rose": "rise", "fought": "fight", "made": "make", "bought": "buy", "left": "leave",
    ]

    static func stem(_ w: String) -> String {
        if w.contains(where: \.isNumber) { return w }
        var base = irregular[w] ?? w
        if irregular[w] == nil {
            if base.hasSuffix("ies"), base.count > 4 { base = String(base.dropLast(3)) + "y" }
            else if base.hasSuffix("es"), ["s", "x", "z", "ch", "sh"].contains(where: { base.dropLast(2).hasSuffix($0) }) { base.removeLast(2) }
            else if base.hasSuffix("s"), !base.hasSuffix("ss"), !base.hasSuffix("us"), !base.hasSuffix("is"), base.count > 3 { base.removeLast() }
            for suffix in ["ingly", "ing", "edly", "ed"] where base.hasSuffix(suffix) && base.count - suffix.count >= 3 {
                base.removeLast(suffix.count)
                // shipped -> ship, planning -> plan
                if let last = base.last, base.count >= 4, base.dropLast().last == last, !"lsz".contains(last) { base.removeLast() }
                break
            }
        }
        // hire, hired, hiring all meet at "hir"
        if base.count >= 4, base.hasSuffix("e") { base.removeLast() }
        return base
    }

    /// Sentences, split on terminal punctuation followed by a space or line break.
    public static func sentences(_ text: String) -> [String] {
        var out: [String] = []
        var current = ""
        let chars = Array(text)
        for (i, c) in chars.enumerated() {
            current.append(c)
            let next = i + 1 < chars.count ? chars[i + 1] : " "
            if (c == "." || c == "?" || c == "!") && (next == " " || next == "\n") || c == "\n" {
                let s = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !s.isEmpty { out.append(s) }
                current = ""
            }
        }
        let s = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.isEmpty { out.append(s) }
        return out
    }

    /// Every figure in the text, normalised so "$4.2M", "4.2 million" and "4.2m" compare equal
    /// and "1,200" equals "1200". Years and plain counts are included: any figure counts.
    public static func numbers(_ text: String) -> Set<String> {
        var found: Set<String> = []
        let ws = words(text)
        for (i, raw) in ws.enumerated() {
            var w = raw.lowercased().replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "")
            guard let first = w.first, first.isNumber else { continue }
            var unit = ""
            // A unit stuck to the number: 40%, 4.2m, 30k, 3x, 2b
            while let last = w.last, last.isLetter || last == "%" {
                unit = String(last) + unit
                w.removeLast()
            }
            guard !w.isEmpty, w.allSatisfy({ $0.isNumber || $0 == "." }) else { continue }
            // A unit as the next word: 4.2 million, 40 percent
            if unit.isEmpty, i + 1 < ws.count {
                switch ws[i + 1].lowercased() {
                case "million", "mm": unit = "m"
                case "billion", "bn": unit = "b"
                case "thousand": unit = "k"
                case "percent", "pct": unit = "%"
                case "x": unit = "x"
                default: break
                }
            }
            switch unit {
            case "million", "mm": unit = "m"
            case "billion", "bn": unit = "b"
            case "thousand": unit = "k"
            case "percent", "pct": unit = "%"
            case "m", "b", "k", "%", "x": break
            default: unit = "" // ordinals and words like "3rd", "2nd", "10am" keep only the figure
            }
            if w.contains(".") { while w.hasSuffix("0") { w.removeLast() }; if w.hasSuffix(".") { w.removeLast() } }
            found.insert(w + unit)
        }
        return found
    }

    /// Capitalised names that aren't at the start of a sentence: companies, products, people, places.
    public static func names(_ text: String) -> Set<String> {
        let common: Set<String> = ["I", "I'm", "I've", "I'd", "I'll", "The", "A", "An", "We", "My", "Our", "It",
                                   "This", "That", "So", "And", "But", "In", "On", "At", "For", "As", "If",
                                   "When", "Then", "There", "They", "He", "She", "You", "Yes", "No", "OK"]
        var found: Set<String> = []
        for sentence in sentences(text) {
            let ws = words(sentence)
            for w in ws.dropFirst() where w.first?.isUppercase == true && !common.contains(w) && w.count > 1 {
                found.insert(w)
            }
        }
        return found
    }
}
