import SwiftUI
import UniformTypeIdentifiers
import SecondChairCore

/// The app window: your documents on the left, ask and answer on the right.
struct RootView: View {
    @EnvironmentObject var model: AppModel
    @State private var importingFolder = false
    @State private var importingGate = false
    @State private var dropTargeted = false

    var body: some View {
        HStack(spacing: 0) {
            LibrarySidebar(importingFolder: $importingFolder)
                .frame(width: 290)
            Divider()
            VStack(spacing: 0) {
                TopBar(showSetup: $model.showSetup, showSettings: $model.showSettings, importingGate: $importingGate)
                Divider()
                if model.folders.isEmpty {
                    EmptyLibrary(importingFolder: $importingFolder, targeted: dropTargeted)
                } else {
                    AskView()
                }
            }
            .frame(minWidth: 560)
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(Color(nsColor: .windowBackgroundColor))
        .dropDestination(for: URL.self) { urls, _ in
            model.addFolders(urls)
            return true
        } isTargeted: { dropTargeted = $0 }
        .fileImporter(isPresented: $importingFolder, allowedContentTypes: [.folder], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { model.addFolders(urls) }
        }
        .fileImporter(isPresented: $importingGate, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result { model.runGate(url) }
        }
        .sheet(isPresented: $model.showSetup) { SessionSetupSheet().environmentObject(model) }
        .sheet(isPresented: $model.showSettings) { SettingsSheet().environmentObject(model) }
        .sheet(isPresented: Binding(get: { model.review != nil }, set: { if !$0 { model.finishReview(saveTranscript: false) } })) {
            ReviewSheet().environmentObject(model)
        }
        .sheet(isPresented: $model.showGateResult) { GateResultSheet().environmentObject(model) }
        .alert(model.warning?.title ?? "", isPresented: Binding(get: { model.warning != nil }, set: { if !$0 { model.warning = nil } })) {
            Button("OK") { model.warning = nil }
        } message: {
            Text(model.warning?.text ?? "")
        }
    }
}

// MARK: Top bar

struct TopBar: View {
    @EnvironmentObject var model: AppModel
    @Binding var showSetup: Bool
    @Binding var showSettings: Bool
    @Binding var importingGate: Bool

    var body: some View {
        HStack(spacing: 10) {
            if model.sessionActive {
                HStack(spacing: 8) {
                    Circle().fill(.red).frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Session running").font(.system(size: 12, weight: .semibold))
                        Text(model.sessionHearing.isEmpty ? "Not listening. Type, or dictate with ⌃⌥D" : "Hearing " + model.sessionHearing.joined(separator: " + "))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                Button("End and Review") { model.endSession() }
                    .controlSize(.large)
            } else {
                Button { showSetup = true } label: {
                    HStack(spacing: 6) { Image(systemName: "person.wave.2.fill"); Text("Start Interview") }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.folders.isEmpty)
            }
            Spacer()
            GateBadge(importingGate: $importingGate)
            Button { showSettings = true } label: { Image(systemName: "gearshape") }
                .buttonStyle(.borderless)
                .help("Models and transcription")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }
}

struct GateBadge: View {
    @EnvironmentObject var model: AppModel
    @Binding var importingGate: Bool

    var body: some View {
        Menu {
            Button("Run Gate on a Question Set…") { importingGate = true }
            if model.gate != nil {
                Button("Show Last Result") { model.showGateResult = true }
            }
        } label: {
            HStack(spacing: 5) {
                if model.gateRunning { ProgressView().controlSize(.small) } else {
                    Image(systemName: model.gatePassed ? "lock.open.fill" : "lock.fill")
                }
                Text(model.gatePassed ? "Live listening on" : "Live listening locked")
            }
            .font(.system(size: 12, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .foregroundStyle(model.gatePassed ? Color.green : Color.secondary)
        .help("Live listening to another person unlocks when your answers pass the gate on your own questions.")
    }
}

// MARK: Library

struct LibrarySidebar: View {
    @EnvironmentObject var model: AppModel
    @Binding var importingFolder: Bool
    @State private var expanded: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Your documents").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button { importingFolder = true } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless)
                    .help("Add a folder")
            }
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(model.folders, id: \.self) { folder in
                        FolderRow(folder: folder, expanded: expanded.contains(folder)) {
                            if expanded.contains(folder) { expanded.remove(folder) } else { expanded.insert(folder) }
                        }
                    }
                    if model.folders.isEmpty {
                        Text("Drop a folder anywhere in this window, or press +.")
                            .font(.system(size: 12)).foregroundStyle(.secondary).padding(.horizontal, 16)
                    }
                }
                .padding(.horizontal, 8)
            }

            Divider()
            IndexFooter()
        }
        .background(Color(nsColor: .underPageBackgroundColor).opacity(0.5))
        .onAppear { if let f = model.folders.first { expanded.insert(f) } }
    }
}

struct FolderRow: View {
    @EnvironmentObject var model: AppModel
    var folder: String
    var expanded: Bool
    var toggle: () -> Void

