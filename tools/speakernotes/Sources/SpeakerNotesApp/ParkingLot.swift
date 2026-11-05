import AppKit

/// An audience question you promised to come back to.
struct ParkedQuestion: Codable, Equatable, Identifiable {
    var id = UUID()
    var text: String
    var slide: Int        // 1 for the first slide
    var slideTitle: String
    var date = Date()
    var answered = false
}

/// Parked questions are kept per notes file.
enum ParkingStore {
    private static func key(for url: URL?) -> String { "parked:" + (url?.path ?? "scratch") }

    static func load(for url: URL?) -> [ParkedQuestion] {
        guard let data = UserDefaults.standard.data(forKey: key(for: url)),
              let items = try? JSONDecoder().decode([ParkedQuestion].self, from: data) else { return [] }
        return items
    }

    static func save(_ items: [ParkedQuestion], for url: URL?) {
        UserDefaults.standard.set(try? JSONEncoder().encode(items), forKey: key(for: url))
    }

    /// The list as plain text, for a follow-up email.
    static func text(_ items: [ParkedQuestion]) -> String {
        items.map { "\($0.answered ? "[x]" : "[ ]") \($0.text)  (slide \($0.slide): \($0.slideTitle))" }
            .joined(separator: "\n")
    }
}

private func label(_ text: String, size: CGFloat = 11, weight: NSFont.Weight = .semibold,
                   color: NSColor = Theme.secondary) -> NSTextField {
    let l = NSTextField(labelWithString: text)
    l.font = .systemFont(ofSize: size, weight: weight)
    l.textColor = color
    return l
}

/// Park a question in one line, and see the ones still waiting.
final class ParkingViewController: NSViewController, NSTextFieldDelegate {
    var onPark: ((String) -> Void)?
    var onToggle: ((UUID) -> Void)?
    var onRemove: ((UUID) -> Void)?
    var onCopy: (() -> Void)?
    var onClearAnswered: (() -> Void)?

    private let field = NSTextField()
    private let list = NSStackView()
    private let header = label("WAITING", size: 10)
    private let copyButton = NSButton(title: "Copy All", target: nil, action: nil)
    private let clearButton = NSButton(title: "Clear Answered", target: nil, action: nil)
    private let empty = label("Nothing parked yet. Press ⌃⌥P during a talk to park a question.", size: 11.5, weight: .regular)

    override func loadView() {
        let title = label("Park a question", size: 13, color: Theme.text)
        let hint = label("Press Return to park it with this slide. You'll see the list at the end.", size: 11.5, weight: .regular)
        hint.lineBreakMode = .byWordWrapping
        hint.maximumNumberOfLines = 2
        hint.preferredMaxLayoutWidth = 320
        field.placeholderString = "e.g. How do you handle EDI?"
        field.font = .systemFont(ofSize: 13)
        field.bezelStyle = .roundedBezel
        field.delegate = self
        field.target = self
        field.action = #selector(park)
        field.widthAnchor.constraint(equalToConstant: 320).isActive = true

        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 6
        for (b, sel) in [(copyButton, #selector(copyAll)), (clearButton, #selector(clearAnswered))] {
            b.target = self
            b.action = sel
            b.isBordered = false
            b.contentTintColor = Theme.accent
            b.font = .systemFont(ofSize: 11.5, weight: .medium)
        }
        let top = NSStackView(views: [header, NSView(), clearButton, copyButton])
        top.widthAnchor.constraint(equalToConstant: 320).isActive = true
        empty.lineBreakMode = .byWordWrapping
        empty.preferredMaxLayoutWidth = 320

        let stack = NSStackView(views: [title, hint, field, top, list, empty])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.setCustomSpacing(4, after: title)
        stack.setCustomSpacing(16, after: field)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),
            container.widthAnchor.constraint(equalToConstant: 352),
        ])
        view = container
    }

    func prepare(prefill: String) {
        _ = view
        field.stringValue = prefill
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }

    func setItems(_ items: [ParkedQuestion]) {
        _ = view
        list.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let waiting = items.filter { !$0.answered }.count
        header.stringValue = items.isEmpty ? "WAITING" : "WAITING · \(waiting) OF \(items.count)"
        empty.isHidden = !items.isEmpty
        list.isHidden = items.isEmpty
        copyButton.isHidden = items.isEmpty
        clearButton.isHidden = !items.contains { $0.answered }
        for item in items {
            let box = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggle(_:)))
            box.state = item.answered ? .on : .off
            box.identifier = NSUserInterfaceItemIdentifier(item.id.uuidString)
            box.toolTip = item.answered ? "Answered" : "Mark answered"
            let text = label(item.text, size: 12.5, weight: .medium, color: item.answered ? Theme.tertiary : Theme.text)
            text.lineBreakMode = .byTruncatingTail
            text.toolTip = item.text
            text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            let where_ = label("Slide \(item.slide)", size: 11, weight: .medium)
            where_.toolTip = item.slideTitle
            let remove = NSButton(image: NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Remove")!,
                                  target: self, action: #selector(remove(_:)))
            remove.isBordered = false
            remove.contentTintColor = Theme.tertiary
            remove.identifier = NSUserInterfaceItemIdentifier(item.id.uuidString)
            let row = NSStackView(views: [box, text, where_, remove])
            row.spacing = 6
            row.widthAnchor.constraint(equalToConstant: 320).isActive = true
            list.addArrangedSubview(row)
        }
    }

    @objc private func park() {
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        field.stringValue = ""
        onPark?(text)
    }

    private func id(_ sender: NSButton) -> UUID? { sender.identifier.flatMap { UUID(uuidString: $0.rawValue) } }
    @objc private func toggle(_ sender: NSButton) { if let id = id(sender) { onToggle?(id) } }
    @objc private func remove(_ sender: NSButton) { if let id = id(sender) { onRemove?(id) } }
    @objc private func copyAll() { onCopy?() }
    @objc private func clearAnswered() { onClearAnswered?() }
}

