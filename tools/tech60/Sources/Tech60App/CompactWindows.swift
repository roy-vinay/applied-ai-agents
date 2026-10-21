import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI
import Tech60Core

// The ticker and the dot: two small windows the card can collapse into (PRD section 6A).
// Card, ticker, and dot each remember their own place. The ticker and dot stay above other windows
// and on every Space by default, never take keyboard focus, and are left out of screen sharing.

/// Settings for the ticker and the dot, saved between launches.
@MainActor
final class CompactSettings: ObservableObject {
    private let save: Bool
    @Published var alwaysOnTop: Bool { didSet { store(alwaysOnTop, "compactAlwaysOnTop") } }
    @Published var allSpaces: Bool { didSet { store(allSpaces, "compactAllSpaces") } }
    /// Leave every Tech60 window out of screen sharing and recordings (SHARE-01).
    @Published var hideFromSharing: Bool { didSet { store(hideFromSharing, "hideFromSharing") } }
    /// Seconds each headline stays on the ticker.
    let rotateSeconds: Double

    init(save: Bool) {
        self.save = save
        let d = UserDefaults.standard
        alwaysOnTop = save ? (d.object(forKey: "compactAlwaysOnTop") as? Bool ?? true) : true
        allSpaces = save ? (d.object(forKey: "compactAllSpaces") as? Bool ?? true) : true
        // Screenshots in CI need to capture the windows; everywhere else they are hidden from sharing.
        let allowCapture = ProcessInfo.processInfo.arguments.contains("--allow-capture")
        hideFromSharing = allowCapture ? false : (save ? (d.object(forKey: "hideFromSharing") as? Bool ?? true) : true)
        let seconds = d.double(forKey: "tickerSeconds")
        rotateSeconds = seconds >= 3 ? seconds : 8
    }

    private func store(_ value: Bool, _ key: String) {
        if save { UserDefaults.standard.set(value, forKey: key) }
    }
}

extension NSScreen {
    /// A stable name for this display, used to remember positions per display.
    var tech60Key: String { "\(localizedName) \(Int(frame.width))x\(Int(frame.height))" }
}

