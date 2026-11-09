import SwiftUI
import SecondChairCore

// MARK: Session setup and consent

struct SessionSetupSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var kind: SessionKind = .remote
    @State private var mode: CaptureMode = .announced
    @State private var pack: String = ""
    @State private var announcing = false
    @State private var copied = false

    var effectiveMode: CaptureMode { mode }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if announcing { announce } else { setup }
        }
        .frame(width: 560)
        .onAppear { pack = model.primaryFolder ?? model.folders.first ?? "" }
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Start an interview").font(.system(size: 20, weight: .semibold))

            section("Where") {
                Picker("", selection: $kind) {
                    ForEach(SessionKind.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden()
            }

            section("Listening") {
                VStack(spacing: 8) {
                    ForEach(CaptureMode.allCases, id: \.self) { m in
                        modeRow(m)
                    }
                }
                if mode == .announced && kind != .rehearsal && !model.gatePassed {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text(model.gate == nil
                             ? "Accuracy isn't checked yet. Answers may miss or show the wrong passage; always glance at the source."
                             : "The last accuracy check failed. Answers may miss or show the wrong passage; always glance at the source.")
                            .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10)
                    .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }
            }

            section("Answer from") {
                Picker("", selection: $pack) {
                    Text("All folders equally").tag("")
                    ForEach(model.folders, id: \.self) { f in
                        Text("\((f as NSString).lastPathComponent) first").tag(f)
                    }
                }
                .labelsHidden()
            }

            section("Before you start") {
                VStack(alignment: .leading, spacing: 5) {
                    checklist("headphones", "Wear headphones on a remote call, so your voice and theirs stay apart.")
                    checklist("moon.fill", "Turn on Do Not Disturb, so notification sounds don't get transcribed.")
                    checklist("speaker.slash.fill", "Close tabs playing audio or video.")
                    checklist("eye.slash.fill", "The window never shows up when you share your screen.")
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(effectiveMode == .announced ? "Next" : "Start") { next() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
    }

    private var announce: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Say this when the call starts").font(.system(size: 20, weight: .semibold))
            Text("\u{201C}\(ConsentGate.disclosure)\u{201D}")
                .font(.system(size: 18))
                .lineSpacing(4)
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                .textSelection(.enabled)
            HStack {
                Button(copied ? "Copied" : "Copy Sentence") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(ConsentGate.disclosure, forType: .string)
                    copied = true
                }
                Spacer()
            }
            Text("Listening to them starts only after you confirm. California needs everyone's consent, and this is asked every session.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            HStack {
                Button("Back") { announcing = false }
                Spacer()
                Button("They Objected") { begin(objection: true) }
                Button("I Said It, No Objection") { begin(objection: false) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
    }

    private func modeRow(_ m: CaptureMode) -> some View {
        let selected = mode == m
        return Button { mode = m } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(m.title).font(.system(size: 13, weight: .semibold))
                    Text(describe(m)).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .contentShape(Rectangle())
            .padding(10)
            .background(selected ? Color.accentColor.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func describe(_ m: CaptureMode) -> String {
        switch (m, kind) {
        case (.announced, .remote): return "You tell them first. Then it hears you on the mic and them through the Mac's sound."
        case (.announced, .inPerson): return "You tell them first. Then it hears the room through the mic."
        case (.announced, .rehearsal): return "Just you, practising out loud. It picks up the questions you ask yourself."
        case (.myVoiceOnly, _): return "Only your voice, only while you dictate with ⌃⌥D. Nobody else is captured."
        case (.off, _): return "Nothing is captured. Type questions into the floating window."
        }
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.system(size: 10.5, weight: .semibold)).tracking(0.5).foregroundStyle(.secondary)
            content()
        }
    }

    private func checklist(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).frame(width: 16).foregroundStyle(.secondary)
            Text(text).font(.system(size: 12))
        }
    }

    private func next() {
        if effectiveMode == .announced && kind != .rehearsal {
            announcing = true
        } else {
            model.startSession(ConsentGate(kind: kind, mode: effectiveMode), primary: pack.isEmpty ? nil : pack)
            dismiss()
        }
    }

    private func begin(objection: Bool) {
        var gate = ConsentGate(kind: kind, mode: .announced)
        gate.attest(saidIt: true, objection: objection)
        model.startSession(gate, primary: pack.isEmpty ? nil : pack)
        dismiss()
    }
}

