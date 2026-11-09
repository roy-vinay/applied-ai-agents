import AppKit
import ScreenCaptureKit

/// Keeps every Second Chair window out of screenshots, recordings and screen shares: the main window,
/// the floating window, sheets and alerts. New windows are caught as they appear.
@MainActor
enum PrivacyGuard {
    private static var timer: Timer?
    private static var observers: [NSObjectProtocol] = []

    static func apply() {
        for w in NSApp.windows where w.sharingType != .none { w.sharingType = .none }
    }

    static func start() {
        apply()
        let names: [Notification.Name] = [NSWindow.didBecomeKeyNotification, NSWindow.didBecomeMainNotification,
                                          NSWindow.didUpdateNotification, NSWindow.willBeginSheetNotification]
        for name in names {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { apply() }
            })
        }
        // Backstop for windows that appear without becoming key (alerts, tool tips, menus).
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in MainActor.assumeIsolated { apply() } }
    }

    /// While an interview runs, also drop the Dock icon and the menu bar chair, which a full-screen share shows.
    static func setDiscreet(_ on: Bool, statusItem: NSStatusItem?) {
        guard UserDefaults.standard.object(forKey: "hideIconsInSessions") as? Bool ?? true else { return }
        statusItem?.isVisible = !on
        let policy: NSApplication.ActivationPolicy = on ? .accessory : .regular
        if NSApp.activationPolicy() != policy {
            NSApp.setActivationPolicy(policy)
            // Switching policy can drop focus; keep our windows where they were.
            DispatchQueue.main.async { NSApp.activate(ignoringOtherApps: true) }
        }
    }

    /// `--window-check`: puts a bright test window and the real app windows on screen, captures the display
    /// the way screen-sharing apps do, and fails if any of them shows up.
    static func selfTest() async -> Int32 {
        let magenta = NSColor(srgbRed: 1, green: 0, blue: 1, alpha: 1)
        let probe = NSWindow(contentRect: NSRect(x: 220, y: 220, width: 360, height: 260), styleMask: [.borderless],
                             backing: .buffered, defer: false)
        probe.backgroundColor = magenta
        probe.level = .floating
        probe.orderFrontRegardless()
        // A control window that is NOT hidden: the capture must show it, or the check proves nothing.
        let control = NSWindow(contentRect: NSRect(x: 700, y: 220, width: 360, height: 260), styleMask: [.borderless],
                               backing: .buffered, defer: false)
        control.backgroundColor = magenta
        control.level = .floating
        control.orderFrontRegardless()
        let overlay = Overlay(model: AppModel.shared)
        overlay.panel.orderFrontRegardless()
        apply()
        control.sharingType = .readOnly
        try? await Task.sleep(nanoseconds: 1_500_000_000)

        var failures: [String] = []
        for w in NSApp.windows where w.isVisible && w !== control && w.sharingType != .none { failures.append("window '\(w.title)' is visible to capture") }

        // 1. The system screenshot path (what screencapture and many recorders use).
        let path = NSTemporaryDirectory() + "secondchair-capture.png"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = ["-x", "-C", path]
        try? p.run()
        p.waitUntilExit()
        if let rep = NSImage(contentsOfFile: path).flatMap({ $0.tiffRepresentation }).flatMap(NSBitmapImageRep.init(data:)) {
            if !showsProbe(rep: rep, frame: control.frame) { failures.append("screenshot check couldn't see the control window, so it proves nothing") }
            else if showsProbe(rep: rep, frame: probe.frame) { failures.append("test window visible in a full-screen screenshot") }
            else { print("screenshot: control window visible, Second Chair test window hidden") }
        } else {
            print("screenshot: not available here (no Screen Recording permission)")
        }

        // 2. ScreenCaptureKit, which Zoom, Meet in Chrome, Teams and OBS use to share a screen.
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            if let display = content.displays.first {
                let config = SCStreamConfiguration()
                config.width = display.width * 2
                config.height = display.height * 2
                let image = try await SCScreenshotManager.captureImage(
                    contentFilter: SCContentFilter(display: display, excludingWindows: []), configuration: config)
                let rep = NSBitmapImageRep(cgImage: image)
                if !showsProbe(rep: rep, frame: control.frame) {
                    failures.append("ScreenCaptureKit check couldn't see the control window, so it proves nothing")
                } else if showsProbe(rep: rep, frame: probe.frame) {
                    failures.append("test window visible to ScreenCaptureKit display capture")
                } else { print("ScreenCaptureKit: control window visible, Second Chair test window hidden") }
            }
        } catch {
            print("ScreenCaptureKit: not available here (\(error.localizedDescription))")
        }

        probe.orderOut(nil)
        control.orderOut(nil)
        overlay.panel.orderOut(nil)
        if failures.isEmpty { print("All Second Chair windows are excluded from screen capture.") }
        for f in failures { print("VISIBLE: \(f)") }
        return failures.isEmpty ? 0 : 1
    }

    /// Is the probe's magenta at its centre in this capture of the main display?
    private static func showsProbe(rep: NSBitmapImageRep, frame: NSRect) -> Bool {
        guard let screen = NSScreen.screens.first else { return false }
        let scale = CGFloat(rep.pixelsWide) / screen.frame.width
        var hits = 0
        for (dx, dy) in [(0.5, 0.5), (0.3, 0.3), (0.7, 0.6), (0.4, 0.7)] {
            let x = Int((frame.minX + frame.width * dx) * scale)
            let y = Int((screen.frame.height - (frame.minY + frame.height * dy)) * scale)
            guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
            if c.redComponent > 0.9, c.greenComponent < 0.15, c.blueComponent > 0.9 { hits += 1 }
        }
        return hits >= 2
    }
}