/// A borderless panel that never becomes key, so typing stays in the app you're using.
final class CompactPanel: NSPanel {
    init(size: NSSize) {
        super.init(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false // Tech60 moves it, so it can snap.
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class CompactController: ObservableObject {
    let model: AppModel
    let settings: CompactSettings
    let card: NSPanel
    private(set) var state: PresentationState { didSet { saveState() } }

    @Published var isInteracting = false
    @Published private(set) var snapTarget: Dock?
    @Published private(set) var isDragging = false
    /// Story rows the dot already knew about; anything else makes it glow.
    @Published private(set) var dotBaseline: Set<String> = []

    private var tickerBook: PlacementBook
    private var dotBook: PlacementBook
    private lazy var ticker: CompactPanel = makePanel(size: NSSize(width: 620, height: 36), view: AnyView(TickerView(model: model, controller: self)))
    private lazy var dot: CompactPanel = makePanel(size: NSSize(width: 44, height: 44), view: AnyView(DotView(model: model, controller: self)))
    private lazy var hints: [Dock: CompactPanel] = [.top: makeHint(.top), .bottom: makeHint(.bottom)]
    private var observers: [Any] = []
    /// Other Tech60 windows (settings) that follow the screen-sharing setting.
    var sharedExtras: [NSWindow] = []
    private var bag: Set<AnyCancellable> = []
    private let hotKeys = HotKeys()

    init(model: AppModel, card: NSPanel) {
        self.model = model
        self.card = card
        let save = !model.isDemo
        settings = CompactSettings(save: save)
        let d = UserDefaults.standard
        func load<T: Decodable>(_ key: String) -> T? {
            save ? d.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) } : nil
        }
        tickerBook = load("tickerPlacement") ?? PlacementBook()
        dotBook = load("dotPlacement") ?? PlacementBook()
        var start: PresentationState = load("presentation") ?? PresentationState()
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--ticker") { start = PresentationState(current: .ticker, previous: .card) }
        if args.contains("--dot") { start = PresentationState(current: .dot, previous: .ticker) }
        state = start

        settings.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.applySettings() }
        }.store(in: &bag)
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.placeCurrent() }
        })
        hotKeys.register(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(cmdKey | shiftKey)) { [weak self] in
            MainActor.assumeIsolated { self?.toggleTicker() }
        }
        hotKeys.register(keyCode: UInt32(kVK_ANSI_Period), modifiers: UInt32(cmdKey | shiftKey)) { [weak self] in
            MainActor.assumeIsolated { self?.toggleDot() }
        }
    }

    // MARK: Switching

    /// Shows whichever presentation was showing last time.
    func showCurrent() {
        applySettings()
        if state.current == .dot { dotBaseline = Set(model.clusters.map(\.id)) }
        display(state.current)
    }

    func collapseToTicker() { go(.ticker) }

    func shrinkToDot() {
        dotBaseline = Set(model.clusters.map(\.id))
        go(.dot)
    }

    /// Ticker to card; dot to whatever it came from.
    func expand() {
        var s = state
        s.expand()
        state = s
        display(state.current)
    }

    /// Straight back to the card, from the ticker or the dot.
    func showCard() {
        var s = state
        s.show(.card)
        state = s
        display(.card)
    }

    /// ⌘⇧T: collapse the card to the ticker, or bring the card back.
    func toggleTicker() { state.current == .card ? collapseToTicker() : expand() }

    /// ⌘⇧.: shrink to the dot, or restore from it.
    func toggleDot() { state.current == .dot ? expand() : shrinkToDot() }

    var current: Presentation { state.current }

    var isVisible: Bool { window(for: state.current).isVisible }

    /// The menu bar's show/hide: hides whichever window is showing, or shows it again.
    func toggleVisible() {
        let w = window(for: state.current)
        if w.isVisible { w.orderOut(nil) } else { display(state.current) }
    }

    private func go(_ next: Presentation) {
        // The ticker and dot open on the display the card was on, the first time.
        if let screen = window(for: state.current).screen, next != .card {
            var book = next == .ticker ? tickerBook : dotBook
            if book.byDisplay.isEmpty {
                book.lastDisplay = screen.tech60Key
                if next == .ticker { tickerBook = book } else { dotBook = book }
            }
        }
        var s = state
        s.show(next)
        state = s
        display(next)
    }

    private func display(_ p: Presentation) {
        for other in [Presentation.card, .ticker, .dot] where other != p {
            window(for: other).orderOut(nil)
        }
        if p != .card { placeCurrent() }
        window(for: p).orderFrontRegardless()
    }

    private func window(for p: Presentation) -> NSWindow {
        switch p {
        case .card: return card
        case .ticker: return ticker
        case .dot: return dot
        }
    }

    // MARK: Placement

    private func screen(for book: PlacementBook) -> NSScreen? {
        let screens = NSScreen.screens
        guard let main = NSScreen.main ?? screens.first else { return nil }
        let key = book.display(connected: screens.map(\.tech60Key), main: main.tech60Key)
        return screens.first { $0.tech60Key == key } ?? main
    }

    /// Puts the ticker or dot where it was last left on its display, always fully on screen.
    func placeCurrent() {
        switch state.current {
        case .card: return
        case .ticker: place(ticker, book: tickerBook, firstUse: .firstUse)
        case .dot: place(dot, book: dotBook, firstUse: SpotOnScreen(dock: .float, centerX: 0.97, bottomY: 0.03))
        }
    }

    private func place(_ panel: NSPanel, book: PlacementBook, firstUse: SpotOnScreen) {
        guard let screen = screen(for: book) else { return }
        let spot = book.byDisplay[screen.tech60Key] ?? firstUse
        let width = panel === ticker ? min(620, screen.visibleFrame.width - 32) : panel.frame.width
        let frame = Placement.frame(for: spot, size: CGSize(width: width, height: panel.frame.height), in: screen.visibleFrame)
        panel.setFrame(frame, display: true)
    }

    func dock(_ d: Dock) {
        guard let screen = ticker.screen ?? NSScreen.main else { return }
        let spot = Placement.spot(docking: d, from: tickerBook.spot(on: screen.tech60Key))
        tickerBook.remember(spot, on: screen.tech60Key)
        saveBooks()
        placeCurrent()
    }

    func resetPosition() {
        if state.current == .dot { dotBook = PlacementBook() } else { tickerBook = PlacementBook() }
        saveBooks()
        placeCurrent()
    }

    var tickerDock: Dock? {
        guard let screen = ticker.screen else { return nil }
        return tickerBook.byDisplay[screen.tech60Key]?.dock ?? .bottom
    }

    // MARK: Dragging

    func dragBegan(_ panel: NSWindow) {
        isDragging = true
        isInteracting = true
    }

    func dragMoved(_ panel: NSWindow, optionHeld: Bool) {
        guard panel === ticker, let screen = panel.screen else { return }
        let target = Placement.snapTarget(for: panel.frame, in: screen.visibleFrame, snapping: !optionHeld)
        if target != snapTarget { snapTarget = target }
        showHints(on: screen, visible: !optionHeld)
    }

    func dragEnded(_ panel: NSWindow, optionHeld: Bool) {
        isDragging = false
        isInteracting = false
        snapTarget = nil
        hints.values.forEach { $0.orderOut(nil) }
        guard let screen = panel.screen ?? NSScreen.main else { return }
        let isTicker = panel === ticker
        let spot = Placement.spot(afterDropping: panel.frame, in: screen.visibleFrame, snapping: isTicker && !optionHeld)
        if isTicker { tickerBook.remember(spot, on: screen.tech60Key) } else { dotBook.remember(spot, on: screen.tech60Key) }
        saveBooks()
        placeCurrent()
    }

    private func showHints(on screen: NSScreen, visible: Bool) {
        for (edge, hint) in hints {
            guard visible else { hint.orderOut(nil); continue }
            let v = screen.visibleFrame
            let h: CGFloat = 44
            let y = edge == .top ? v.maxY - h - 4 : v.minY + 4
            hint.setFrame(NSRect(x: v.minX + 8, y: y, width: v.width - 16, height: h), display: true)
            hint.orderFront(nil)
        }
        ticker.orderFrontRegardless()
    }

    // MARK: Options menu

    func showOptions() {
        isInteracting = true
        defer { isInteracting = false }
        let menu = NSMenu()
        func item(_ title: String, on: Bool? = nil, enabled: Bool = true, _ action: @escaping () -> Void) {
            let i = ClosureMenuItem(title: title, action: action)
            if let on { i.state = on ? .on : .off }
            i.isEnabled = enabled
            menu.addItem(i)
        }
        if state.current == .ticker {
            let header = NSMenuItem(title: "Position", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            let d = tickerDock
            item("Dock to top edge", on: d == .top) { [weak self] in self?.dock(.top) }
            item("Dock to bottom edge", on: d == .bottom) { [weak self] in self?.dock(.bottom) }
            item("Float (drag anywhere)", on: d == .float) { [weak self] in self?.dock(.float) }
            menu.addItem(.separator())
        }
        item("Always on top", on: settings.alwaysOnTop) { [weak self] in self?.settings.alwaysOnTop.toggle() }
        item("Show on all Spaces", on: settings.allSpaces) { [weak self] in self?.settings.allSpaces.toggle() }
        item("Hide from screen sharing", on: settings.hideFromSharing) { [weak self] in self?.settings.hideFromSharing.toggle() }
        item("Reset position") { [weak self] in self?.resetPosition() }
        menu.addItem(.separator())
        if state.current == .ticker {
            item("Shrink to dot  ⌘⇧.") { [weak self] in self?.shrinkToDot() }
        }
        item(state.current == .dot && state.previous == .ticker ? "Back to ticker" : "Expand to card  ⌘⇧T") { [weak self] in self?.expand() }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    // MARK: Settings

    func applySettings() {
        let level: NSWindow.Level = settings.alwaysOnTop ? .statusBar : .normal
        var behavior: NSWindow.CollectionBehavior = [.fullScreenAuxiliary, .ignoresCycle]
        behavior.insert(settings.allSpaces ? .canJoinAllSpaces : .managed)
        for panel in [ticker, dot] {
            panel.level = level
            panel.collectionBehavior = behavior
        }
        for hint in hints.values { hint.level = .statusBar; hint.collectionBehavior = behavior }
        applySharing()
    }

    /// Leaves every Tech60 window out of screen captures, so viewers of a share never see them (SHARE-01).
    func applySharing(extra: [NSWindow] = []) {
        let type: NSWindow.SharingType = settings.hideFromSharing ? .none : .readOnly
        for w in [card, ticker, dot] + Array(hints.values) + extra + sharedExtras { w.sharingType = type }
    }

    // MARK: Saving

    private func saveState() {
        guard !model.isDemo, let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: "presentation")
    }

    private func saveBooks() {
        guard !model.isDemo else { return }
        let e = JSONEncoder()
        if let t = try? e.encode(tickerBook) { UserDefaults.standard.set(t, forKey: "tickerPlacement") }
        if let d = try? e.encode(dotBook) { UserDefaults.standard.set(d, forKey: "dotPlacement") }
    }

    // MARK: Windows

    private func makePanel(size: NSSize, view: AnyView) -> CompactPanel {
        let panel = CompactPanel(size: size)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        panel.level = settings.alwaysOnTop ? .statusBar : .normal
        panel.sharingType = settings.hideFromSharing ? .none : .readOnly
        return panel
    }

    private func makeHint(_ edge: Dock) -> CompactPanel {
        let panel = CompactPanel(size: NSSize(width: 400, height: 44))
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.contentView = NSHostingView(rootView: SnapHintView(edge: edge, controller: self))
        panel.sharingType = settings.hideFromSharing ? .none : .readOnly
        return panel
    }
}

