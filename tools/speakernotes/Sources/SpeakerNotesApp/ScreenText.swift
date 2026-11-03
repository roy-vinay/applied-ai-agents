import AppKit
import ScreenCaptureKit
import Vision

/// Text read off a picture of a slide, with the line most likely to be its title.
struct ScreenText {
    var lines: [String]
    var title: String?

    /// Reads text with Apple's on-device text recognition. Runs on the calling thread.
    /// `fast` reads big text (a slide title) in a fraction of the time; `accurate` is the careful pass.
    static func read(_ image: CGImage, fast: Bool = false) throws -> ScreenText {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = fast ? .fast : .accurate
        request.usesLanguageCorrection = !fast
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

/// A tiny grayscale thumbnail, to tell cheaply whether the slide changed since the last look.
struct Fingerprint {
    private let pixels: [UInt8]

    init?(_ image: CGImage) {
        let w = 32, h = 18
        var buffer = [UInt8](repeating: 0, count: w * h)
        guard let ctx = CGContext(data: &buffer, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return nil }
        ctx.interpolationQuality = .low
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        pixels = buffer
    }

    /// True when the two look the same (a blinking cursor or a clock doesn't count as a new slide).
    func matches(_ other: Fingerprint?) -> Bool {
        guard let other, other.pixels.count == pixels.count else { return false }
        let diff = zip(pixels, other.pixels).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }
        return Double(diff) / Double(pixels.count) < 1.5
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
        let scale = min(1.0, 1280 / max(window.frame.width, 1))
        config.width = Int(window.frame.width * scale)
        config.height = Int(window.frame.height * scale)
        config.showsCursor = false
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }
}
