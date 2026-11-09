import AppKit
import SecondChairCore

/// `--screenshots <dir> --corpus <folder>`: drives the app through its main states and saves PNGs,
/// so the design can be checked in CI. Developer use only; it starts from empty settings.
@MainActor
enum Screenshots {
    static func run(into dir: String, app: AppDelegate) async {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let model = app.model
        app.mainWindow.setContentSize(NSSize(width: 1120, height: 760))
        app.mainWindow.center()
        await wait(2)
        window(app.mainWindow, "\(dir)/1-empty.png")

        if let corpus = CLI.value("--corpus") {
            model.addFolders([URL(fileURLWithPath: corpus).standardizedFileURL])
            for _ in 0..<80 where Library.shared.isBuilding || model.passageCount == 0 { await wait(0.5) }
        }
        await wait(1)
        window(app.mainWindow, "\(dir)/2-library.png")

        let questions = [("3-grounded", "How much did revenue grow while you led product at Lumen?"),
                         ("4-story", "Tell me about a time you disagreed with your CEO."),
                         ("5-not-in-docs", "How would you price a freemium consumer mobile game?")]
        for (name, q) in questions {
            model.ask(q)
            for _ in 0..<60 where model.current?.answering != false { await wait(0.5) }
            await wait(1)
            window(app.mainWindow, "\(dir)/\(name).png")
        }

        model.ask("Walk me through your 90 day plan.")
        for _ in 0..<60 where model.current?.answering != false { await wait(0.5) }
        app.overlayPanel.setContentSize(NSSize(width: 440, height: 420))
        app.overlayPanel.orderFrontRegardless()
        await wait(1.5)
        // The floating window is excluded from screen capture by design, so render it in-process.
        render(app.overlayPanel, "\(dir)/6-overlay.png")
        app.overlayPanel.orderOut(nil)

        model.showSetup = true
        await wait(2)
        if let sheet = app.mainWindow.attachedSheet { window(sheet, "\(dir)/7-session-setup.png") }
        model.showSetup = false
        await wait(1)

        model.showSettings = true
        await wait(2)
        if let sheet = app.mainWindow.attachedSheet { window(sheet, "\(dir)/8-settings.png") }
        model.showSettings = false
        await wait(1)
        NSApp.terminate(nil)
    }

    static func wait(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    static func window(_ w: NSWindow, _ path: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = ["-x", "-o", "-l", String(w.windowNumber), path]
        try? p.run()
        p.waitUntilExit()
        if !FileManager.default.fileExists(atPath: path) { render(w, path) }
        print("screenshot \(path)")
    }

    static func render(_ w: NSWindow, _ path: String) {
        guard let view = w.contentView else { return }
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        print("rendered \(path)")
    }
}
