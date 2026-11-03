import AppKit
import Carbon.HIToolbox

/// Moves your actual slides when you move the notes, so one key (or click) moves both.
///
/// - Keynote and PowerPoint: goes to the exact slide through AppleScript.
/// - Other apps (Google Slides in a browser, a PDF viewer): sends → or ← to the app, once per slide.
///   Sending keys to another app needs Accessibility permission.
enum SlideDriver {
    /// SpeakerNotes' own key presses shouldn't be mistaken for yours ("Move with My Slide Keys").
    static private(set) var quietUntil = Date.distantPast

    enum Result { case moved, needsAccessibility, needsAutomation, notMoved }

    /// - Parameters:
    ///   - app: the app showing the slides.
    ///   - number: the slide number to show (1 is the first), when known.
    ///   - steps: how many slides forward (positive) or back (negative), for apps that only take keys.
    @discardableResult
    static func move(_ app: NSRunningApplication, toSlide number: Int, steps: Int) -> Result {
        guard steps != 0 else { return .notMoved }
        if let deck = SlideApp(bundleID: app.bundleIdentifier) {
            do {
                try go(deck, to: number)
                return .moved
            } catch let error as SlideApp.ScriptError where error.notAllowed {
                return .needsAutomation
            } catch {
                return sendArrows(to: app, steps: steps)
            }
        }
        return sendArrows(to: app, steps: steps)
    }

    private static func go(_ deck: SlideApp, to number: Int) throws {
        let script: String
        switch deck {
        case .keynote:
            // While playing, step with show next/previous for neighbors (keeps transitions), or restart the
            // show from the slide for jumps. While editing, select the slide.
            script = """
                tell application "Keynote"
                    if playing then
                        set n to slide number of current slide of front document
                        if \(number) is n + 1 then
                            show next
                        else if \(number) is n - 1 then
                            show previous
                        else if \(number) is not n then
                            start front document from slide \(number) of front document
                        end if
                    else
                        set current slide of front document to slide \(number) of front document
                    end if
                end tell
                """
        case .powerpoint:
            script = """
                tell application "Microsoft PowerPoint"
                    if (count of slide show windows) > 0 then
                        go to slide (slide show view of slide show window 1) number \(number)
                    else
                        go to slide (view of document window 1) number \(number)
                    end if
                end tell
                """
        }
        try SlideApp.run(script)
    }

    private static func sendArrows(to app: NSRunningApplication, steps: Int) -> Result {
        guard AXIsProcessTrusted() else { return .needsAccessibility }
        let key = CGKeyCode(steps > 0 ? kVK_RightArrow : kVK_LeftArrow)
        let count = min(abs(steps), 60)
        quietUntil = Date().addingTimeInterval(0.4 + Double(count) * 0.05)
        let source = CGEventSource(stateID: .hidSystemState)
        for i in 0..<count {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.04) {
                for down in [true, false] {
                    let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down)
                    event?.flags = [] // a plain arrow, even while ⌃⌥ is still held from the hotkey
                    event?.postToPid(app.processIdentifier)
                }
            }
        }
        return .moved
    }
}
