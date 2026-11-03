import AppKit
import SpeakerNotesCore

// Test mode for CI: read a slide image and print which notes slide it matches.
//   SpeakerNotes --match-image slide.png notes.md
let arguments = CommandLine.arguments
if let i = arguments.firstIndex(of: "--match-image"), arguments.count > i + 2 {
    let imagePath = arguments[i + 1], notesPath = arguments[i + 2]
    guard let image = NSImage(contentsOfFile: imagePath)?.cgImage(forProposedRect: nil, context: nil, hints: nil),
          let notes = try? String(contentsOfFile: notesPath, encoding: .utf8),
          let text = try? ScreenText.read(image) else {
        print("error: couldn't read \(imagePath) or \(notesPath)")
        exit(2)
    }
    let slides = NotesParser.slides(in: notes)
    print("title read: \(text.title ?? "none")")
    print("lines read: \(text.lines.joined(separator: " | "))")
    guard let m = SlideMatcher.match(screenTitle: text.title, screenLines: text.lines, slides: slides, near: 0) else {
        print("no match")
        exit(1)
    }
    print("matched slide \(m.index + 1) \"\(slides[m.index].title)\" score=\(String(format: "%.2f", m.score)) margin=\(String(format: "%.2f", m.margin)) confident=\(SlideMatcher.isConfident(m))")
    exit(SlideMatcher.isConfident(m) ? 0 : 1)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular) // a Dock icon, so it's always easy to find and relaunch
app.run()
