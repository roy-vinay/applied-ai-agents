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