/// A menu item that runs a closure.
final class ClosureMenuItem: NSMenuItem {
    private let run: () -> Void
    init(title: String, action: @escaping () -> Void) {
        run = action
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }
    @available(*, unavailable) required init(coder: NSCoder) { fatalError() }
    @objc private func fire() { run() }
}

// MARK: - Views

/// The ticker: a pill with one headline at a time.
struct TickerView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var controller: CompactController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0
    @State private var elapsed = 0.0
    @State private var tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var hovering = false

    private var rows: [StoryCluster] { Array(model.visibleClusters.prefix(20)) }
    private var row: StoryCluster? { rows.isEmpty ? nil : rows[index % rows.count] }
    private var paused: Bool { hovering || controller.isInteracting || model.isPaused }

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 9) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.secondary)
                    .frame(width: 16)
                if paused {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Palette.accent)
                } else {
                    Circle().fill(Palette.accent).frame(width: 7, height: 7)
                }
                if let row {
                    Text(row.lead.sourceName.uppercased())
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                        .fixedSize()
                    Text(row.lead.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .underline(hovering)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .id(row.id)
                        .transition(reduceMotion ? .identity : .opacity)
                    Spacer(minLength: 4)
                    Text("\(index % rows.count + 1) / \(rows.count)")
                        .font(.system(size: 10.5).monospacedDigit())
                        .foregroundStyle(Palette.secondary)
                        .fixedSize()
                } else {
                    Text(model.isRefreshing ? "Checking sources" : "No stories yet")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.secondary)
                    Spacer()
                }
            }
            .allowsHitTesting(false)
            .padding(.leading, 10)
            .frame(maxHeight: .infinity)
            .background(GrabSurface(
                label: row.map { "Tech60 ticker: \($0.lead.title). Click to expand, Command-click to open the story." } ?? "Tech60 ticker. Click to expand.",
                tooltip: row?.lead.title,
                onClick: { flags in
                    if flags.contains(.command), let row { model.open(row.lead) } else { controller.expand() }
                },
                onHover: { hovering = $0 },
                controller: controller))

            PillButton(symbol: "ellipsis", label: "Ticker options") { controller.showOptions() }
            PillButton(symbol: "arrow.up.left.and.arrow.down.right", label: "Expand to card") { controller.expand() }
                .padding(.trailing, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Capsule().fill(Palette.paper))
        .overlay(Capsule().strokeBorder(Palette.rule, lineWidth: 1))
        .clipShape(Capsule())
        .onReceive(tick) { _ in
            guard !paused, rows.count > 1 else { return }
            elapsed += 1
            guard elapsed >= controller.settings.rotateSeconds else { return }
            elapsed = 0
            if reduceMotion { index += 1 } else { withAnimation(.easeInOut(duration: 0.35)) { index += 1 } }
        }
    }
}

