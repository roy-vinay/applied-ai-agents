import SwiftUI
import SecondChairCore

/// The whole document a match comes from, as it reads there, scrolled to the match. The matched section sits
/// on a tinted band and its answer sentences are yellow, so you can read around it and say more than was asked.
/// Each document's blocks, built once per index rather than on every redraw.
@MainActor
enum DocumentCache {
    struct Part { var headings: [String]; var chunk: Chunk?; var blocks: [SectionText.Block] }
    private static var built: Date = .distantPast
    private static var parts: [String: [Part]] = [:]

    static func parts(_ file: String) -> [Part] {
        let index = Library.shared.index
        if index.builtAt != built { parts = [:]; built = index.builtAt }
        if let cached = parts[file] { return cached }
        let made = index.documentParts(file: file).map { Part(headings: $0.headings, chunk: $0.chunk, blocks: SectionText.blocks($0.text)) }
        parts[file] = made
        return made
    }
}

struct DocumentDetail: View, Equatable {
    nonisolated static func == (a: DocumentDetail, b: DocumentDetail) -> Bool {
        a.match == b.match && a.question == b.question && a.size == b.size && a.compact == b.compact
    }

    var match: SectionMatch
    var question: String
    var size: CGFloat = 16
    var compact = false
    @State private var copied = false

    struct Row {
        var block: SectionText.Block
        var inSection: Bool
    }

    var rows: [Row] {
        let section = match.section
        var out: [Row] = []
        for part in DocumentCache.parts(section.file) {
            let inSection: Bool
            if let chunk = part.chunk {
                inSection = section.contains(chunk)
            } else {
                // A heading row: inside when it is the section's own heading or one beneath it.
                inSection = section.anchorChunk == nil && !section.path.isEmpty && part.headings.starts(with: section.path)
            }
            for block in part.blocks { out.append(Row(block: block, inSection: inSection)) }
        }
        if out.isEmpty { out = SectionText.blocks(section.text).map { Row(block: $0, inSection: true) } }
        return out
    }

    var body: some View {
        let rows = self.rows
        let marked = SectionText.answerSentences(match: match, question: question)
        let start = rows.firstIndex(where: \.inSection) ?? 0
        let firstMarked = rows.indices.first { rows[$0].inSection && SectionText.isMarked(rows[$0].block.text, marked) }
        let target = firstMarked.map { $0 - start > 6 ? $0 - 1 : start } ?? start

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(match.section.fileName).font(.system(size: compact ? 10.5 : 12, weight: .semibold, design: .monospaced))
                Text(match.section.title).font(.system(size: compact ? 10.5 : 12, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                if !compact {
                    Button(copied ? "Copied" : "Copy section") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(match.section.title + "\n\n" + match.section.text.replacingOccurrences(of: "**", with: ""), forType: .string)
                        copied = true
                    }
                    .controlSize(.small)
                    Button { NSWorkspace.shared.open(URL(fileURLWithPath: match.section.file)) } label: { Image(systemName: "arrow.up.forward.square") }
                        .buttonStyle(.borderless).help("Open the document")
                }
            }
            .padding(.bottom, compact ? 6 : 10)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                            SectionText.view(row.block, marked: row.inSection ? marked : [], question: row.inSection ? question : "", size: size)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, compact ? 6 : 10)
                                .padding(.vertical, compact ? 3 : 5)
                                .background(row.inSection ? Color.accentColor.opacity(0.07) : Color.clear)
                                .overlay(alignment: .leading) {
                                    if row.inSection { Rectangle().fill(Color.accentColor.opacity(0.6)).frame(width: 3) }
                                }
                                .opacity(row.inSection ? 1 : 0.78)
                                .id(i)
                        }
                    }
                    .padding(.trailing, 6)
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { proxy.scrollTo(target, anchor: .top) }
                }
            }
        }
        .padding(compact ? 0 : 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(compact ? AnyShapeStyle(Color.clear) : AnyShapeStyle(.background), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(compact ? Color.clear : Color.secondary.opacity(0.2)))
    }
}
