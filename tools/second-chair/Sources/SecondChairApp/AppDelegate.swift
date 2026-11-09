import AppKit
import Carbon.HIToolbox
import SwiftUI
import SecondChairCore

/// Shared state: which models are running right now.
final class AppState {
    static let shared = AppState()
    var models = Models.Available(fast: nil, quality: nil, embedder: nil, summary: "Checking local models…")
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let model = AppModel.shared
    private var statusItem: NSStatusItem!
    private var window: NSWindow!
    private var overlay: Overlay!
    private let hotKeys = HotKeys()
    private var freshnessTimer: Timer?
    private var screenshotDir: String? { CLI.value("--screenshots") }

    func applicationDidFinishLaunching(_ notification: Notification) {
        overlay = Overlay(model: model)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 760),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        window.title = "Second Chair"
        window.titlebarAppearsTransparent = true
        window.contentViewController = NSHostingController(rootView: RootView().environmentObject(model))
        window.setContentSize(NSSize(width: 1120, height: 760))
        window.isReleasedWhenClosed = false
        window.sharingType = .none
        if !window.setFrameUsingName("SecondChairMain") { window.center() }
        window.setFrameAutosaveName("SecondChairMain")

        PrivacyGuard.start()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "chair", accessibilityDescription: "Second Chair")
        model.statusItem = statusItem
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        buildMainMenu()

        // Hot key actions arrive on the main queue.
        hotKeys.register(kVK_Space) { [weak self] in MainActor.assumeIsolated { guard let self else { return }; self.overlay.focusQuery(self.model) } }
        hotKeys.register(kVK_ANSI_S) { [weak self] in MainActor.assumeIsolated { self?.overlay.toggle() } }
        hotKeys.register(kVK_ANSI_A) { [weak self] in MainActor.assumeIsolated { self?.model.askLastExchange() } }
        hotKeys.register(kVK_ANSI_D) { [weak self] in MainActor.assumeIsolated { self?.model.session.toggleDictation() } }

        if screenshotDir != nil { UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier ?? "") }
        Library.shared.load()
        model.syncLibrary()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        Task { @MainActor in
            await self.model.discoverModels()
            if Library.shared.isStale, !Library.shared.folders.isEmpty { self.model.rebuild() }
            if let dir = self.screenshotDir { await Screenshots.run(into: dir, app: self) }
        }
        // The index follows its folders between sessions; it never rebuilds mid-interview.
        freshnessTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.model.sessionActive else { return }
                Library.shared.checkFreshness()
                if Library.shared.isStale, !Library.shared.isBuilding, !Library.shared.folders.isEmpty { self.model.rebuild() }
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMain()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func showMain() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    var mainWindow: NSWindow { window }
    var overlayPanel: NSPanel { overlay.panel }

    // MARK: Menus

    private func buildMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Second Chair", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Second Chair", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Second Chair", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let win = NSMenu(title: "Window")
        let show = NSMenuItem(title: "Second Chair", action: #selector(showMainMenu), keyEquivalent: "0")
        show.target = self
        win.addItem(show)
        let float = NSMenuItem(title: "Floating Window", action: #selector(toggleOverlay), keyEquivalent: "")
        float.target = self
        win.addItem(float)
        win.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = win
        main.addItem(windowItem)
        NSApp.mainMenu = main
        NSApp.windowsMenu = win
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        func add(_ title: String, _ action: Selector, enabled: Bool = true) {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
            i.target = self
            i.isEnabled = enabled
            menu.addItem(i)
        }
        add("Open Second Chair", #selector(showMainMenu))
        add(overlay.panel.isVisible ? "Hide Floating Window  ⌃⌥S" : "Show Floating Window  ⌃⌥S", #selector(toggleOverlay))
        add("Ask a Question  ⌃⌥Space", #selector(askFromMenu))
        menu.addItem(.separator())
        if model.sessionActive {
            let info = NSMenuItem(title: model.sessionStatus, action: nil, keyEquivalent: "")
            info.isEnabled = false
            menu.addItem(info)
            add(model.dictating ? "Stop Dictating  ⌃⌥D" : "Dictate Question  ⌃⌥D", #selector(dictate))
            add("End Session and Review", #selector(endSession))
        } else {
            add("Start Interview…", #selector(showMainMenu), enabled: !model.folders.isEmpty)
        }
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    @objc private func showMainMenu() { showMain() }
    @objc private func toggleOverlay() { overlay.toggle() }
    @objc private func askFromMenu() { overlay.focusQuery(model) }
    @objc private func dictate() { model.session.toggleDictation() }
    @objc private func endSession() { model.endSession(); showMain() }
}
