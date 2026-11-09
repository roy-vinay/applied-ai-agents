import SwiftUI
import UniformTypeIdentifiers
import SecondChairCore

/// The app window: your documents on the left, ask and answer on the right.
struct RootView: View {
    @EnvironmentObject var model: AppModel
    @State private var dropTargeted = false

    var body: some View {
        HStack(spacing: 0) {
            LibrarySidebar()
                .frame(width: 290)
            Divider()
            VStack(spacing: 0) {
                TopBar(showSetup: $model.showSetup, showSettings: $model.showSettings)
                Divider()
                if model.folders.isEmpty {
                    EmptyLibrary(targeted: dropTargeted)
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
                if let gate = model.session.gate, gate.mayDictate, !gate.mayListenContinuously {
                    Button { model.session.toggleDictation() } label: {
                        HStack(spacing: 6) {
                            Image(systemName: model.dictating ? "stop.circle.fill" : "mic.fill")
                            Text(model.dictating ? "Stop Dictating" : "Dictate Question")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(model.dictating ? .red : .accentColor)
                    .controlSize(.large)
                    .help("⌃⌥D from any app")
                }
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
            GateBadge()
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

    var body: some View {
        Menu {
            Button("Check Accuracy on a Question Set…") { model.chooseGateFile() }
            if model.gate != nil {
                Button("Show Last Result") { model.showGateResult = true }
            }
        } label: {
            HStack(spacing: 5) {
                if model.gateRunning { ProgressView().controlSize(.small) } else {
                    Image(systemName: model.gatePassed ? "checkmark.seal.fill" : "exclamationmark.triangle")
                }
                Text(model.gatePassed ? "Accuracy checked" : model.gate == nil ? "Accuracy not checked" : "Accuracy check failed")
            }
            .font(.system(size: 12, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .foregroundStyle(model.gatePassed ? Color.green : Color.orange)
        .help("Run your own questions through it to see how often it finds the right answer and says \u{201C}not in your docs\u{201D} when it should.")
    }
}

// MARK: Library

struct LibrarySidebar: View {
    @EnvironmentObject var model: AppModel
    @State private var collapsed: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Your documents").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button { model.chooseFolders() } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless)
                    .help("Add a folder")
            }
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(model.folders, id: \.self) { folder in
                        FolderRow(folder: folder, expanded: !collapsed.contains(folder)) {
                            if collapsed.contains(folder) { collapsed.remove(folder) } else { collapsed.insert(folder) }
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
    @EnvironmentObject var model: AppModel
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
            Button("Choose Folder…") { model.chooseFolders() }
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
        VStack(alignment: .leading, spacing: 14) {
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
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(focused ? Color.accentColor.opacity(0.7) : Color.secondary.opacity(0.25), lineWidth: focused ? 2 : 1))

            if model.sessionActive { LivePanel() }

            if let item = model.current {
                ResultsView(item: item)
            } else {
                ScrollView { StarterTips() }
            }
        }
        .padding(.horizontal, 22).padding(.top, 18).padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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

/// Like reading your prep doc: matches and similar questions on the left, the whole section on the right,
/// exactly as it reads in the document, with the answer marked in place.
struct ResultsView: View {
    @EnvironmentObject var model: AppModel
    var item: Asked
    @State private var tab = 0
    @State private var selected: String?

    var shown: SectionMatch? {
        let all = item.results + item.similar
        return all.first { $0.id == selected } ?? item.results.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            AnswerStrip(item: item)
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("", selection: $tab) {
                        Text("Matches \(item.results.count)").tag(0)
                        Text("Similar \(item.similar.count)").tag(1)
                        Text("Earlier").tag(2)
                    }
                    .pickerStyle(.segmented).labelsHidden()
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            switch tab {
                            case 0:
                                if item.results.isEmpty {
                                    note(item.answering ? "Searching your documents…" : "Nothing in your documents matches. Try Similar.")
                                }
                                ForEach(item.results) { m in row(m) }
                            case 1:
                                if item.similar.isEmpty { note("No similar questions or sections.") }
                                ForEach(item.similar) { m in row(m) }
                            default:
                                let earlier = model.history.filter { $0.id != item.id }
                                if earlier.isEmpty { note("Nothing asked yet.") }
                                ForEach(earlier) { h in
                                    Button { model.current = h } label: {
                                        HStack(spacing: 8) {
                                            Circle().fill(h.card?.label.color ?? .gray).frame(width: 7, height: 7)
                                            Text(h.question).font(.system(size: 13)).lineLimit(2)
                                            Spacer()
                                        }
                                        .contentShape(Rectangle()).padding(8)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .frame(width: 300)

                if let m = shown {
                    SectionDetail(match: m, question: item.question)
                        .id(m.id)
                } else {
                    VStack {
                        Spacer()
                        if item.answering { ProgressView() } else {
                            Text("Your documents don't cover this. Answer from judgement, then add it to your prep.")
                                .font(.system(size: 14)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onChange(of: item.id) { selected = nil; tab = 0 }
    }

    func note(_ text: String) -> some View {
        Text(text).font(.system(size: 12.5)).foregroundStyle(.secondary).padding(8)
    }

    func row(_ m: SectionMatch) -> some View {
        let isShown = shown?.id == m.id
        return Button { selected = m.id; model.holdLiveSuggestions(30) } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    if m.prepared { Text("ANSWER").font(.system(size: 9.5, weight: .bold, design: .monospaced)).foregroundStyle(.green) }
                    Text(m.section.parents.last ?? m.section.fileName)
                        .font(.system(size: 10.5, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                }
                Text(m.section.title).font(.system(size: 13.5, weight: .semibold)).lineLimit(2).multilineTextAlignment(.leading)
                Text(snippet(m)).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(isShown ? Color.accentColor.opacity(0.09) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .leading) {
                if isShown { RoundedRectangle(cornerRadius: 2).fill(Color.accentColor).frame(width: 3).padding(.vertical, 6) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    func snippet(_ m: SectionMatch) -> String {
        let source = m.matched.first ?? m.section.text
        return source.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespaces)
    }
}

/// The label and, when a model wrote one, the short answer to say. Document text is shown in place below.
struct AnswerStrip: View {
    var item: Asked

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if item.live {
                Text("FROM THE CONVERSATION").font(.system(size: 10, weight: .bold)).tracking(0.5)
                    .foregroundStyle(.white).padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.red.opacity(0.8), in: Capsule())
                Text("\u{2026}" + item.question).font(.system(size: 12.5)).foregroundStyle(.secondary).lineLimit(2)
            } else if let card = item.card {
                LabelPill(label: card.label, compact: true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.question).font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary).lineLimit(2)
                    if let a = card.answer, let by = card.answeredBy, by != "extract", by != Answerer.preparedAnswer {
                        Text(a).font(.system(size: 16, weight: .semibold)).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Said in your words by \(by) from the marked text").font(.system(size: 10.5)).foregroundStyle(.tertiary)
                    } else if item.answering && card.label != .notInDocs && card.answer == nil {
                        HStack(spacing: 6) { ProgressView().controlSize(.mini); Text("Writing a short version…").font(.system(size: 11.5)).foregroundStyle(.secondary) }
                    } else if let w = card.withheld {
                        Text(w).font(.system(size: 11.5)).foregroundStyle(.orange)
                    }
                }
            } else if item.answering {
                ProgressView().controlSize(.small)
                Text(item.question).font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
            } else {
                Text(item.question).font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

/// One section, shown whole and formatted as in the document, with the answer sentences marked.
struct SectionDetail: View {
    var match: SectionMatch
    var question: String
    @State private var copied = false

    var body: some View {
        let blocks = SectionText.blocks(match.section.text)
        let marked = SectionText.answerSentences(match: match, question: question)
        let firstMarked = blocks.firstIndex { SectionText.isMarked($0.text, marked) }
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(match.section.breadcrumb).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Button(copied ? "Copied" : "Copy answer") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(match.section.title + "\n\n" + match.section.text.replacingOccurrences(of: "**", with: ""), forType: .string)
                    copied = true
                }
                .controlSize(.small)
                Button { NSWorkspace.shared.open(URL(fileURLWithPath: match.section.file)) } label: { Image(systemName: "arrow.up.forward.square") }
                    .buttonStyle(.borderless).help("Open the document")
            }
            .padding(.bottom, 10)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if match.prepared {
                            Text("YOUR PREPARED ANSWER").font(.system(size: 10, weight: .bold)).tracking(0.5).foregroundStyle(.green)
                        }
                        Text(match.section.title).font(.system(size: 26, weight: .bold)).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.bottom, 4)
                        ForEach(Array(blocks.enumerated()), id: \.offset) { i, block in
                            SectionText.view(block, marked: marked, question: question, size: 16).id(i)
                        }
                    }
                    .padding(.trailing, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onAppear {
                    if let i = firstMarked, i > 2 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { withAnimation { proxy.scrollTo(i, anchor: .top) } }
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.separator.opacity(0.6)))
    }
}

// MARK: Live transcript

/// What it hears, as it hears it: a level meter per channel, the transcript, and words in progress.
struct LivePanel: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Text("LIVE").font(.system(size: 10.5, weight: .bold)).tracking(0.6).foregroundStyle(.red)
                meter(.you, "You")
                if model.sessionHearing.contains("Them") { meter(.them, "Them") }
                Spacer()
                if !model.listenStatus.isEmpty {
                    Text(model.listenStatus).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        if model.transcript.isEmpty && model.partials.isEmpty {
                            Text(model.sessionHearing.isEmpty ? "Not listening right now." : "Start talking. What it hears shows up here as you speak.")
                                .font(.system(size: 13)).foregroundStyle(.tertiary)
                        }
                        ForEach(Array(model.transcript.suffix(40).enumerated()), id: \.offset) { _, u in
                            line(u.channel, u.text, live: false)
                        }
                        ForEach([Channel.them, Channel.you], id: \.self) { c in
                            if let p = model.partials[c], !p.isEmpty { line(c, p, live: true) }
                        }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 96)
                .onChange(of: model.transcript.count) { proxy.scrollTo("end", anchor: .bottom) }
                .onChange(of: model.partials) { proxy.scrollTo("end", anchor: .bottom) }
            }
        }
        .padding(14)
        .background(Color.red.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.red.opacity(0.18)))
    }

    func meter(_ c: Channel, _ name: String) -> some View {
        let level = CGFloat(model.levels[c] ?? 0)
        return HStack(spacing: 6) {
            Image(systemName: c == .you ? "mic.fill" : "speaker.wave.2.fill").font(.system(size: 11)).foregroundStyle(.secondary)
            Text(name).font(.system(size: 11.5, weight: .medium))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.15))
                Capsule().fill(level > 0.05 ? Color.green : Color.secondary.opacity(0.4)).frame(width: max(3, 70 * level))
            }
            .frame(width: 70, height: 6)
            .animation(.linear(duration: 0.1), value: level)
        }
    }

    func line(_ c: Channel, _ text: String, live: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(c.rawValue.uppercased()).font(.system(size: 9.5, weight: .bold)).tracking(0.4)
                .foregroundStyle(c == .them ? Color.accentColor : Color.secondary)
                .frame(width: 36, alignment: .leading)
            Text(text).font(.system(size: 13.5)).foregroundStyle(live ? .secondary : .primary).italic(live)
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
    }
}