// MARK: Review

struct ReviewSheet: View {
    @EnvironmentObject var model: AppModel
    @State private var missed: Set<Int> = []
    @State private var notes: [Int: String] = [:]

    var items: [ReviewItem] { model.review?.review ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("How did it do?").font(.system(size: 20, weight: .semibold))
                Text("Tick what it missed. Misses go into your primary prep pack as a to-do note. Fix the prep, not the tool.")
                    .font(.system(size: 12.5)).foregroundStyle(.secondary)
            }
            if items.isEmpty {
                Text("No questions came up this session.").foregroundStyle(.secondary).padding(.vertical, 20)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                            row(i, item)
                        }
                    }
                }
                .frame(maxHeight: 420)
            }
            HStack {
                Text("The transcript is deleted when you finish, unless you keep it.")
                    .font(.system(size: 11.5)).foregroundStyle(.secondary)
                Spacer()
                Button("Keep Transcript…") { save(transcript: true) }
                Button("Done") { save(transcript: false) }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 640)
    }

    private func row(_ i: Int, _ item: ReviewItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Toggle("", isOn: Binding(get: { missed.contains(i) }, set: { if $0 { missed.insert(i) } else { missed.remove(i) } }))
                .toggleStyle(.checkbox).labelsHidden()
                .help("Missed")
            VStack(alignment: .leading, spacing: 6) {
                Text(item.question).font(.system(size: 13.5, weight: .medium))
                HStack(spacing: 8) {
                    LabelPill(label: item.label, compact: true)
                    if let s = item.source { Text(s).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1) }
                }
                if let a = item.answer { Text(a).font(.system(size: 12.5)).foregroundStyle(.secondary) }
                if missed.contains(i) {
                    TextField("What should it have said? (optional)", text: Binding(get: { notes[i] ?? "" }, set: { notes[i] = $0 }))
                        .textFieldStyle(.roundedBorder).font(.system(size: 12))
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(missed.contains(i) ? Color.orange.opacity(0.07) : Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }

    private func save(transcript: Bool) {
        if let log = model.review {
            for i in log.review.indices {
                log.review[i].missed = missed.contains(i)
                log.review[i].note = notes[i] ?? ""
            }
        }
        model.finishReview(saveTranscript: transcript)
    }
}

// MARK: Gate result

struct GateResultSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let g = model.gate {
                HStack(spacing: 10) {
                    Image(systemName: g.passed ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 22)).foregroundStyle(g.passed ? Color.green : Color.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(g.passed ? "Passed every accuracy bar." : "Missed at least one accuracy bar.")
                            .font(.system(size: 18, weight: .semibold))
                        Text("\(g.rows.count) questions · \(g.date.formatted(date: .abbreviated, time: .shortened))")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                    metric("Shown answers backed by their passage", g.citationCorrectness, 0.95)
                    metric("Covered questions answered from the right place", g.groundedAccuracy, 0.85)
                    metric("Said \u{201C}not in your docs\u{201D} exactly when it should", g.refusalPrecision, 0.90)
                    GridRow {
                        Text("Invented figures")
                        Text("\(g.unsupportedNumbers)").monospacedDigit().bold()
                        bar(g.unsupportedNumbers == 0, "must be zero")
                    }
                    GridRow {
                        Text("Time to source, median / slowest 10%")
                        Text(String(format: "%.1fs / %.1fs", g.medianLatency, g.p90Latency)).monospacedDigit().bold()
                        bar(g.medianLatency < 3 && g.p90Latency < 5, "under 3s / 5s")
                    }
                }
                .font(.system(size: 13))
                let misses = g.rows.filter { $0.covered ? !($0.correctSource && $0.citationOK) : !$0.correctRefusal }
                if !misses.isEmpty {
                    Text("Questions to fix").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(misses.enumerated()), id: \.offset) { _, r in
                                HStack(spacing: 8) {
                                    LabelPill(label: r.label, compact: true)
                                    Text(r.question).font(.system(size: 12.5)).lineLimit(1)
                                    Spacer()
                                    Text(r.covered ? "expected an answer" : "expected not in docs").font(.system(size: 11)).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 180)
                }
                if !g.passed && model.gateFailures >= 2 {
                    Text("Two misses in a row. Add the missing answers to your prep, then check again.")
                        .font(.system(size: 12)).foregroundStyle(.orange)
                }
            }
            HStack {
                Button("Open Full Report") { NSWorkspace.shared.open(Library.supportDirectory.appendingPathComponent("gate-report.md")) }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 600)
    }

    private func metric(_ name: String, _ value: Double, _ bar: Double) -> some View {
        GridRow {
            Text(name)
            Text(String(format: "%.0f%%", value * 100)).monospacedDigit().bold()
            self.bar(value >= bar, String(format: "needs %.0f%%", bar * 100))
        }
    }

    private func bar(_ ok: Bool, _ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill").foregroundStyle(ok ? Color.green : Color.red)
            Text(text).foregroundStyle(.secondary).font(.system(size: 11.5))
        }
    }
}

