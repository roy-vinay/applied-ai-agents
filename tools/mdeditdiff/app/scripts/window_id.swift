// Prints the window number of the first normal on-screen window owned by the named app.
import CoreGraphics
import Foundation

let name = CommandLine.arguments.dropFirst().first?.lowercased() ?? "mdeditdiff"
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
for w in windows {
    let owner = (w[kCGWindowOwnerName as String] as? String)?.lowercased()
    if owner == name, (w[kCGWindowLayer as String] as? Int) == 0, let n = w[kCGWindowNumber as String] as? Int {
        print(n)
        exit(0)
    }
}
FileHandle.standardError.write(Data("No window found for \(name). Owners: \(Set(windows.compactMap { $0[kCGWindowOwnerName as String] as? String }))\n".utf8))
exit(1)
