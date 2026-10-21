// Prints the window number of the first normal on-screen window owned by the named app.
// With --floating, also accepts windows above normal ones (the ticker and dot).
import CoreGraphics
import Foundation

let args = CommandLine.arguments.dropFirst()
let floating = args.contains("--floating")
let name = args.first { !$0.hasPrefix("--") }?.lowercased() ?? "tech60"
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
for w in windows {
    let owner = (w[kCGWindowOwnerName as String] as? String)?.lowercased()
    let layer = w[kCGWindowLayer as String] as? Int ?? -1
    // Skip the menu bar icon, which is also a floating Tech60 window.
    let top = ((w[kCGWindowBounds as String] as? [String: Any])?["Y"] as? Double) ?? 0
    if owner == name, layer == 0 || (floating && layer > 0 && top > 40), let n = w[kCGWindowNumber as String] as? Int {
        print(n)
        exit(0)
    }
}
FileHandle.standardError.write(Data("No window found for \(name). Owners: \(Set(windows.compactMap { $0[kCGWindowOwnerName as String] as? String }))\n".utf8))
exit(1)
