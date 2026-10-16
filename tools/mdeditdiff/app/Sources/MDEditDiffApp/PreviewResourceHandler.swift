import Foundation
import WebKit

/// Serves local images to the preview. Only image files are served; remote images are
/// never fetched (the preview shows a notice instead).
final class PreviewResourceHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "mdeditdiff-res"

    /// The folder relative image paths resolve against: the document's folder.
    var baseDirectory: () -> URL? = { nil }

    private static let mimeTypes: [String: String] = [
        "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "gif": "image/gif",
        "svg": "image/svg+xml", "webp": "image/webp", "bmp": "image/bmp",
        "tif": "image/tiff", "tiff": "image/tiff", "heic": "image/heic", "ico": "image/x-icon",
    ]

    /// The bundled Preview folder (inside the .app, or the SwiftPM resource bundle when run with `swift run`).
    static var previewDirectory: URL? {
        if let url = Bundle.main.url(forResource: "Preview", withExtension: nil) { return url }
        return Bundle.module.url(forResource: "Preview", withExtension: nil)
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url,
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let raw = comps.queryItems?.first(where: { $0.name == "p" })?.value
        else { return fail(task) }

        let path = raw.removingPercentEncoding ?? raw
        let fileURL: URL
        if path.lowercased().hasPrefix("file:"), let u = URL(string: raw) {
            fileURL = u
        } else if path.hasPrefix("/") {
            fileURL = URL(fileURLWithPath: path)
        } else if let base = baseDirectory() {
            fileURL = URL(fileURLWithPath: path, relativeTo: base).standardizedFileURL
        } else {
            return fail(task)
        }

        guard let mime = Self.mimeTypes[fileURL.pathExtension.lowercased()],
              let data = try? Data(contentsOf: fileURL)
        else { return fail(task) }

        task.didReceive(URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: nil))
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}

    private func fail(_ task: WKURLSchemeTask) {
        task.didFailWithError(NSError(domain: NSURLErrorDomain, code: NSURLErrorFileDoesNotExist))
    }
}
