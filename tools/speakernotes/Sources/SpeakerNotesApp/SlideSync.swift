import AppKit
import SpeakerNotesCore

/// Keeps the notes on the slide you're presenting.
///
/// - Keynote and PowerPoint: asks the app which slide is showing (exact).
/// - Anything else (Google Slides, Canva, a PDF): reads the slide's title off the screen with on-device text
///   recognition and finds the notes slide with that title. It only moves when it's sure, and when the title
///   doesn't match word for word, Apple's on-device model can match it by meaning.
final class SlideSync {
    enum Source: Equatable {
        case app(SlideApp)
        case screen(String) // the app being read, for example "Google Chrome"

        var label: String {
            switch self {
            case .app(let a): return a.name
            case .screen(let name): return name
            }
        }
    }

    /// The notes to follow, and the slide showing now.
    var slides: () -> [Slide] = { [] }
    var currentIndex: () -> Int = { 0 }
    /// Moves the notes. Called on the main thread.
    var onMove: ((Int) -> Void)?
    /// Something the person should know: a permission is missing, or what's being followed.
    var onStatus: ((String) -> Void)?
    var onSourceChange: ((Source?) -> Void)?

    private(set) var isOn = false
    private(set) var source: Source? { didSet { if source != oldValue { onSourceChange?(source) } } }
    private var timer: Timer?
    private var reading = false
    private var lastAppSlide: (SlideApp, Int)?
    private var pending: (index: Int, count: Int)?
    private var lastScreenTitle: String?
    private var askedModel: Set<String> = []
    private var warnedAutomation: Set<SlideApp> = []
    private var warnedScreen = false
    /// After you move the notes yourself, sync waits a moment before taking over again.
    var pausedUntil = Date.distantPast

    /// Video call and chat apps: reading their windows would match the wrong thing, so sync keeps its last answer.
    private let ignoredApps: Set<String> = ["us.zoom.xos", "com.microsoft.teams2", "com.microsoft.teams", "com.tinyspeck.slackmacgap",
                                            "com.apple.FaceTime", "com.cisco.webexmeetingsapp", "com.hnc.Discord"]

    func start() {
        guard !isOn else { return }
        isOn = true
        lastAppSlide = nil
        pending = nil
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        tick()
    }

    func stop() {
        isOn = false
        timer?.invalidate()
        timer = nil
        source = nil
    }

    private var tickCount = 0

    private func tick() {
        guard isOn, Date() >= pausedUntil else { return }
        tickCount += 1
        let front = NSWorkspace.shared.frontmostApplication
        let frontID = front?.bundleIdentifier

        // Our own window, or a call app, is in front: keep following whatever we followed last.
        if frontID == Bundle.main.bundleIdentifier || ignoredApps.contains(frontID ?? "") {
            if case .app(let a)? = source { followApp(a) }
            return
        }
        if let app = SlideApp(bundleID: frontID) {
            source = .app(app)
            followApp(app)
            return
        }
        // A slideshow playing in Keynote or PowerPoint wins, even if it isn't in front.
        for app in [SlideApp.keynote, .powerpoint] where app.isPlaying {
            source = .app(app)
            followApp(app)
            return
        }
        // Everything else: read the screen, about once a second.
        guard let front, tickCount % 2 == 0 else { return }
        followScreen(front)
    }

    // MARK: Keynote and PowerPoint

    private func followApp(_ app: SlideApp) {
        do {
            guard let number = try app.currentSlide() else { return }
            if let last = lastAppSlide, last.0 == app, last.1 == number { return }
            lastAppSlide = (app, number)
            if let index = SlideMatcher.index(forSlideNumber: number, in: slides()), index != currentIndex() {
                onMove?(index)
            }
        } catch let error as SlideApp.ScriptError where error.notAllowed {
            if !warnedAutomation.contains(app) {
                warnedAutomation.insert(app)
                onStatus?("Allow SpeakerNotes to control \(app.name) in System Settings > Privacy & Security > Automation")
            }
        } catch {
            // The deck is closing or between states; try again on the next tick.
        }
    }

    // MARK: Reading the screen

    private func followScreen(_ app: NSRunningApplication) {
        guard #available(macOS 14.0, *) else {
            if !warnedScreen { warnedScreen = true; onStatus?("Following other apps needs macOS 14 or later") }
            return
        }
        guard SlideWindowCapture.hasPermission else {
            if !warnedScreen {
                warnedScreen = true
                SlideWindowCapture.requestPermission()
                onStatus?("Allow Screen Recording for SpeakerNotes, then reopen it, to follow \(app.localizedName ?? "this app")")
            }
            return
        }
        guard !reading else { return }
        reading = true
        let pid = app.processIdentifier
        let name = app.localizedName ?? "screen"
        let slides = self.slides()
        let near = currentIndex()
        Task.detached(priority: .utility) { [weak self] in
            defer { DispatchQueue.main.async { self?.reading = false } }
            guard let image = try? await SlideWindowCapture.capture(pid: pid),
                  let text = try? ScreenText.read(image) else { return }
            let match = SlideMatcher.match(screenTitle: text.title, screenLines: text.lines, slides: slides, near: near)
            await MainActor.run { self?.source = .screen(name) }
            if let match, SlideMatcher.isConfident(match) {
                await MainActor.run { self?.propose(match.index) }
            } else if let title = text.title, let index = await self?.askModel(title, slides) {
                await MainActor.run { self?.propose(index) }
            }
        }
    }

    /// When the screen title doesn't match well, ask the on-device model which notes heading it means.
    /// Asked once per title, so it costs nothing while a slide stays up.
    private func askModel(_ title: String, _ slides: [Slide]) async -> Int? {
        let key = title.lowercased()
        let alreadyAsked = await MainActor.run { () -> Bool in
            let seen = askedModel.contains(key)
            askedModel.insert(key)
            return seen
        }
        guard !alreadyAsked, Assistant.isAvailable else { return nil }
        return await Assistant.matchSlide(title, among: slides.map { $0.title })
    }

    /// Moves only when two readings in a row agree, so a passing animation or a half-drawn slide can't jump the notes.
    private func propose(_ index: Int) {
        guard Date() >= pausedUntil else { return }
        if let p = pending, p.index == index {
            pending = (index, p.count + 1)
        } else {
            pending = (index, 1)
        }
        if let p = pending, p.count >= 2, index != currentIndex() {
            onMove?(index)
        }
    }
}
