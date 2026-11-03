// Prints the window number of the largest on-screen window owned by the named app.
// With --bounds, prints that window's frame as x,y,w,h in screen points (for screencapture -R).
import CoreGraphics
import Foundation

let args = CommandLine.arguments.dropFirst()
let name = args.first(where: { !$0.hasPrefix("--") })?.lowercased() ?? "speakernotes"
let wantBounds = args.contains("--bounds")
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
var best: (Int, [String: CGFloat], CGFloat)?
for w in windows where (w[kCGWindowOwnerName as String] as? String)?.lowercased() == name {
    guard let n = w[kCGWindowNumber as String] as? Int,
          let b = w[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
    let area = (b["Width"] ?? 0) * (b["Height"] ?? 0)
    if area > (best?.2 ?? 0) { best = (n, b, area) }
}
guard let best else {
    FileHandle.standardError.write(Data("No window found for \(name). Owners: \(Set(windows.compactMap { $0[kCGWindowOwnerName as String] as? String }))\n".utf8))
    exit(1)
}
if wantBounds {
    let b = best.1
    print("\(Int(b["X"] ?? 0)),\(Int(b["Y"] ?? 0)),\(Int(b["Width"] ?? 0)),\(Int(b["Height"] ?? 0))")
} else {
    print(best.0)
}
