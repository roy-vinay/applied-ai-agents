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
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        // Launched to open a file (from Finder or `open`): don't show the Open panel.
        let isDefaultLaunch = (notification.userInfo?[NSApplication.launchIsDefaultLaunchKey] as? Bool) ?? true
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
