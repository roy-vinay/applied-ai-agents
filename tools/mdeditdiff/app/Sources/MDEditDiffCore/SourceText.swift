import Foundation

/// The line-ending style of a file.
public enum LineEnding: String, Sendable {
    case lf = "\n"
    case crlf = "\r\n"
    case cr = "\r"
}

/// A Markdown file's text plus everything needed to save it back without changing
/// bytes the user didn't touch: byte-order mark, line endings, and the original data.
///
/// The editor works with `text`, which always uses "\n" line endings. `data(for:)` turns
/// edited text back into file bytes:
/// - If the text is unchanged, the original bytes are returned exactly, whatever they were.
/// - Otherwise line endings are converted back to the file's style and the byte-order mark is kept.
public struct SourceText: Equatable, Sendable {
    public enum DecodeError: Error, LocalizedError, Equatable {
        case notUTF8

        public var errorDescription: String? {
            "This file isn't UTF-8 text. mdEditDiff only opens UTF-8 files, so it won't convert or overwrite this one."
        }
    }

    public static let bom: [UInt8] = [0xEF, 0xBB, 0xBF]

    /// The exact bytes the text was loaded from.
    public let originalData: Data
    public let hasBOM: Bool
    /// The most common line ending in the file ("\n" for files with no line breaks).
    public let lineEnding: LineEnding
    /// True when the file uses more than one line-ending style.
    public let hasMixedLineEndings: Bool
    /// Text with every line ending normalized to "\n".
    public let text: String

    public init(data: Data) throws {
        let bytes = [UInt8](data)
        let hasBOM = bytes.starts(with: SourceText.bom)
        let body = hasBOM ? Array(bytes.dropFirst(3)) : bytes

        // Strict UTF-8: decoding must round-trip to the same bytes.
        let decoded = String(decoding: body, as: UTF8.self)
        guard Array(decoded.utf8) == body else { throw DecodeError.notUTF8 }

        var crlf = 0, lf = 0, cr = 0
        var i = 0
        while i < body.count {
            let b = body[i]
            if b == 0x0D {
                if i + 1 < body.count && body[i + 1] == 0x0A {
                    crlf += 1
                    i += 2
                    continue
                }
                cr += 1
            } else if b == 0x0A {
                lf += 1
            }
            i += 1
        }
        let styles = [crlf, lf, cr].filter { $0 > 0 }.count
        let ending: LineEnding
        if crlf >= lf && crlf >= cr && crlf > 0 {
            ending = .crlf
        } else if cr > lf {
            ending = .cr
        } else {
            ending = .lf
        }

        self.originalData = data
        self.hasBOM = hasBOM
        self.lineEnding = ending
        self.hasMixedLineEndings = styles > 1
        self.text = SourceText.normalize(decoded)
    }

    /// An empty new document.
    public static let empty: SourceText = try! SourceText(data: Data())

    /// True if the file ends with a line break.
    public var endsWithNewline: Bool { text.hasSuffix("\n") }

    /// Bytes to write for the edited text.
    public func data(for editedText: String) -> Data {
        let edited = SourceText.normalize(editedText)
        // Compare scalars, not Swift's canonical equivalence, so any real change is saved.
        if edited.unicodeScalars.elementsEqual(text.unicodeScalars) {
            return originalData
        }
        var out = Data()
        if hasBOM { out.append(contentsOf: SourceText.bom) }
        let withEndings = lineEnding == .lf ? edited : edited.replacingOccurrences(of: "\n", with: lineEnding.rawValue)
        out.append(contentsOf: Array(withEndings.utf8))
        return out
    }

    /// True if saving this text would change the file.
    public func isEdited(_ editedText: String) -> Bool {
        !SourceText.normalize(editedText).unicodeScalars.elementsEqual(text.unicodeScalars)
    }

    static func normalize(_ s: String) -> String {
        guard s.utf8.contains(0x0D) else { return s }
        return s.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }
}