    var docs: [IndexedDocument] { model.documents[folder] ?? [] }
    var isPrimary: Bool { model.primaryFolder == folder }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button(action: toggle) {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .foregroundStyle(.tertiary)
                        .frame(width: 10)
                    Image(systemName: isPrimary ? "star.circle.fill" : "folder.fill")
                        .foregroundStyle(isPrimary ? Color.orange : Color.accentColor)
                    VStack(alignment: .leading, spacing: 1) {
                        Text((folder as NSString).lastPathComponent)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                        Text(isPrimary ? "Primary prep pack · \(docs.count) documents" : "\(docs.count) documents")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
                .padding(.vertical, 6).padding(.horizontal, 8)
            }
            .buttonStyle(.plain)
            .background(isPrimary ? Color.orange.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .contextMenu {
                Button(isPrimary ? "Unpin as Primary Prep Pack" : "Make Primary Prep Pack") { model.togglePrimary(folder) }
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: folder)]) }
                Divider()
                Button("Remove from Second Chair") { model.removeFolder(folder) }
            }

            if expanded {
                ForEach(docs) { doc in
                    Button { NSWorkspace.shared.open(URL(fileURLWithPath: doc.path)) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: icon(doc.kind)).foregroundStyle(.secondary).frame(width: 14)
                            Text(doc.name).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Text("\(doc.passages)").font(.system(size: 10, weight: .medium)).foregroundStyle(.tertiary)
                                .help("\(doc.passages) passages")
                        }
                        .contentShape(Rectangle())
                        .padding(.vertical, 3).padding(.leading, 34).padding(.trailing, 8)
                    }
                    .buttonStyle(.plain)
                    .help("Open \(doc.name)")
                }
                if docs.isEmpty {
                    Text(model.isIndexing ? "Reading documents…" : "No readable documents found")
                        .font(.system(size: 11)).foregroundStyle(.secondary).padding(.leading, 34).padding(.vertical, 3)
                }
            }
        }
    }

    func icon(_ kind: String) -> String {
        switch kind {
        case "PDF": return "doc.richtext"
        case "DOCX", "DOC", "RTF": return "doc.text"
        default: return "doc.plaintext"
        }
    }
}

struct IndexFooter: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if model.isIndexing {
                    ProgressView().controlSize(.small)
                    Text("Reading your documents…")
                } else if model.isStale && !model.folders.isEmpty {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text("Index out of date")
                    Spacer()
                    Button("Update") { model.rebuild() }.controlSize(.small)
                } else if !model.folders.isEmpty {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("\(model.passageCount) passages ready")
                }
            }
            .font(.system(size: 11.5, weight: .medium))
            Text(model.usesEmbeddings ? "Keyword search + meaning search" : "Keyword search")
                .font(.system(size: 10.5)).foregroundStyle(.secondary)
            if !model.skipped.isEmpty {
                Text("\(model.skipped.count) file(s) skipped: no text to read")
                    .font(.system(size: 10.5)).foregroundStyle(.secondary)
                    .help(model.skipped.prefix(20).map { ($0 as NSString).lastPathComponent }.joined(separator: "\n"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
    }
}

struct EmptyLibrary: View {
    @Binding var importingFolder: Bool
    var targeted: Bool

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 54, weight: .light))
                .foregroundStyle(targeted ? Color.accentColor : .secondary)
            Text("Drop a folder of your documents here")
                .font(.system(size: 22, weight: .semibold))
            Text("Prep notes, story bank, numbers sheet, company research, past PRDs.\nMarkdown, text, PDF and Word. Everything stays on this Mac.")
                .font(.system(size: 14)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Choose Folder…") { importingFolder = true }
                .buttonStyle(.borderedProminent).controlSize(.large)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                .foregroundStyle(targeted ? Color.accentColor : Color.secondary.opacity(0.3))
                .padding(28)
        )
    }
}

// MARK: Ask

