import AppKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static var retained: AppDelegate?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        retained = delegate
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.build()
        // Optional appearance override: `defaults write io.github.roy-vinay.mdeditdiff Appearance dark` (or light).
        switch UserDefaults.standard.string(forKey: "Appearance")?.lowercased() {
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        default: break // Follow the system.
        }
    }

    private var appearanceObservation: NSKeyValueObservation?

    /// White icon by day, graphite black by night: follows Light and Dark mode (which, with
    /// Appearance set to Auto, switches with the time of day).
    static func updateDockIcon() {
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let name = dark ? "AppIcon-Dark" : "AppIcon-Light"
        if let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Icons"),
           let image = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = image
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.updateDockIcon()
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { AppDelegate.updateDockIcon() }
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        // Launched to open a file (from Finder or `open`): don't show the Open panel.
        let isDefaultLaunch = (notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? Bool) ?? true
        guard isDefaultLaunch else { return }
        // Launched on its own: offer the Open panel instead of an empty window.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            MainActor.assumeIsolated {
                if NSDocumentController.shared.documents.isEmpty {
                    NSDocumentController.shared.openDocument(nil)
                }
            }
        }
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { NSDocumentController.shared.openDocument(nil) }
        return true
    }

    @objc func openProjectPage(_ sender: Any?) {
        if let url = URL(string: "https://github.com/roy-vinay/applied-ai-agents/tree/main/tools/mdeditdiff") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func reportIssue(_ sender: Any?) {
        if let url = URL(string: "https://github.com/roy-vinay/applied-ai-agents/issues/new?title=mdEditDiff:%20") {
            NSWorkspace.shared.open(url)
        }
    }
}
