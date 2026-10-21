import AppKit
import Combine
import SwiftUI
import Tech60Core
import UserNotifications

/// The floating news card: a panel that never takes focus from what you're typing in.
@MainActor
func makeCardPanel(model: AppModel) -> NSPanel {
    let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 640),
                        styleMask: [.nonactivatingPanel, .titled, .closable, .resizable, .fullSizeContentView],
                        backing: .buffered, defer: false)
    panel.title = "Tech60"
    panel.titleVisibility = .hidden
    panel.titlebarAppearsTransparent = true
    panel.isMovableByWindowBackground = true
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    panel.level = .normal
    panel.standardWindowButton(.closeButton)?.isHidden = true
    panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
    panel.standardWindowButton(.zoomButton)?.isHidden = true
    // Clear window background so the card's material shows the desktop through it, like a widget.
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.minSize = NSSize(width: 320, height: 300)
    panel.contentView = NSHostingView(rootView: CardView(model: model))
    if !panel.setFrameUsingName("Tech60Card") {
        if let screen = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: screen.maxX - panel.frame.width - 24, y: screen.maxY - panel.frame.height - 24))
        } else {
            panel.center()
        }
    }
    panel.setFrameAutosaveName("Tech60Card")
    return panel
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, UNUserNotificationCenterDelegate {
    private var model: AppModel!
    private var panel: NSPanel!
    private var statusItem: NSStatusItem!
    private var sourcesWindow: NSWindow?
    private var countWatcher: Any?
    private var compact: CompactController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-Appearance"), i + 1 < args.count {
            NSApp.appearance = NSAppearance(named: args[i + 1] == "dark" ? .darkAqua : .aqua)
        }
        model = AppModel(isDemo: args.contains("--demo"))
        if !model.isDemo { UNUserNotificationCenter.current().delegate = self }
        model.openSettings = { [weak self] in self?.showSources() }
        panel = makeCardPanel(model: model)
        compact = CompactController(model: model, card: panel)
        model.collapseToTicker = { [weak self] in self?.compact.collapseToTicker() }
        model.shrinkToDot = { [weak self] in self?.compact.shrinkToDot() }
        compact.showCurrent()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = MenuBarIcon.make()
        statusItem.button?.imagePosition = .imageLeading
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        countWatcher = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateCount() }
        }
        updateCount()
    }

    private func updateCount() {
        let n = model.newCount
        statusItem.button?.title = n > 0 ? " \(n)" : ""
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        func item(_ title: String, _ action: Selector, key: String = "", on: Bool? = nil) {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
            i.target = self
            if let on { i.state = on ? .on : .off }
            menu.addItem(i)
        }
        item(compact.isVisible ? "Hide Tech60" : "Show Tech60", #selector(toggleCard))
        if compact.current == .card {
            item("Collapse to ticker", #selector(collapseToTicker), key: "")
        } else {
            item("Expand to card", #selector(expandCard), key: "")
        }
        if compact.current != .dot { item("Shrink to dot", #selector(shrinkToDot)) }
        item(model.isRefreshing ? "Refreshing…" : "Refresh now", #selector(refreshNow), key: "r")
        item("Mark all as seen", #selector(markSeen))
        if model.hasBrief { item("Show today's brief", #selector(showBrief)) }
        menu.addItem(.separator())
        item("Keep card above other windows", #selector(togglePin), on: panel.level == .floating)
        item("Short summaries (on-device)", #selector(toggleSummaries), on: model.summariesEnabled)
        item("Sources, topics, and brief…", #selector(showSources), key: ",")
        menu.addItem(.separator())
        item("Quit Tech60", #selector(quit), key: "q")
    }

    @objc private func toggleCard() { compact.toggleVisible() }
    @objc private func collapseToTicker() { compact.collapseToTicker() }
    @objc private func shrinkToDot() { compact.shrinkToDot() }
    @objc private func expandCard() { compact.showCard() }
    @objc private func togglePause() { model.isPaused.toggle() }
    @objc private func refreshNow() { Task { await model.refresh() } }
    @objc private func markSeen() { model.markViewed() }
    @objc private func togglePin() { panel.level = panel.level == .floating ? .normal : .floating }
    @objc private func toggleSummaries() { model.summariesEnabled.toggle() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func showBrief() {
        model.showBrief()
        compact.showCard()
    }

    // Clicking the brief notification opens the brief on the card.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in self.showBrief() }
        completionHandler()
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    @objc private func showSources() {
        if sourcesWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 600),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "Tech60 settings"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SourcesView(model: model))
            w.center()
            sourcesWindow = w
            compact.sharedExtras = [w]
            compact.applySharing()
        }
        NSApp.activate(ignoringOtherApps: true)
        sourcesWindow?.makeKeyAndOrderFront(nil)
    }
}

/// The menu bar glyph: a small front page whose top corner opens into the Tech60 ring.
/// Drawn as a template image so macOS tints it for light and dark menu bars.
enum MenuBarIcon {
    static func make() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.set()
            // Page outline, with a gap cut where the ring sits.
            NSGraphicsContext.saveGraphicsState()
            let clip = NSBezierPath(rect: NSRect(x: 0, y: 0, width: 18, height: 18))
            clip.appendOval(in: NSRect(x: 13.9 - 4, y: 4.1 - 4, width: 8, height: 8))
            clip.windingRule = .evenOdd
            clip.addClip()
            let page = NSBezierPath(roundedRect: NSRect(x: 2.8, y: 2.3, width: 12.4, height: 13.4), xRadius: 2.6, yRadius: 2.6)
            page.lineWidth = 1.6
            page.stroke()
            NSGraphicsContext.restoreGraphicsState()

            // The ring, open at 82%, starting at 12 o'clock.
            let ring = NSBezierPath()
            for i in 0...40 {
                let a = -CGFloat.pi / 2 + CGFloat(i) / 40 * 2 * .pi * 0.8
                let p = NSPoint(x: 13.9 + 2.5 * cos(a), y: 4.1 + 2.5 * sin(a))
                i == 0 ? ring.move(to: p) : ring.line(to: p)
            }
            ring.lineWidth = 1.5
            ring.lineCapStyle = .round
            ring.stroke()

            // Masthead and three lines of text.
            for (x, y, w, h) in [(5.1, 5.2, 4.4, 1.9), (5.1, 8.6, 7.8, 1.2), (5.1, 10.8, 7.8, 1.2), (5.1, 13.0, 5.2, 1.2)] as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
                NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: 0.6, yRadius: 0.6).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Tech60"
        return image
    }
}