// MARK: Settings

struct SettingsSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("engine") private var engine = Settings.Engine.analyzer.rawValue
    @AppStorage("embeddingChoice") private var embedding = Models.EmbeddingChoice.ollama.rawValue
    @AppStorage("qualityModel") private var quality = "qwen3:8b"
    @AppStorage("embeddingModel") private var embedModel = "embeddinggemma"
    @State private var checking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Settings").font(.system(size: 20, weight: .semibold))

            group("Local models", "Everything runs on this Mac. Nothing is sent anywhere.") {
                status(model.fastReady, "Quick answers: Apple Intelligence", model.fastReady ? "Ready" : "Off. Turn on Apple Intelligence in System Settings.")
                status(model.qualityReady, "Answers from several passages: \(quality)", model.qualityReady ? "Ready" : "Not running. In Terminal: ollama pull \(quality)")
                HStack {
                    Text("Model").frame(width: 120, alignment: .leading)
                    TextField("qwen3:8b", text: $quality).textFieldStyle(.roundedBorder).frame(width: 200)
                }
            }

            group("Meaning search", "Finds passages when the question uses different words than your notes.") {
                Picker("", selection: $embedding) {
                    Text("EmbeddingGemma via Ollama (best)").tag(Models.EmbeddingChoice.ollama.rawValue)
                    Text("Apple built-in (no setup)").tag(Models.EmbeddingChoice.apple.rawValue)
                    Text("Off: keyword search only").tag(Models.EmbeddingChoice.none.rawValue)
                }
                .pickerStyle(.radioGroup).labelsHidden()
            }

            group("Transcription", "Used during sessions.") {
                Picker("", selection: $engine) {
                    ForEach(Settings.Engine.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.radioGroup).labelsHidden()
                if engine == Settings.Engine.whisper.rawValue {
                    Text("Start it with: whisper-server -m <model> --port \(WhisperServerEngine.port)")
                        .font(.system(size: 11.5, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }

            HStack {
                Button(checking ? "Checking…" : "Recheck Models") {
                    checking = true
                    Task { await model.discoverModels(); checking = false }
                }
                .disabled(checking)
                Spacer()
                Button("Done") {
                    Task { await model.discoverModels() }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    private func group<C: View>(_ title: String, _ subtitle: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 13, weight: .semibold))
            Text(subtitle).font(.system(size: 11.5)).foregroundStyle(.secondary)
            content()
        }
    }

    private func status(_ ok: Bool, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle.dashed").foregroundStyle(ok ? Color.green : Color.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12.5))
                Text(detail).font(.system(size: 11.5)).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
    }
}
