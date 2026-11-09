import AppKit
import SwiftUI
import SecondChairCore

/// A floating panel that takes typing without stealing focus from the call.
final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// The interview window. Always excluded from screen capture and screen sharing; there is no setting to change that.
@MainActor
final class Overlay {
    let panel: OverlayPanel

    init(model: AppModel) {
        panel = OverlayPanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 420),
                             styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .fullSizeContentView],
                             backing: .buffered, defer: false)
        panel.title = "Second Chair"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.sharingType = .none   // never in a screenshot, recording or screen share
        panel.minSize = NSSize(width: 340, height: 260)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.contentView = NSHostingView(rootView: OverlayView().environmentObject(model))
        if !panel.setFrameUsingName("SecondChairOverlay2"), let screen = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: screen.maxX - 460, y: screen.maxY - 440))
        }
        panel.setFrameAutosaveName("SecondChairOverlay2")
    }

    func toggle() { panel.isVisible ? panel.orderOut(nil) : panel.orderFrontRegardless() }

    func show() { panel.orderFrontRegardless() }

    func focusQuery(_ model: AppModel) {
        panel.orderFrontRegardless()
        panel.makeKey()
        model.focusOverlay()
    }
}

/// Built for a glance: what it heard, the label, the answer in big type, the passage it came from.
struct OverlayView: View {
    @EnvironmentObject var model: AppModel
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Circle().fill(model.sessionActive ? Color.red : Color.secondary.opacity(0.4)).frame(width: 7, height: 7)
                Text(statusText).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "eye.slash").font(.system(size: 10)).foregroundStyle(.tertiary)
                    .help("Hidden from screen sharing")
            }
            .padding(.top, 4)

            if !model.heardPartial.isEmpty {
                Text("… " + model.heardPartial).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
            }

            if let item = model.overlayItem {
                OverlayAnswer(item: item)
            } else {
                Spacer()
                Text("Questions show up here.\nType one below, or start a session in the main window.")
                    .font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                Spacer()
            }

            TextField("Type a question  ⌃⌥Space", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                .focused($focused)
                .onSubmit { model.ask(draft); draft = "" }
        }
        .padding(.horizontal, 14)
        .padding(.top, 18)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onChange(of: model.overlayFocusTick) { focused = true }
    }

    var statusText: String {
        guard model.sessionActive else { return "Second Chair" }
        return model.sessionHearing.isEmpty ? "Session · not listening" : "Hearing " + model.sessionHearing.joined(separator: " + ")
    }
}

struct OverlayAnswer: View {
    var item: Asked

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(item.question).font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary).lineLimit(2)
            if let card = item.card {
                HStack(spacing: 8) {
                    LabelPill(label: card.label, compact: true)
                    if let c = card.passages.first?.chunk {
                        Text(c.headings.last.map { "\(c.fileName) › \($0)" } ?? c.fileName).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        answerText(card)
                        ForEach(Array(card.passages.enumerated()), id: \.offset) { _, hit in
                            passage(hit, card: card)
                        }
                    }
                }
            } else {
                HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Searching…").foregroundStyle(.secondary) }
                Spacer()
            }
        }
    }

    @ViewBuilder func answerText(_ card: AnswerCard) -> some View {
        if let a = card.answer {
            Text(a).font(.system(size: 19, weight: .semibold)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
        } else if item.answering && card.label != .notInDocs {
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Writing…").foregroundStyle(.secondary) }
                .font(.system(size: 13))
        } else if card.label == .notInDocs {
            Text("Not in your docs. Answer from judgement.").font(.system(size: 17, weight: .semibold)).foregroundStyle(.secondary)
        } else if let w = card.withheld {
            Text(w).font(.system(size: 12)).foregroundStyle(.orange)
        }
    }

    func passage(_ hit: Hit, card: AnswerCard) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if card.passages.count > 1 {
                Text(hit.chunk.sourceLine).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.secondary)
            }
            Text(Highlight.passage(hit.chunk.text, question: item.question, size: 13))
                .font(.system(size: 13)).lineSpacing(2)
                .opacity(card.label == .notInDocs ? 0.65 : 1)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }
}