struct AskView: View {
    @EnvironmentObject var model: AppModel
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").font(.system(size: 16)).foregroundStyle(.secondary)
                    TextField("Ask anything your documents cover", text: $draft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 18))
                        .focused($focused)
                        .onSubmit { model.ask(draft); draft = "" }
                    if !draft.isEmpty {
                        Button("Ask") { model.ask(draft); draft = "" }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
                .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(focused ? Color.accentColor.opacity(0.7) : Color.secondary.opacity(0.25), lineWidth: focused ? 2 : 1))

                if let item = model.current {
                    AnswerView(item: item)
                } else {
                    StarterTips()
                }

                if model.history.count > (model.current == nil ? 0 : 1) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Earlier").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                        ForEach(model.history.filter { $0.id != model.current?.id }) { h in
                            Button { model.current = h } label: {
                                HStack(spacing: 10) {
                                    Circle().fill(h.card?.label.color ?? .gray).frame(width: 7, height: 7)
                                    Text(h.question).font(.system(size: 13)).lineLimit(1)
                                    Spacer()
                                    Text(h.card?.label.title ?? "").font(.system(size: 11)).foregroundStyle(.secondary)
                                }
                                .contentShape(Rectangle())
                                .padding(.vertical, 6).padding(.horizontal, 10)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 860, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .onAppear { focused = true }
    }
}

struct StarterTips: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("How answers work").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 12) {
                tip(.grounded)
                tip(.synthesized)
                tip(.notInDocs)
            }
            Text("Shortcuts anywhere: ⌃⌥Space ask from the floating window · ⌃⌥S show or hide it · ⌃⌥D dictate in a session")
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }

    func tip(_ label: AnswerLabel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            LabelPill(label: label, compact: true)
            Text(label.explanation).font(.system(size: 12.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(label.color.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Label and sources first (they arrive first), the sayable answer in large type beneath the label.
struct AnswerView: View {
    var item: Asked

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(item.question)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)

            if let card = item.card {
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            LabelPill(label: card.label)
                            Text(card.label.explanation).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
                            Spacer()
                        }
                        if let answer = card.answer {
                            Text(answer)
                                .font(.system(size: 20, weight: .regular))
                                .lineSpacing(4)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        } else if item.answering && card.label != .notInDocs {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("Writing an answer you can say…").font(.system(size: 14)).foregroundStyle(.secondary)
                            }
                        } else if let withheld = card.withheld {
                            Label(withheld, systemImage: "hand.raised.fill")
                                .font(.system(size: 13)).foregroundStyle(.orange)
                        }
                        Text(footnote(card)).font(.system(size: 11)).foregroundStyle(.tertiary)
                    }
                }

                if !card.passages.isEmpty {
                    Text(card.label == .notInDocs ? "Closest passage (doesn't answer it)" : card.passages.count > 1 ? "From \(card.passages.count) passages in your documents" : "From your documents")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                        .padding(.top, 4)
                    ForEach(Array(card.passages.enumerated()), id: \.offset) { _, hit in
                        SourceCard(hit: hit, question: item.question, dim: card.label == .notInDocs)
                    }
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Searching your documents…").foregroundStyle(.secondary)
                }
            }
        }
    }

    func footnote(_ card: AnswerCard) -> String {
        var bits = [String(format: "Source in %.1fs", card.sourceLatency)]
        if let by = card.answeredBy {
            bits.append(by == "extract" ? "answer lifted from the passage" : "answer by \(by)")
            bits.append(String(format: "%.1fs", card.answerLatency))
        }
        return bits.joined(separator: " · ")
    }
}

struct SourceCard: View {
    var hit: Hit
    var question: String
    var dim = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text").foregroundStyle(.secondary)
                Text(hit.chunk.fileName).font(.system(size: 12.5, weight: .semibold))
                if !hit.chunk.headings.isEmpty {
                    Text("›").foregroundStyle(.tertiary)
                    Text(hit.chunk.headingPath).font(.system(size: 12.5)).foregroundStyle(.secondary).lineLimit(1)
                }
                if hit.primary {
                    Text("PRIMARY").font(.system(size: 9, weight: .bold)).foregroundStyle(.orange)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .overlay(Capsule().strokeBorder(.orange.opacity(0.6)))
                }
                Spacer()
                Button { NSWorkspace.shared.open(URL(fileURLWithPath: hit.chunk.file)) } label: {
                    Image(systemName: "arrow.up.forward.square")
                }
                .buttonStyle(.borderless)
                .help("Open the document")
            }
            Text(Highlight.passage(hit.chunk.text, question: question))
                .font(.system(size: 14))
                .lineSpacing(3)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(dim ? 0.7 : 1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(dim ? Color.gray.opacity(0.4) : Color.accentColor.opacity(0.7)).frame(width: 3).padding(.vertical, 10)
        }
    }
}
