import AppKit

/// Talks to Keynote and PowerPoint through AppleScript: which slide is showing, and the deck's own notes.
/// macOS asks once for permission to control each app (Privacy & Security > Automation).
enum SlideApp: String {
    case keynote, powerpoint

    static let keynoteID = "com.apple.iWork.Keynote"
    static let powerpointID = "com.microsoft.Powerpoint"

    var name: String { self == .keynote ? "Keynote" : "PowerPoint" }

    init?(bundleID: String?) {
        switch bundleID {
        case Self.keynoteID: self = .keynote
        case Self.powerpointID: self = .powerpoint
        default: return nil
        }
    }

    var isRunning: Bool {
        let id = self == .keynote ? Self.keynoteID : Self.powerpointID
        return !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty
    }

    /// Whether a slideshow is playing, so the notes can follow it even while another app is in front.
    var isPlaying: Bool {
        guard isRunning else { return false }
        let script = self == .keynote
            ? "tell application \"Keynote\" to return playing"
            : "tell application \"Microsoft PowerPoint\" to return (count of slide show windows) > 0"
        return (try? Self.run(script).booleanValue) ?? false
    }

    /// The slide showing now, 1 for the first. Nil when no deck is open.
    func currentSlide() throws -> Int? {
        guard isRunning else { return nil }
        let script: String
        switch self {
        case .keynote:
            script = """
                tell application "Keynote"
                    if (count of documents) is 0 then return 0
                    return slide number of current slide of front document
                end tell
                """
        case .powerpoint:
            script = """
                tell application "Microsoft PowerPoint"
                    try
                        if (count of slide show windows) > 0 then return slide index of slide of slide show view of slide show window 1
                    end try
                    try
                        return slide index of slide of view of document window 1
                    end try
                    try
                        return slide index of slide range of selection of document window 1
                    end try
                    return 0
                end tell
                """
        }
        let n = Int(try Self.run(script).int32Value)
        return n > 0 ? n : nil
    }

    /// The front deck's slide titles and presenter notes, and where the deck is saved.
    func importNotes() throws -> (deck: URL?, slides: [(title: String, notes: String)]) {
        let fieldSep = "\u{1F}", slideSep = "\u{1E}"
        let script: String
        switch self {
        case .keynote:
            script = """
                tell application "Keynote"
                    set d to front document
                    set out to {}
                    repeat with s in slides of d
                        set t to ""
                        try
                            set t to object text of default title item of s
                        end try
                        set n to ""
                        try
                            set n to presenter notes of s
                        end try
                        set end of out to (t & (ASCII character 31) & n)
                    end repeat
                    set p to ""
                    try
                        set p to POSIX path of (file of d as alias)
                    end try
                    set AppleScript's text item delimiters to (ASCII character 30)
                    return p & (ASCII character 30) & (out as text)
                end tell
                """
        case .powerpoint:
            script = """
                tell application "Microsoft PowerPoint"
                    set p to active presentation
                    set out to {}
                    repeat with i from 1 to (count of slides of p)
                        set s to slide i of p
                        set t to ""
                        try
                            set t to content of text range of text frame of place holder 1 of s
                        end try
                        set n to ""
                        try
                            set n to content of text range of text frame of place holder 2 of notes page of s
                        end try
                        set end of out to (t & (ASCII character 31) & n)
                    end repeat
                    set f to ""
                    try
                        set f to POSIX path of (full name of p)
                    end try
                    try
                        if f is "" then set f to full name of p
                    end try
                    set AppleScript's text item delimiters to (ASCII character 30)
                    return f & (ASCII character 30) & (out as text)
                end tell
                """
        }
        let raw = (try Self.run(script).stringValue ?? "")
            .replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var parts = raw.components(separatedBy: slideSep)
        let path = parts.isEmpty ? "" : parts.removeFirst()
        let slides = parts.map { part -> (String, String) in
            let f = part.components(separatedBy: fieldSep)
            let title = (f.first ?? "").replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
            return (title, f.count > 1 ? f[1].trimmingCharacters(in: .whitespacesAndNewlines) : "")
        }
        let deck = path.hasPrefix("/") ? URL(fileURLWithPath: path) : nil
        return (deck, slides)
    }

    /// Turns a deck's notes into SpeakerNotes Markdown: one numbered heading per slide.
    static func markdown(from slides: [(title: String, notes: String)]) -> String {
        slides.enumerated().map { i, s in
            let title = s.title.isEmpty ? "Slide \(i + 1)" : s.title
            let notes = s.notes.isEmpty ? "_No notes for this slide._" : s.notes
            return "## \(i + 1). \(title)\n\n\(notes)"
        }.joined(separator: "\n\n---\n\n") + "\n"
    }

    // MARK: AppleScript

    struct ScriptError: LocalizedError {
        let number: Int
        let message: String
        var notAllowed: Bool { number == -1743 }
        var errorDescription: String? { message }
    }

    private static var compiled: [String: NSAppleScript] = [:]

    @discardableResult
    static func run(_ source: String) throws -> NSAppleEventDescriptor {
        let script = compiled[source] ?? NSAppleScript(source: source)!
        compiled[source] = script
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            throw ScriptError(number: error[NSAppleScript.errorNumber] as? Int ?? 0,
                              message: error[NSAppleScript.errorMessage] as? String ?? "AppleScript failed")
        }
        return result
    }
}
