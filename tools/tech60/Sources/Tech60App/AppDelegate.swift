import AppKit
import Combine
import SwiftUI
import Tech60Core

/// The floating news card: it never takes focus from what you're typing in.
final class CardPanel: NSPanel {
    init(model: AppModel) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 380, height: 460),
                   styleMask: [.nonactivatingPanel, .titled, .closable, .resizable, .fullSizeContentView],
                   backing: .buffered, defer: false)
        title = "Tech60"
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        level = .normal
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        minSize = NSSize(width: 320, height: 300)
        contentView = NSHostingView(rootView: CardView(model: model))
        if !setFrameUsingName("Tech60Card") { placeTopRight() }
        setFrameAutosaveName("Tech60Card")
    }

    override var canBecomeKey: Bool { true }

    private func placeTopRight() {
        guard let screen = NSScreen.main?.visibleFrame else { center(); return }
        setFrameOrigin(NSPoint(x: screen.maxX - frame.width - 24, y: screen.maxY - frame.height - 24))
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var model: AppModel!
    private var panel: CardPanel!
    private var statusItem: NSStatusItem!
    private var sourcesWindow: NSWindow?
    private var countWatcher: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-Appearance"), i + 1 < args.count {
            NSApp.appearance = NSAppearance(named: args[i + 1] == "dark" ? .darkAqua : .aqua)
        }
        model = AppModel(isDemo: args.contains("--demo"))
        panel = CardPanel(model: model)
        panel.orderFrontRegardless()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "newspaper", accessibilityDescription: "Tech60")
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
        item(panel.isVisible ? "Hide card" : "Show card", #selector(toggleCard))
        item(model.isPaused ? "Resume scrolling" : "Pause scrolling", #selector(togglePause))
        item(model.isRefreshing ? "Refreshing…" : "Refresh now", #selector(refreshNow), key: "r")
        item("Mark all as seen", #selector(markSeen))
        menu.addItem(.separator())
        item("Keep card above other windows", #selector(togglePin), on: panel.level == .floating)
        item("Short summaries (on-device)", #selector(toggleSummaries), on: model.summariesEnabled)
        item("Sources…", #selector(showSources), key: ",")
        menu.addItem(.separator())
        item("Quit Tech60", #selector(quit), key: "q")
    }

    @objc private func toggleCard() { panel.isVisible ? panel.orderOut(nil) : panel.orderFrontRegardless() }
    @objc private func togglePause() { model.isPaused.toggle() }
    @objc private func refreshNow() { Task { await model.refresh() } }
    @objc private func markSeen() { model.markViewed() }
    @objc private func togglePin() { panel.level = panel.level == .floating ? .normal : .floating }
    @objc private func toggleSummaries() { model.summariesEnabled.toggle() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func showSources() {
        if sourcesWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 560),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "Tech60 sources"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SourcesView(model: model))
            w.center()
            sourcesWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        sourcesWindow?.makeKeyAndOrderFront(nil)
    }
}
