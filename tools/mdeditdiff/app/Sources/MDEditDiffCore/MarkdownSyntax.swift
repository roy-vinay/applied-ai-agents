import Foundation

/// Regular expressions for editor syntax highlighting. Kept here (without AppKit) so they can be unit-tested.
public enum MarkdownSyntax {
    public static let options: NSRegularExpression.Options = [.anchorsMatchLines]

    public static let heading = #"^ {0,3}#{1,6}(?:[ \t].*)?$"#
    public static let bold = #"\*\*[^*\n]+\*\*|__[^_\n]+__"#
    public static let italic = #"(?<![*\w])\*[^*\n]+\*(?![*\w])|(?<![_\w])_[^_\n]+_(?![_\w])"#
    public static let strikethrough = #"~~[^~\n]+~~"#
    public static let quote = #"^ {0,3}>.*$"#
    public static let listMarker = #"^[ \t]*(?:[-*+]|\d{1,9}[.)])(?=[ \t])"#
    public static let link = #"!?\[[^\]\n]*\]\([^)\n]*\)"#
    public static let inlineCode = #"`[^`\n]+`"#
    public static let codeFence = #"^ {0,3}(```|~~~)[\s\S]*?(^ {0,3}\1[ \t]*$|\z)"#
    public static let rule = #"^ {0,3}([-*_])(?:[ \t]*\1){2,}[ \t]*$"#

    public static let all: [String] = [heading, bold, italic, strikethrough, quote, listMarker, link, inlineCode, codeFence, rule]
}