/// The dot: a small circle that glows when stories arrive.
struct DotView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var controller: CompactController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bright = false

    private var hasNew: Bool { model.clusters.contains { !controller.dotBaseline.contains($0.id) } }

    var body: some View {
        ZStack {
            if hasNew {
                Circle().fill(Palette.accent.opacity(0.16)).frame(width: 34, height: 34)
                Circle().fill(Palette.accent.opacity(0.32)).frame(width: 26, height: 26)
                    .opacity(reduceMotion ? 1 : (bright ? 1 : 0.45))
            }
            Circle()
                .fill(hasNew ? Palette.accent : Palette.secondary)
                .frame(width: 16, height: 16)
                .overlay(Circle().strokeBorder(Palette.paper.opacity(0.7), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
        }
        .frame(width: 44, height: 44)
        .allowsHitTesting(false)
        .background(GrabSurface(
            label: hasNew ? "Tech60, new stories. Click to restore." : "Tech60. Click to restore.",
            tooltip: model.visibleClusters.first.map { hasNew ? "New: \($0.lead.title)" : $0.lead.title },
            onClick: { _ in controller.expand() },
            onHover: { _ in },
            controller: controller))
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { bright = true }
        }
    }
}

/// The highlighted strip at the top or bottom edge while the ticker is dragged.
struct SnapHintView: View {
    let edge: Dock
    @ObservedObject var controller: CompactController
    var body: some View {
        let active = controller.snapTarget == edge
        RoundedRectangle(cornerRadius: 10)
            .fill(Palette.accent.opacity(active ? 0.22 : 0.08))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Palette.accent.opacity(active ? 0.9 : 0.45), style: StrokeStyle(lineWidth: 2, dash: active ? [] : [6, 4])))
            .overlay(Text(active ? "Release to snap to the \(edge.rawValue) edge" : "Snap to \(edge.rawValue) edge")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.ink))
    }
}

