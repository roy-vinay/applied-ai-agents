import AppKit
import SecondChairCore

/// A floating panel that takes typing without stealing focus from the call.
final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// The private window: question as heard, source card first, sayable answer second.
/// It is always excluded from screen capture and screen sharing; there is no setting to change that.
final class Overlay: NSObject, NSTextFieldDelegate {
    let panel: OverlayPanel
    var onAsk: ((String) -> Void)?

    private let status = NSTextField(labelWithString: "")
    private let heard = NSTextField(wrappingLabelWithString: "")
    private let badge = NSTextField(labelWithString: "")
    private let source = NSTextField(labelWithString: "")
    private let passage = NSTextView()
    private let passageScroll = NSScrollView()
    private let answer = NSTextField(wrappingLabelWithString: "")
    private let note = NSTextField(wrappingLabelWithString: "")
    private let query = NSTextField()
    private var shownQuestion = ""

    override init() {
        panel = OverlayPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 380),
                             styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel, .fullSizeContentView],
                             backing: .buffered, defer: false)
        super.init()
        panel.title = "Second Chair"
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.sharingType = .none   // never in a screenshot, recording or screen share
        panel.minSize = NSSize(width: 320, height: 240)
        if !panel.setFrameUsingName("SecondChairOverlay") { panel.center() }
        panel.setFrameAutosaveName("SecondChairOverlay")
        build()
        showIdle()
    }

    private func build() {
        let fx = NSVisualEffectView()
        fx.material = .hudWindow
        fx.blendingMode = .behindWindow
        fx.state = .active
        panel.contentView = fx

        status.font = .systemFont(ofSize: 10.5)
        status.textColor = .secondaryLabelColor
        status.lineBreakMode = .byTruncatingTail

        heard.font = .systemFont(ofSize: 12)
        heard.textColor = .secondaryLabelColor
        heard.maximumNumberOfLines = 2

        badge.font = .systemFont(ofSize: 11, weight: .heavy)
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 4
        badge.drawsBackground = true

        source.font = .systemFont(ofSize: 11, weight: .medium)
        source.textColor = .secondaryLabelColor
        source.lineBreakMode = .byTruncatingMiddle

        passage.isEditable = false
        passage.isSelectable = true
        passage.drawsBackground = false
        passage.font = .systemFont(ofSize: 13)
        passage.textColor = .labelColor
        passage.textContainerInset = NSSize(width: 0, height: 2)
        passage.isVerticallyResizable = true
        passage.autoresizingMask = [.width]
        passage.textContainer?.widthTracksTextView = true
        passageScroll.documentView = passage
        passageScroll.hasVerticalScroller = true
        passageScroll.drawsBackground = false
        passageScroll.borderType = .noBorder
        passageScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 70).isActive = true

        answer.font = .systemFont(ofSize: 17, weight: .semibold)
        answer.textColor = .labelColor
        answer.maximumNumberOfLines = 5

        note.font = .systemFont(ofSize: 10.5)
        note.textColor = .tertiaryLabelColor

        query.placeholderString = "Type the question (⌃⌥Space)"
        query.font = .systemFont(ofSize: 13)
        query.bezelStyle = .roundedBezel
        query.delegate = self
        query.target = self
        query.action = #selector(submit)

        let header = NSStackView(views: [badge, source])
        header.spacing = 8
        let stack = NSStackView(views: [status, heard, header, passageScroll, answer, note, query])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 30, left: 14, bottom: 12, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setHuggingPriority(.defaultLow, for: .vertical)
        passageScroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        fx.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: fx.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: fx.trailingAnchor),
            stack.topAnchor.constraint(equalTo: fx.topAnchor),
            stack.bottomAnchor.constraint(equalTo: fx.bottomAnchor),
        ])
        for v in [heard, header, passageScroll, answer, note, query, status] as [NSView] {
            v.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -28).isActive = true
        }
    }

    @objc private func submit() {
        let q = query.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        query.stringValue = ""
        onAsk?(q)
    }

    func setStatus(_ s: String) { status.stringValue = s }

    func toggle() { panel.isVisible ? panel.orderOut(nil) : panel.orderFrontRegardless() }

    func focusQuery() {
        panel.orderFrontRegardless()
        panel.makeKey()
        panel.makeFirstResponder(query)
    }

    func showIdle() {
        heard.stringValue = ""
        setBadge(nil)
        source.stringValue = ""
        passage.string = "Ask with ⌃⌥Space, or start a session from the menu bar. Answers come only from the folders you added."
        answer.stringValue = ""
        note.stringValue = ""
    }

    func showPartial(_ channel: Channel, _ text: String) {
        guard channel == .them || heard.stringValue.isEmpty || heard.stringValue.hasPrefix("…") else { return }
        heard.stringValue = "… " + String(text.suffix(140))
    }

    func showSearching(_ question: String) {
        shownQuestion = question
        heard.stringValue = "Heard: \(question)"
        panel.orderFrontRegardless()
    }

    /// The fast element: label, verbatim passages and their sources.
    func showSource(_ card: AnswerCard) {
        guard card.question == shownQuestion else { return }
        setBadge(card.label)
        let sources = card.passages.map(\.chunk.sourceLine)
        source.stringValue = sources.first.map { sources.count > 1 ? "\($0) +\(sources.count - 1) more" : $0 } ?? ""
        source.toolTip = sources.joined(separator: "\n")
        if card.passages.isEmpty {
            passage.string = "Your documents don't cover this. Answer from judgement, then add it to the prep pack."
        } else {
            let body = NSMutableAttributedString()
            for (i, hit) in card.passages.enumerated() {
                if card.passages.count > 1 {
                    body.append(NSAttributedString(string: (i == 0 ? "" : "\n\n") + hit.chunk.sourceLine + "\n",
                                                   attributes: [.font: NSFont.systemFont(ofSize: 10.5, weight: .semibold),
                                                                .foregroundColor: NSColor.secondaryLabelColor]))
                }
                body.append(NSAttributedString(string: hit.chunk.text, attributes: [.font: NSFont.systemFont(ofSize: 13),
                                                                                    .foregroundColor: NSColor.labelColor]))
            }
            passage.textStorage?.setAttributedString(body)
            passage.scrollToBeginningOfDocument(nil)
        }
        if card.label == .notInDocs, !card.passages.isEmpty {
            answer.stringValue = ""
            note.stringValue = "Closest passage shown. It does not answer the question."
        } else {
            answer.stringValue = card.label == .notInDocs ? "" : "…"
            note.stringValue = card.label == .synthesized
                ? String(format: "Made on the spot from %d passages · source in %.1fs", card.passages.count, card.sourceLatency)
                : String(format: "Source in %.1fs", card.sourceLatency)
        }
    }

    /// The slow element: arrives after the source and never replaces it.
    func showAnswer(_ card: AnswerCard) {
        guard card.question == shownQuestion else { return }
        setBadge(card.label)
        answer.stringValue = card.answer ?? ""
        var bits: [String] = []
        if card.label == .synthesized { bits.append("Made on the spot from \(card.passages.count) passages") }
        if let w = card.withheld { bits.append(w) }
        if let by = card.answeredBy { bits.append(by == "extract" ? "lifted from the passage" : "by \(by)") }
        bits.append(String(format: "source %.1fs, answer %.1fs", card.sourceLatency, card.answerLatency))
        if card.label == .notInDocs { bits.insert(card.passages.isEmpty ? "Nothing close in your docs." : "Closest passage shown; it does not answer this.", at: 0) }
        note.stringValue = bits.joined(separator: " · ")
    }

    private func setBadge(_ label: Label?) {
        guard let label else { badge.stringValue = ""; badge.backgroundColor = .clear; return }
        badge.stringValue = " \(label.rawValue) "
        switch label {
        case .grounded: badge.backgroundColor = .systemGreen; badge.textColor = .white
        case .synthesized: badge.backgroundColor = .systemOrange; badge.textColor = .black
        case .notInDocs: badge.backgroundColor = .systemGray; badge.textColor = .white
        }
    }
}
