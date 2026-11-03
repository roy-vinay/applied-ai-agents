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
    private var lastFingerprint: Fingerprint?
    private var modelAnswers: [String: Int?] = [:]
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
        // Four looks a second: an exact app answers in milliseconds, and an unchanged screen costs almost nothing.
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
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
        // Everything else: read the screen.
        guard let front else { return }
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
        screenApp = app
        let pid = app.processIdentifier
        let name = app.localizedName ?? "screen"
        let slides = self.slides()
        let near = currentIndex()
        let previous = lastFingerprint
        Task.detached(priority: .userInitiated) { [weak self] in
            defer { DispatchQueue.main.async { self?.reading = false } }
            guard let image = try? await SlideWindowCapture.capture(pid: pid) else { return }
            // Nothing changed on screen since the last look: nothing to read.
            let shot = Fingerprint(image)
            if let shot, shot.matches(previous) { return }
            await MainActor.run { self?.lastFingerprint = shot; self?.source = .screen(name) }
            // A quick read first; a careful one only if the quick one isn't sure.
            var best: SlideMatcher.Match?
            var title: String?
            for fast in [true, false] {
                guard let text = try? ScreenText.read(image, fast: fast) else { continue }
                title = text.title ?? title
                if let m = SlideMatcher.match(screenTitle: text.title, screenLines: text.lines, slides: slides, near: near),
                   SlideMatcher.isConfident(m, from: near) {
                    best = m
                    break
                }
            }
            if let found = best {
                let index = found.index, sure = found.score >= 0.95 && found.margin >= 0.3
                await MainActor.run { self?.propose(index, sure: sure) }
            } else if let readTitle = title, let index = await self?.askModel(readTitle, slides) {
                await MainActor.run { self?.propose(index, sure: false) }
            } else {
                // Couldn't tell: look again next time even if the screen hasn't changed.
                await MainActor.run { self?.lastFingerprint = nil }
            }
        }
    }

    /// When the screen title doesn't match well, ask the on-device model which notes heading it means.
    /// Each title is asked once and the answer remembered, so it costs nothing while a slide stays up.
    private func askModel(_ title: String, _ slides: [Slide]) async -> Int? {
        guard Assistant.isAvailable, SlideMatcher.keyWords(title).count >= 2 else { return nil }
        let key = title.lowercased()
        if let cached = await MainActor.run(body: { modelAnswers[key] }) { return cached }
        let answer = await Assistant.matchSlide(title, among: slides.map { $0.title })
        await MainActor.run { modelAnswers[key] = .some(answer) }
        return answer
    }

    /// Forget remembered answers, for example when different notes are opened.
    func reset() {
        modelAnswers = [:]
        pending = nil
        lastAppSlide = nil
    }

    /// A near-exact title moves the notes at once. Anything less waits for a second reading to agree,
    /// so a passing animation or a half-drawn slide can't jump the notes.
    private func propose(_ index: Int, sure: Bool) {
        guard Date() >= pausedUntil else { return }
        if let p = pending, p.index == index {
            pending = (index, p.count + 1)
        } else {
            pending = (index, 1)
        }
        if let p = pending, sure || p.count >= 2, index != currentIndex() {
            onMove?(index)
        }
    }

    /// The app showing the slides right now, if SpeakerNotes knows it: what the notes should move along with.
    var slidesApp: NSRunningApplication? {
        let front = NSWorkspace.shared.frontmostApplication
        if let front, front.bundleIdentifier != Bundle.main.bundleIdentifier, !ignoredApps.contains(front.bundleIdentifier ?? "") {
            return front
        }
        switch source {
        case .app(let a)?:
            let id = a == .keynote ? SlideApp.keynoteID : SlideApp.powerpointID
            return NSRunningApplication.runningApplications(withBundleIdentifier: id).first
        case .screen?:
            return screenApp
        case nil:
            return nil
        }
    }
    private var screenApp: NSRunningApplication?

    /// Remember that the notes are already on a slide, so the next reading doesn't count as news.
    func settle(on index: Int) {
        pending = (index, 2)
    }
}
