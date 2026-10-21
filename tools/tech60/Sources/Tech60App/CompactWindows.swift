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
    /// "Keep card above other windows": also over full-screen apps and on every Space.
    @Published var cardPinned: Bool { didSet { store(cardPinned, "cardPinned") } }
    /// Leave every Tech60 window out of screen sharing and recordings (SHARE-01).
    @Published var hideFromSharing: Bool { didSet { store(hideFromSharing, "hideFromSharing") } }
    /// Seconds each headline stays on the ticker when Reduce Motion is on.
    let rotateSeconds: Double
    /// How fast the ticker scrolls, in points per second.
    @Published var speed: Double { didSet { if save { UserDefaults.standard.set(speed, forKey: "tickerSpeed") } } }
    static let speeds: [(String, Double)] = [("Slow", 25), ("Normal", 40), ("Fast", 60)]

    init(save: Bool) {
        self.save = save
        let d = UserDefaults.standard
        alwaysOnTop = save ? (d.object(forKey: "compactAlwaysOnTop") as? Bool ?? true) : true
        allSpaces = save ? (d.object(forKey: "compactAllSpaces") as? Bool ?? true) : true
        cardPinned = save ? d.bool(forKey: "cardPinned") : false
        // Screenshots in CI need to capture the windows; everywhere else they are hidden from sharing.
        let allowCapture = ProcessInfo.processInfo.arguments.contains("--allow-capture")
        hideFromSharing = allowCapture ? false : (save ? (d.object(forKey: "hideFromSharing") as? Bool ?? true) : true)
        let seconds = d.double(forKey: "tickerSeconds")
        rotateSeconds = seconds >= 3 ? seconds : 8
        let saved = save ? d.double(forKey: "tickerSpeed") : 0
        speed = saved > 0 ? saved : 40
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
    /// The ticker's headlines, worked out once when stories change rather than on every redraw.
    @Published private(set) var headlines: [TickerItem] = []
    private var leadStories: [String: Story] = [:]
    /// The scrolling text, so a ⌘-click can find the headline under the pointer.
    weak var marquee: MarqueeView?

    private var tickerBook: PlacementBook
    private var dotBook: PlacementBook
    private lazy var ticker: CompactPanel = makePanel(size: NSSize(width: 620, height: 36), view: AnyView(TickerView(controller: self)))
    private lazy var dot: CompactPanel = makePanel(size: NSSize(width: Self.dotSize, height: Self.dotSize), view: AnyView(DotView(model: model, controller: self)))
    private lazy var hints: [Dock: CompactPanel] = [.top: makeHint(.top), .bottom: makeHint(.bottom)]
    private var observers: [Any] = []
    private var hintsShown: Bool?
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

        // Recompute the ticker's headlines after the stories settle, and only while the ticker or dot is up.
        model.objectWillChange
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.state.current != .card else { return }
                    self.refreshHeadlines()
                }
            }
            .store(in: &bag)
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
        if state.current != .card { refreshHeadlines() }
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

    static let dotSize: CGFloat = 56

    private func go(_ next: Presentation) {
        // The first time on a display, the dot appears at the top-right corner of the window it came from,
        // so it's obvious where the card went.
        let from = window(for: state.current)
        if next == .dot, let screen = from.screen, dotBook.byDisplay[screen.tech60Key] == nil {
            let s = Self.dotSize
            let rect = CGRect(x: from.frame.maxX - s, y: from.frame.maxY - s, width: s, height: s)
            dotBook.remember(Placement.spot(afterDropping: rect, in: screen.visibleFrame, snapping: false), on: screen.tech60Key)
            saveBooks()
        }
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

    func refreshHeadlines() {
        let rows = Array(model.visibleClusters.prefix(20))
        let items = rows.map { TickerItem(id: $0.id, source: $0.lead.sourceName, title: $0.lead.title) }
        leadStories = Dictionary(rows.map { ($0.id, $0.lead) }, uniquingKeysWith: { first, _ in first })
        if items != headlines { headlines = items }
    }

    func openStory(_ id: String) {
        if let story = leadStories[id] { model.open(story) }
    }

    private func display(_ p: Presentation) {
        if p != .card { refreshHeadlines() }
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
        // Show or hide the snap highlights only when that changes, not on every mouse movement.
        if hintsShown != !optionHeld {
            hintsShown = !optionHeld
            showHints(on: screen, visible: !optionHeld)
        }
    }

    func dragEnded(_ panel: NSWindow, optionHeld: Bool) {
        isDragging = false
        isInteracting = false
        snapTarget = nil
        hintsShown = nil
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
        if state.current == .ticker {
            let speed = NSMenuItem(title: "Scroll speed", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            for (name, value) in CompactSettings.speeds {
                let i = ClosureMenuItem(title: name) { [weak self] in self?.settings.speed = value }
                i.state = settings.speed == value ? .on : .off
                sub.addItem(i)
            }
            speed.submenu = sub
            menu.addItem(speed)
        }
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
        // A pinned card floats over other windows, including full-screen apps, on every Space.
        card.level = settings.cardPinned ? .floating : .normal
        card.collectionBehavior = settings.cardPinned ? [.canJoinAllSpaces, .fullScreenAuxiliary] : []
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

struct TickerItem: Identifiable, Equatable {
    let id: String
    let source: String
    let title: String
}

/// The ticker: a pill whose headlines scroll continuously, right to left.
struct TickerView: View {
    @ObservedObject var controller: CompactController
    @ObservedObject var settings: CompactSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    @State private var index = 0
    @State private var elapsed = 0.0
    @State private var tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(controller: CompactController) {
        _controller = ObservedObject(wrappedValue: controller)
        _settings = ObservedObject(wrappedValue: controller.settings)
    }

    private var items: [TickerItem] { controller.headlines }
    private var paused: Bool { hovering || controller.isInteracting || controller.model.isPaused }
    /// With Reduce Motion, one headline at a time without movement.
    private var still: TickerItem? { items.isEmpty ? nil : items[index % items.count] }

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
                        .frame(width: 7)
                } else {
                    Circle().fill(Palette.accent).frame(width: 7, height: 7)
                }
                if items.isEmpty {
                    Text(controller.model.isRefreshing ? "Checking sources" : "No stories yet")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.secondary)
                    Spacer()
                } else if reduceMotion, let still {
                    Text(still.source.uppercased())
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Palette.secondary)
                        .fixedSize()
                    Text(still.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                } else {
                    MarqueeText(items: items, paused: paused, speed: CGFloat(settings.speed), controller: controller)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .allowsHitTesting(false)
            .padding(.leading, 10)
            .frame(maxHeight: .infinity)
            .background(GrabSurface(
                label: "Tech60 ticker. Click to expand, Command-click a headline to open it.",
                tooltip: hovering ? "Click to expand · ⌘-click a headline to open it" : nil,
                onClick: { flags, point in
                    if flags.contains(.command) {
                        if reduceMotion, let still { controller.openStory(still.id) }
                        else if let id = controller.marquee?.itemID(atWindowPoint: point) { controller.openStory(id) }
                    } else {
                        controller.expand()
                    }
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
            // Only Reduce Motion rotates; the scroll itself is a Core Animation loop and needs no ticks.
            guard reduceMotion, !paused, items.count > 1 else { return }
            elapsed += 1
            guard elapsed >= settings.rotateSeconds else { return }
            elapsed = 0
            index += 1
        }
    }
}

/// Continuous right-to-left scrolling text, run by Core Animation so it costs almost nothing per frame.
struct MarqueeText: NSViewRepresentable {
    let items: [TickerItem]
    let paused: Bool
    let speed: CGFloat
    let controller: CompactController

    func makeNSView(context: Context) -> MarqueeView {
        let view = MarqueeView()
        controller.marquee = view
        return view
    }

    func updateNSView(_ view: MarqueeView, context: Context) {
        view.update(items: items, speed: speed)
        view.setPaused(paused)
    }
}

final class MarqueeView: NSView {
    private let strip = CALayer()
    private let fade = CAGradientLayer()
    private var items: [TickerItem] = []
    private var speed: CGFloat = 40
    /// Width of one full pass of the headlines.
    private var cycle: CGFloat = 0
    /// Where each headline sits within one pass.
    private struct Span { let start: CGFloat; let end: CGFloat; let id: String }
    private var spans: [Span] = []
    private var paused = false
    private var builtSize: CGSize = .zero

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.addSublayer(strip)
        // Soft edges so headlines slide in and out instead of being cut.
        fade.colors = [NSColor.clear.cgColor, NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
        fade.startPoint = CGPoint(x: 0, y: 0.5)
        fade.endPoint = CGPoint(x: 1, y: 0.5)
        layer?.mask = fade
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    // Clicks go to the surface underneath.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(items: [TickerItem], speed: CGFloat) {
        guard items != self.items || speed != self.speed else { return }
        self.items = items
        self.speed = speed
        rebuild()
    }

    override func layout() {
        super.layout()
        if bounds.size != builtSize { rebuild() }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        rebuild()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        rebuild()
    }

    private func text() -> NSAttributedString {
        let out = NSMutableAttributedString()
        var found: [Span] = []
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let sourceStyle: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10.5, weight: .semibold),
                .foregroundColor: NSColor.secondaryLabelColor.usingColorSpace(.sRGB) ?? .gray, .kern: 0.4,
            ]
            let titleStyle: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: NSColor.labelColor.usingColorSpace(.sRGB) ?? .black,
            ]
            let gapStyle: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: NSColor.tertiaryLabelColor.usingColorSpace(.sRGB) ?? .gray,
            ]
            for item in items {
                let start = out.size().width
                out.append(NSAttributedString(string: item.source.uppercased() + "  ", attributes: sourceStyle))
                out.append(NSAttributedString(string: item.title, attributes: titleStyle))
                found.append(Span(start: start, end: out.size().width, id: item.id))
                out.append(NSAttributedString(string: "      •      ", attributes: gapStyle))
            }
        }
        spans = found
        return out
    }

    private func rebuild() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        builtSize = bounds.size
        strip.removeAllAnimations()
        strip.sublayers?.forEach { $0.removeFromSuperlayer() }
        strip.speed = 1
        strip.timeOffset = 0
        strip.beginTime = 0
        fade.frame = bounds
        let edge = bounds.width > 0 ? min(0.06, 18 / bounds.width) : 0
        fade.locations = [0, NSNumber(value: Double(edge)), NSNumber(value: Double(1 - edge)), 1]
        guard !items.isEmpty, bounds.width > 0 else { return }

        let pass = text()
        let height = ceil(pass.size().height)
        // Repeat a short list until one pass is wider than the ticker, so there's never a gap.
        let line = NSMutableAttributedString(attributedString: pass)
        let one = pass.size().width
        var copies = 1
        while line.size().width < bounds.width, copies < 20 {
            line.append(pass)
            copies += 1
        }
        let base = spans
        spans = (0..<copies).flatMap { k in
            base.map { Span(start: $0.start + CGFloat(k) * one, end: $0.end + CGFloat(k) * one, id: $0.id) }
        }
        cycle = one * CGFloat(copies)

        let scale = window?.backingScaleFactor ?? 2
        for k in 0..<2 {
            let t = CATextLayer()
            t.string = line
            t.contentsScale = scale
            t.isWrapped = false
            t.frame = CGRect(x: CGFloat(k) * cycle, y: (bounds.height - height) / 2, width: cycle + 1, height: height)
            strip.addSublayer(t)
        }
        strip.frame = CGRect(x: 0, y: 0, width: cycle * 2, height: bounds.height)

        let scroll = CABasicAnimation(keyPath: "transform.translation.x")
        scroll.fromValue = 0
        scroll.toValue = -cycle
        scroll.duration = CFTimeInterval(cycle / max(speed, 5))
        scroll.repeatCount = .infinity
        scroll.isRemovedOnCompletion = false
        strip.add(scroll, forKey: "scroll")
        if paused {
            paused = false
            setPaused(true)
        }
    }

    func setPaused(_ pause: Bool) {
        guard pause != paused else { return }
        paused = pause
        if pause {
            let now = strip.convertTime(CACurrentMediaTime(), from: nil)
            strip.speed = 0
            strip.timeOffset = now
        } else {
            let pausedAt = strip.timeOffset
            strip.speed = 1
            strip.timeOffset = 0
            strip.beginTime = 0
            strip.beginTime = strip.convertTime(CACurrentMediaTime(), from: nil) - pausedAt
        }
    }

    /// The headline under a point in window coordinates, for ⌘-click.
    func itemID(atWindowPoint point: NSPoint) -> String? {
        guard cycle > 0 else { return nil }
        let x = convert(point, from: nil).x
        let shift = (strip.presentation()?.value(forKeyPath: "transform.translation.x") as? NSNumber)?.doubleValue ?? 0
        var at = (x - CGFloat(shift)).truncatingRemainder(dividingBy: cycle)
        if at < 0 { at += cycle }
        return spans.first { at >= $0.start - 12 && at <= $0.end + 12 }?.id
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
                Circle().fill(Palette.accent.opacity(0.18)).frame(width: 50, height: 50)
                    .opacity(reduceMotion ? 1 : (bright ? 1 : 0.35))
                Circle().fill(Palette.accent.opacity(0.35)).frame(width: 38, height: 38)
                    .opacity(reduceMotion ? 1 : (bright ? 1 : 0.5))
            }
            // Always the accent color with a white ring and a shadow, so it stands out on any wallpaper.
            Circle()
                .fill(Palette.accent)
                .frame(width: 24, height: 24)
                .overlay(Circle().strokeBorder(Color.white, lineWidth: 2.5))
                .shadow(color: .black.opacity(0.45), radius: 4, y: 1.5)
        }
        .frame(width: CompactController.dotSize, height: CompactController.dotSize)
        .allowsHitTesting(false)
        .background(GrabSurface(
            label: hasNew ? "Tech60, new stories. Click to restore." : "Tech60. Click to restore.",
            tooltip: controller.headlines.first.map { hasNew ? "New: \($0.title)" : $0.title },
            onClick: { _, _ in controller.expand() },
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
    let onClick: (NSEvent.ModifierFlags, NSPoint) -> Void
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
    var onClick: (NSEvent.ModifierFlags, NSPoint) -> Void = { _, _ in }
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
            onClick(event.modifierFlags, event.locationInWindow)
        }
    }

    override func accessibilityPerformPress() -> Bool {
        onClick([], .zero)
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
