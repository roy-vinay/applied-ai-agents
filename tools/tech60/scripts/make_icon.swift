// Draws the Tech60 app icon (the "front page" design) at every size macOS needs.
// Usage: swift scripts/make_icon.swift <output.iconset> [preview.png]
// Coordinates are in a 100 x 100 design space, y down, matching the design canvas.
import AppKit

func hex(_ v: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
}

let ink = hex(0x17181C), accent = hex(0xD9480F), photo = hex(0xD3DCEA), grey = hex(0xA6A9B0)

/// An arc that starts at 12 o'clock and runs clockwise for `fraction` of the circle (y-down space).
func ring(center: CGPoint, radius: CGFloat, fraction: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    let steps = 64
    for i in 0...steps {
        let a = -CGFloat.pi / 2 + CGFloat(i) / CGFloat(steps) * 2 * .pi * fraction
        let p = CGPoint(x: center.x + radius * cos(a), y: center.y + radius * sin(a))
        i == 0 ? path.move(to: p) : path.line(to: p)
    }
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    return path
}

func bar(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: NSColor, r: CGFloat = 0) {
    color.setFill()
    NSBezierPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), xRadius: r, yRadius: r).fill()
}

func drawIcon() {
    // Apple's icon grid: the tile fills about 80% of the canvas, so map the 4...96 design onto 10...90.
    let t = NSAffineTransform()
    t.translateX(by: 10, yBy: 10.5)
    t.scale(by: 80 / 92)
    t.translateX(by: -4, yBy: -4)

    let tile = NSBezierPath(roundedRect: CGRect(x: 4, y: 4, width: 92, height: 92), xRadius: 21, yRadius: 21)
    NSGraphicsContext.saveGraphicsState()
    t.concat()
    // Soft shadow under the tile, like other Mac icons.
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
    shadow.shadowBlurRadius = 3.5
    shadow.shadowOffset = NSSize(width: 0, height: -1.6)   // flipped context: negative moves it down
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    hex(0xFFFFFF).setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: hex(0xFFFFFF), ending: hex(0xEFEDE9))!.draw(in: tile, angle: 90)
    hex(0xD6D2CB).setStroke()
    tile.lineWidth = 0.5
    tile.stroke()

    // Masthead: "Tech" in the system serif, sized to 44 units wide, baseline at 33.
    let base = NSFont.systemFont(ofSize: 21, weight: .heavy)
    let serif = base.fontDescriptor.withDesign(.serif).flatMap { NSFont(descriptor: $0, size: 21) } ?? base
    let probe = NSAttributedString(string: "Tech", attributes: [.font: serif])
    let size = 21 * 44 / probe.size().width
    let font = NSFont(descriptor: serif.fontDescriptor, size: size) ?? serif
    let text = NSAttributedString(string: "Tech", attributes: [.font: font, .foregroundColor: ink, .kern: -0.3])
    text.draw(at: CGPoint(x: 17, y: 33 - font.ascender))

    let r = ring(center: CGPoint(x: 74, y: 26), radius: 6.8, fraction: 0.82)
    r.lineWidth = 2.8
    accent.setStroke()
    r.stroke()

    bar(17, 39, 66, 1.3, ink)
    bar(17, 42, 66, 1.3, ink)
    bar(17, 48, 30, 22, photo, r: 3)
    bar(52, 49, 31, 4, ink, r: 1.2)
    bar(52, 56, 23, 4, ink, r: 1.2)
    bar(52, 64.5, 31, 2.2, grey, r: 1.1)
    bar(17, 76, 66, 2.2, grey, r: 1.1)
    bar(17, 81, 46, 2.2, grey, r: 1.1)
    NSGraphicsContext.restoreGraphicsState()
}

func png(pixels: Int) -> Data {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let cg = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    cg.translateBy(x: 0, y: CGFloat(pixels))
    cg.scaleBy(x: CGFloat(pixels) / 100, y: -CGFloat(pixels) / 100)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
    drawIcon()
    NSGraphicsContext.current = nil
    let rep = NSBitmapImageRep(cgImage: cg.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

let args = CommandLine.arguments
guard args.count >= 2 else { print("usage: make_icon.swift <out.iconset> [preview.png]"); exit(1) }
let dir = URL(fileURLWithPath: args[1])
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
for pt in [16, 32, 128, 256, 512] {
    try png(pixels: pt).write(to: dir.appendingPathComponent("icon_\(pt)x\(pt).png"))
    try png(pixels: pt * 2).write(to: dir.appendingPathComponent("icon_\(pt)x\(pt)@2x.png"))
}
if args.count >= 3 { try png(pixels: 512).write(to: URL(fileURLWithPath: args[2])) }
print("Wrote \(dir.path)")
