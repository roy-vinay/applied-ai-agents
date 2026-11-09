import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Turns a Word document's XML into Markdown that keeps what matters for finding and reading answers:
/// headings (by style, or a short paragraph that's entirely bold), bulleted and numbered lists, bold text,
/// and table rows. Plain text conversion loses all of that, and with it every section boundary.
public enum DocxMarkdown {
    /// `document` is word/document.xml; `styles` and `numbering` are word/styles.xml and word/numbering.xml.
    public static func convert(document: Data, styles: Data? = nil, numbering: Data? = nil) -> String {
        let headingStyles = styles.map(StyleParser.parse) ?? [:]
        let numberFormats = numbering.map(NumberingParser.parse) ?? [:]
        let p = DocumentParser(headingStyles: headingStyles, numberFormats: numberFormats)
        let parser = XMLParser(data: document)
        parser.delegate = p
        parser.parse()
        return p.output.joined(separator: "\n").replacingOccurrences(of: "\n\n\n", with: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    /// Heading level from a style's id or display name ("Heading2", "heading 2", "Title").
    static func headingLevel(styleID: String, name: String?) -> Int? {
        for raw in [styleID, name ?? ""] {
            let s = raw.lowercased().replacingOccurrences(of: " ", with: "")
            if s == "title" { return 1 }
            if s == "subtitle" { return 2 }
            if s.hasPrefix("heading"), let n = Int(s.dropFirst("heading".count)), (1...6).contains(n) { return n }
        }
        return nil
    }
}

/// styleId -> heading level, for paragraph styles that are headings.
final class StyleParser: NSObject, XMLParserDelegate {
    var levels: [String: Int] = [:]
    private var id: String?
    private var name: String?
    private var outline: Int?

    static func parse(_ data: Data) -> [String: Int] {
        let p = StyleParser()
        let x = XMLParser(data: data)
        x.delegate = p
        x.parse()
        return p.levels
    }

    func parser(_ parser: XMLParser, didStartElement e: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String] = [:]) {
        switch e {
        case "w:style": id = a["w:styleId"]; name = nil; outline = nil
        case "w:name": name = a["w:val"]
        case "w:outlineLvl": outline = a["w:val"].flatMap(Int.init).map { $0 + 1 }
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement e: String, namespaceURI: String?, qualifiedName: String?) {
        guard e == "w:style", let id else { return }
        if let level = DocxMarkdown.headingLevel(styleID: id, name: name) ?? outline.flatMap({ $0 <= 6 ? $0 : nil }) {
            levels[id] = level
        }
        self.id = nil
    }
}

/// numId -> (ilvl -> numFmt), so numbered lists keep their numbers.
final class NumberingParser: NSObject, XMLParserDelegate {
    private var abstract: [String: [Int: String]] = [:]
    private var numToAbstract: [String: String] = [:]
    private var currentAbstract: String?
    private var currentLevel: Int?
    private var currentNum: String?

    static func parse(_ data: Data) -> [String: [Int: String]] {
        let p = NumberingParser()
        let x = XMLParser(data: data)
        x.delegate = p
        x.parse()
        var out: [String: [Int: String]] = [:]
        for (num, abs) in p.numToAbstract { out[num] = p.abstract[abs] ?? [:] }
        return out
    }

    func parser(_ parser: XMLParser, didStartElement e: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String] = [:]) {
        switch e {
        case "w:abstractNum": currentAbstract = a["w:abstractNumId"]
        case "w:lvl": currentLevel = a["w:ilvl"].flatMap(Int.init)
        case "w:numFmt":
            if let abs = currentAbstract, let lvl = currentLevel, let fmt = a["w:val"] { abstract[abs, default: [:]][lvl] = fmt }
        case "w:num": currentNum = a["w:numId"]
        case "w:abstractNumId": if let num = currentNum, let v = a["w:val"] { numToAbstract[num] = v }
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement e: String, namespaceURI: String?, qualifiedName: String?) {
        if e == "w:abstractNum" { currentAbstract = nil }
        if e == "w:num" { currentNum = nil }
    }
}

final class DocumentParser: NSObject, XMLParserDelegate {
    let headingStyles: [String: Int]
    let numberFormats: [String: [Int: String]]
    var output: [String] = []

    // Paragraph state
    private var inParagraph = false
    private var style: String?
    private var numID: String?
    private var ilvl = 0
    private var runs: [(text: String, bold: Bool)] = []
    // Run state
    private var inRun = false
    private var bold = false
    private var inText = false
    private var runText = ""
    // Tables
    private var tableDepth = 0
    private var cell: [String] = []
    private var row: [String] = []
    // Lists
    private var counters: [String: [Int: Int]] = [:]
    private var lastWasList = false
    private var lastHeadingLevel = 1

    init(headingStyles: [String: Int], numberFormats: [String: [Int: String]]) {
        self.headingStyles = headingStyles
        self.numberFormats = numberFormats
    }

    func parser(_ parser: XMLParser, didStartElement e: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String] = [:]) {
        switch e {
        case "w:p": inParagraph = true; style = nil; numID = nil; ilvl = 0; runs = []
        case "w:pStyle" where inParagraph && !inRun: style = a["w:val"]
        case "w:numId" where inParagraph: numID = a["w:val"]; if numID == "0" { numID = nil }
        case "w:ilvl" where inParagraph: ilvl = a["w:val"].flatMap(Int.init) ?? 0
        case "w:r": inRun = true; bold = false; runText = ""
        case "w:b" where inRun:
            let v = a["w:val"]?.lowercased()
            bold = !(v == "0" || v == "false" || v == "off")
        case "w:t": inText = true
        case "w:tab" where inRun: runText += " "
        case "w:br" where inRun: runText += " "
        case "w:tbl": tableDepth += 1
        case "w:tr": row = []
        case "w:tc": cell = []
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inText { runText += string }
    }

    func parser(_ parser: XMLParser, didEndElement e: String, namespaceURI: String?, qualifiedName: String?) {
        switch e {
        case "w:t": inText = false
        case "w:r":
            if !runText.isEmpty { runs.append((runText, bold)) }
            inRun = false
        case "w:p": endParagraph()
        case "w:tc": row.append(cell.joined(separator: " ").trimmingCharacters(in: .whitespaces))
        case "w:tr":
            let cells = row.filter { !$0.isEmpty }
            if !cells.isEmpty { emit(cells.joined(separator: " | "), list: false) }
        case "w:tbl": tableDepth -= 1
        default: break
        }
    }

    private func endParagraph() {
        inParagraph = false
        let plain = runs.map(\.text).joined().trimmingCharacters(in: .whitespaces)
        guard !plain.isEmpty else { return }
        if tableDepth > 0 { cell.append(inline()); return }

        var level = style.flatMap { headingStyles[$0] } ?? style.flatMap { DocxMarkdown.headingLevel(styleID: $0, name: nil) }
        // A short paragraph that's entirely bold and isn't a sentence reads as a heading.
        if level == nil, numID == nil, runs.allSatisfy({ $0.bold || $0.text.trimmingCharacters(in: .whitespaces).isEmpty }),
           plain.count <= 100, !plain.hasSuffix("."), !plain.hasSuffix(",") {
            level = min(6, lastHeadingLevel + 1)
        }
        if let level {
            lastHeadingLevel = level
            counters = [:]
            emit(String(repeating: "#", count: level) + " " + plain, list: false)
            return
        }
        if let numID {
            let fmt = numberFormats[numID]?[ilvl] ?? "bullet"
            var levels = counters[numID] ?? [:]
            levels[ilvl, default: 0] += 1
            for deeper in levels.keys where deeper > ilvl { levels[deeper] = nil }
            counters[numID] = levels
            let marker = ["decimal", "decimalZero", "lowerLetter", "upperLetter", "lowerRoman", "upperRoman"].contains(fmt)
                ? "\(levels[ilvl] ?? 1)." : "-"
            emit(String(repeating: "  ", count: ilvl) + marker + " " + inline(), list: true)
            return
        }
        emit(inline(), list: false)
    }

    /// Runs as Markdown, merging neighbouring bold runs into one **...**.
    private func inline() -> String {
        var out = ""
        var boldBuffer = ""
        func flushBold() {
            guard !boldBuffer.isEmpty else { return }
            let core = boldBuffer.trimmingCharacters(in: .whitespaces)
            if core.isEmpty { out += boldBuffer } else {
                let lead = boldBuffer.prefix(while: { $0 == " " })
                let trail = String(boldBuffer.reversed().prefix(while: { $0 == " " }))
                out += lead + "**" + core + "**" + trail
            }
            boldBuffer = ""
        }
        for r in runs {
            if r.bold { boldBuffer += r.text } else { flushBold(); out += r.text }
        }
        flushBold()
        return out.trimmingCharacters(in: .whitespaces)
    }

    /// Lists stay together (single line breaks); everything else is its own paragraph.
    private func emit(_ line: String, list: Bool) {
        if !(list && lastWasList), !output.isEmpty { output.append("") }
        output.append(line)
        lastWasList = list
    }
}