/// A Spotlight-style box for parking a question without leaving your slides: it takes your typing while
/// Keynote or your browser stays the active app, so Return parks the question and you're right back where you were.
final class QuickParkPanel: NSPanel, NSTextFieldDelegate {
    var onPark: ((String) -> Void)?
    private let field = NSTextField()
    private let context = NSTextField(labelWithString: "")

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 460, height: 112),
                   styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView], backing: .buffered, defer: false)
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] { standardWindowButton(kind)?.isHidden = true }
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        isReleasedWhenClosed = false
        isMovableByWindowBackground = true
        appearance = NSAppearance(named: .darkAqua)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true

        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 14
        background.layer?.masksToBounds = true
        background.layer?.borderWidth = 1
        background.layer?.borderColor = Theme.accent.withAlphaComponent(0.6).cgColor
        contentView = background

        let icon = NSImageView(image: NSImage(systemSymbolName: "tray.and.arrow.down.fill", accessibilityDescription: nil)!
            .withSymbolConfiguration(.init(pointSize: 15, weight: .semibold))!)
        icon.contentTintColor = Theme.accent
        let title = label("Park a question", size: 13, color: Theme.text)
        context.font = .systemFont(ofSize: 11.5, weight: .medium)
        context.textColor = Theme.secondary
        context.lineBreakMode = .byTruncatingTail
        let head = NSStackView(views: [icon, title, context])
        head.spacing = 8

        field.placeholderString = "Type the question in a few words"
        field.font = .systemFont(ofSize: 16)
        field.bezelStyle = .roundedBezel
        field.focusRingType = .none
        field.delegate = self
        let hint = label("Return parks it  ·  Esc cancels  ·  Hidden from your screen share", size: 11, weight: .regular)

        let stack = NSStackView(views: [head, field, hint])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 9
        stack.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: background.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: background.bottomAnchor, constant: -12),
            field.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Shows the box over the notes window (or at the top of the screen), ready to type.
    func present(prefill: String, slide: String, over notes: NSWindow, hiddenFromShare: Bool) {
        sharingType = hiddenFromShare ? .none : .readOnly
        context.stringValue = slide
        field.stringValue = prefill
        let f = notes.isVisible ? notes.frame : (NSScreen.main?.visibleFrame ?? .zero)
        let size = frame.size
        var origin = NSPoint(x: f.midX - size.width / 2, y: f.maxY - size.height - 56)
        if let screen = (notes.screen ?? NSScreen.main)?.visibleFrame {
            origin.x = min(max(origin.x, screen.minX + 8), screen.maxX - size.width - 8)
            origin.y = min(max(origin.y, screen.minY + 8), screen.maxY - size.height - 8)
        }
        setFrameOrigin(origin)
        makeKeyAndOrderFront(nil)
        makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            orderOut(nil)
            return true
        }
        if selector == #selector(NSResponder.insertNewline(_:)) {
            let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            orderOut(nil)
            if !text.isEmpty { onPark?(text) }
            return true
        }
        return false
    }
}
