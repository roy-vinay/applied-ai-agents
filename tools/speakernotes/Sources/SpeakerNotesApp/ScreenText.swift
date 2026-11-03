import AppKit
import ScreenCaptureKit
import Vision

/// Text read off a picture of a slide, with the line most likely to be its title.
struct ScreenText {
    var lines: [String]
    var title: String?

    /// Reads text with Apple's on-device text recognition. Runs on the calling thread.
    static func read(_ image: CGImage) throws -> ScreenText {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        let found = (request.results ?? []).compactMap { o -> (String, CGRect)? in
            guard let text = o.topCandidates(1).first?.string.trimmingCharacters(in: .whitespaces), !text.isEmpty
            else { return nil }
            return (text, o.boundingBox)
        }
        // Vision's boxes run from the bottom left, 0 to 1. Order lines top to bottom.
        let ordered = found.sorted { $0.1.midY > $1.1.midY }
        // The title: the tallest text in the top half that reads like words, not a page number.
        let title = ordered
            .filter { $0.1.midY > 0.45 && $0.0.count >= 3 && $0.0.contains(where: \.isLetter) }
            .max { $0.1.height < $1.1.height }?.0
        return ScreenText(lines: ordered.map { $0.0 }, title: title)
    }
}

/// Takes a picture of the slides window, so its text can be read. Needs Screen Recording permission.
@available(macOS 14.0, *)
enum SlideWindowCapture {
    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    /// Shows macOS's permission prompt once. It takes effect after SpeakerNotes is reopened.
    @discardableResult
    static func requestPermission() -> Bool { CGRequestScreenCaptureAccess() }

    /// The largest visible window of an app, captured at a size that's easy to read and quick to process.
    static func capture(pid: pid_t) async throws -> CGImage? {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        let windows = content.windows.filter {
            $0.owningApplication?.processID == pid && $0.isOnScreen && $0.frame.width >= 300 && $0.frame.height >= 200
        }
        guard let window = windows.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height })
        else { return nil }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        let scale = min(1.0, 1600 / max(window.frame.width, 1))
        config.width = Int(window.frame.width * scale)
        config.height = Int(window.frame.height * scale)
        config.showsCursor = false
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }
}
