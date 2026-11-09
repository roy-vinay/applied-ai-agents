import SwiftUI
import SecondChairCore

extension AnswerLabel {
    var color: Color {
        switch self {
        case .grounded: return Color(red: 0.13, green: 0.62, blue: 0.38)
        case .synthesized: return Color(red: 0.86, green: 0.52, blue: 0.10)
        case .notInDocs: return Color(red: 0.45, green: 0.47, blue: 0.52)
        }
    }

    var symbol: String {
        switch self {
        case .grounded: return "checkmark.seal.fill"
        case .synthesized: return "square.stack.3d.up.fill"
        case .notInDocs: return "questionmark.folder.fill"
        }
    }

    var title: String {
        switch self {
        case .grounded: return "Grounded"
        case .synthesized: return "Synthesized"
        case .notInDocs: return "Not in your docs"
        }
    }

    var explanation: String {
        switch self {
        case .grounded: return "One passage answers this. Every figure is in it."
        case .synthesized: return "Made on the spot from these passages."
        case .notInDocs: return "Your documents don't cover this. Answer from judgement, then add it to your prep."
        }
    }
}

struct LabelPill: View {
    var label: AnswerLabel
    var compact = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: label.symbol)
            Text(label.title.uppercased())
        }
        .font(.system(size: compact ? 10 : 11, weight: .bold))
        .tracking(0.4)
        .foregroundStyle(.white)
        .padding(.horizontal, compact ? 7 : 9)
        .padding(.vertical, compact ? 3 : 4)
        .background(label.color, in: Capsule())
    }
}

/// A passage with the question's words picked out, so you can find the figure at a glance.
enum Highlight {
    static func passage(_ text: String, question: String, size: CGFloat = 14) -> AttributedString {
        let wanted = Set(Lexicon.terms(question))
        var out = AttributedString()
        var word = ""
        var gap = ""
        func flushWord() {
            guard !word.isEmpty else { return }
            var piece = AttributedString(word)
            let isFigure = word.contains(where: \.isNumber)
            if isFigure || Lexicon.terms(word).contains(where: wanted.contains) {
                piece.font = .system(size: size, weight: .semibold)
                piece.backgroundColor = isFigure ? Color.yellow.opacity(0.28) : Color.accentColor.opacity(0.14)
            }
            out += piece
            word = ""
        }
        func flushGap() {
            guard !gap.isEmpty else { return }
            out += AttributedString(gap)
            gap = ""
        }
        for c in text {
            if c.isLetter || c.isNumber || c == "%" || c == "$" || c == "." && word.last?.isNumber == true {
                flushGap()
                word.append(c)
            } else {
                flushWord()
                gap.append(c)
            }
        }
        flushWord()
        flushGap()
        return out
    }
}

extension Highlight {
    /// The whole passage with the sentences that answer the question in bold, so the answer is read in place.
    static func inPlace(_ text: String, question: String, size: CGFloat = 15) -> AttributedString {
        var out = passage(text, question: question, size: size)
        let answer = Answerer.extract(question, from: text)
        for sentence in Lexicon.sentences(answer) {
            let needle = sentence.trimmingCharacters(in: .whitespaces)
            guard needle.count > 3, let r = out.range(of: needle) else { continue }
            out[r].font = .system(size: size, weight: .bold)
            out[r].foregroundColor = Color.primary
            out[r].backgroundColor = Color.yellow.opacity(0.22)
        }
        return out
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator.opacity(0.6)))
    }
}

/// Renders a section's Markdown as it reads in the document: headings, bullets, numbered items, bold,
/// with the sentences that answer the question marked in yellow and the question's words underlined.
enum SectionText {
    struct Block {
        enum Kind { case heading(Int), bullet(Int), numbered(String, Int), paragraph }
        var kind: Kind
        var text: String
    }

    static func blocks(_ markdown: String) -> [Block] {
        var out: [Block] = []
        for raw in markdown.components(separatedBy: "\n") {
            let indent = raw.prefix(while: { $0 == " " }).count / 2
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if line.hasPrefix("#") {
                let level = line.prefix(while: { $0 == "#" }).count
                out.append(Block(kind: .heading(level), text: line.dropFirst(level).trimmingCharacters(in: .whitespaces)))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") {
                out.append(Block(kind: .bullet(indent), text: String(line.dropFirst(2))))
            } else if let dot = line.firstIndex(of: "."), dot != line.startIndex, line[..<dot].allSatisfy(\.isNumber),
                      line.index(after: dot) < line.endIndex, line[line.index(after: dot)] == " " {
                out.append(Block(kind: .numbered(String(line[...dot]), indent), text: String(line[line.index(dot, offsetBy: 2)...])))
            } else {
                out.append(Block(kind: .paragraph, text: line))
            }
        }
        return out
    }

    static func plain(_ s: String) -> String {
        s.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "__", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-*•> ").union(.whitespaces))
    }

    /// The sentences that answer the question, from each passage that matched. A prepared answer is
    /// the answer in full, so nothing inside it needs marking.
    static func answerSentences(match: SectionMatch, question: String) -> [String] {
        guard !match.prepared else { return [] }
        return match.matched.flatMap { passage in
            Lexicon.sentences(Answerer.extract(question, from: passage)).map(plain)
        }.filter { $0.count > 3 }
    }

    static func isMarked(_ text: String, _ marked: [String]) -> Bool {
        let p = plain(text)
        return marked.contains { m in p.contains(m) || (p.count > 20 && m.contains(p)) }
    }

    static func attributed(_ text: String, marked: [String], question: String) -> AttributedString {
        var a = (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
        let p = String(a.characters)
        let yellow = Color.yellow.opacity(0.32)
        if p.count > 20, marked.contains(where: { $0.contains(p.trimmingCharacters(in: .whitespaces)) }) {
            a.backgroundColor = yellow
        } else {
            for m in marked { if let r = a.range(of: m) { a[r].backgroundColor = yellow } }
        }
        let wanted = Set(Lexicon.terms(question))
        var cursor = a.startIndex
        for w in Lexicon.words(p) where Lexicon.terms(w).contains(where: wanted.contains) {
            guard let r = a[cursor...].range(of: w) else { continue }
            a[r].underlineStyle = Text.LineStyle(pattern: .solid, color: Color.accentColor.opacity(0.7))
            cursor = r.upperBound
        }
        return a
    }

    @ViewBuilder
    static func view(_ block: Block, marked: [String], question: String, size: CGFloat) -> some View {
        let a = attributed(block.text, marked: marked, question: question)
        switch block.kind {
        case .heading(let level):
            Text(a).font(.system(size: size + (level <= 3 ? 3 : 1), weight: .bold)).padding(.top, 6)
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        case .bullet(let indent):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").font(.system(size: size, weight: .bold)).foregroundStyle(.secondary)
                Text(a).font(.system(size: size)).lineSpacing(4).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, CGFloat(indent) * 20 + 4)
        case .numbered(let n, let indent):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(n).font(.system(size: size, weight: .semibold)).monospacedDigit().frame(minWidth: 18, alignment: .trailing)
                Text(a).font(.system(size: size)).lineSpacing(4).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, CGFloat(indent) * 20)
        case .paragraph:
            Text(a).font(.system(size: size)).lineSpacing(4).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
    }
}