struct PillButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10.5, weight: .semibold))
                .frame(width: 26, height: 26)
                .background(Circle().fill(Palette.chip))
                .foregroundStyle(Palette.body)
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// Click, ⌘-click, or drag the window it sits in. Drags move the window by hand so Tech60 can snap it.
struct GrabSurface: NSViewRepresentable {
    let label: String
    let tooltip: String?
    let onClick: (NSEvent.ModifierFlags) -> Void
    let onHover: (Bool) -> Void
    let controller: CompactController

    func makeNSView(context: Context) -> GrabView { GrabView() }

    func updateNSView(_ view: GrabView, context: Context) {
        view.onClick = onClick
        view.onHover = onHover
        view.controller = controller
        view.toolTip = tooltip
        view.setAccessibilityLabel(label)
    }
}

final class GrabView: NSView {
    var onClick: (NSEvent.ModifierFlags) -> Void = { _ in }
    var onHover: (Bool) -> Void = { _ in }
    weak var controller: CompactController?
    private var start: NSPoint?
    private var origin: NSPoint?
    private var dragging = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }
    override func mouseEntered(with event: NSEvent) { onHover(true) }
    override func mouseExited(with event: NSEvent) { onHover(false) }

    override func mouseDown(with event: NSEvent) {
        start = NSEvent.mouseLocation
        origin = window?.frame.origin
        dragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start, let origin, let window else { return }
        let p = NSEvent.mouseLocation
        let dx = p.x - start.x, dy = p.y - start.y
        if !dragging {
            guard hypot(dx, dy) >= 4 else { return }
            dragging = true
            controller?.dragBegan(window)
        }
        window.setFrameOrigin(NSPoint(x: origin.x + dx, y: origin.y + dy))
        let option = event.modifierFlags.contains(.option)
        controller?.dragMoved(window, optionHeld: option)
    }

    override func mouseUp(with event: NSEvent) {
        defer { start = nil; dragging = false }
        if dragging, let window {
            let option = event.modifierFlags.contains(.option)
            controller?.dragEnded(window, optionHeld: option)
        } else {
            onClick(event.modifierFlags)
        }
    }

    override func accessibilityPerformPress() -> Bool {
        onClick([])
        return true
    }
}

/// System-wide shortcuts (⌘⇧T, ⌘⇧.) through Carbon hot keys, which need no extra permission.
final class HotKeys {
    private static var actions: [UInt32: () -> Void] = [:]
    private static var installed = false
    private static var nextID: UInt32 = 1
    private var refs: [EventHotKeyRef] = []

    func register(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        HotKeys.installHandler()
        let id = HotKeys.nextID
        HotKeys.nextID += 1
        HotKeys.actions[id] = action
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x5436_3030), id: id) // "T600"
        if RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref) == noErr, let ref {
            refs.append(ref)
        }
    }

    deinit { refs.forEach { UnregisterEventHotKey($0) } }

    private static func installHandler() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let id = hotKeyID.id
            DispatchQueue.main.async { HotKeys.actions[id]?() }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
