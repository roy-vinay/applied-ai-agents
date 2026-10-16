import AppKit
import MDEditDiffCore

/// Light syntax highlighting for the source editor. It only changes colors and weights,
/// never the text.
struct MarkdownHighlighter {
    let fontSize: CGFloat
    let baseFont: NSFont
    let boldFont: NSFont
    let baseAttributes: [NSAttributedString.Key: Any]
    private let rules: [(NSRegularExpression, [NSAttributedString.Key: Any])]

    /// Above this size, highlighting is skipped to keep typing responsive.
    static let maxLength = 400_000

    init(fontSize: CGFloat) {
        self.fontSize = fontSize
        let regular = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let bold = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .bold)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = 1.15
        baseFont = regular
        boldFont = bold
        baseAttributes = [.font: regular, .foregroundColor: NSColor.textColor, .paragraphStyle: paragraph]

        func re(_ pattern: String) -> NSRegularExpression {
            // Patterns are constants checked by MarkdownSyntaxTests.
            try! NSRegularExpression(pattern: pattern, options: MarkdownSyntax.options)
        }
        let muted = NSColor.secondaryLabelColor
        // The app's indigo accent (matches the icon and the preview), lighter in dark mode.
        let accent = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 0.56, green: 0.55, blue: 1.0, alpha: 1)
                : NSColor(srgbRed: 0.29, green: 0.28, blue: 0.88, alpha: 1)
        }
        rules = [
            (re(MarkdownSyntax.heading), [.font: bold, .foregroundColor: NSColor.labelColor]),
            (re(MarkdownSyntax.bold), [.font: bold]),
            (re(MarkdownSyntax.italic), [.obliqueness: 0.15]),
            (re(MarkdownSyntax.strikethrough), [.strikethroughStyle: NSUnderlineStyle.single.rawValue, .foregroundColor: muted]),
            (re(MarkdownSyntax.quote), [.foregroundColor: muted]),
            (re(MarkdownSyntax.listMarker), [.foregroundColor: accent]),
            (re(MarkdownSyntax.link), [.foregroundColor: NSColor.linkColor]),
            (re(MarkdownSyntax.inlineCode), [.foregroundColor: accent]),
            (re(MarkdownSyntax.codeFence), [.foregroundColor: NSColor.secondaryLabelColor, .font: regular]),
            (re(MarkdownSyntax.rule), [.foregroundColor: muted]),
        ]
    }

    func apply(to textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let full = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.setAttributes(baseAttributes, range: full)
        if storage.length <= Self.maxLength {
            let string = storage.string
            for (regex, attrs) in rules {
                regex.enumerateMatches(in: string, options: [], range: full) { match, _, _ in
                    if let r = match?.range, r.length > 0 { storage.addAttributes(attrs, range: r) }
                }
            }
        }
        storage.endEditing()
        textView.typingAttributes = baseAttributes
    }
}
