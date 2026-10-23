// Draws the app icon: swift Resources/make-icon.swift → Resources/AppIcon.png and AppIcon.icns
import AppKit

let size = 1024
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

// The tile, on the standard macOS icon grid: 824 pt with ~22% corner radius, centred.
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: color(0x000000, 0.3))
ctx.addPath(tilePath)
ctx.setFillColor(color(0x2F3349))
ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(tilePath)
ctx.clip()
let gradient = CGGradient(colorsSpace: nil, colors: [color(0x3D405B), color(0x2B2E44)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])

let shelfTop: CGFloat = 322

/// A book standing on the shelf, tilted by `angle` degrees around its bottom-left corner.
func book(x: CGFloat, width: CGFloat, height: CGFloat, fill: UInt32, angle: CGFloat = 0) {
    ctx.saveGState()
    ctx.translateBy(x: x, y: shelfTop)
    ctx.rotate(by: angle * .pi / 180)
    let r = CGRect(x: 0, y: 0, width: width, height: height)
    ctx.addPath(CGPath(roundedRect: r, cornerWidth: 10, cornerHeight: 10, transform: nil))
    ctx.setFillColor(color(fill))
    ctx.fillPath()
    // Two thin bands across the spine, the only detail.
    ctx.setFillColor(color(0x2B2E44, 0.22))
    ctx.fill(CGRect(x: 0, y: height - 70, width: width, height: 12))
    ctx.fill(CGRect(x: 0, y: height - 96, width: width, height: 6))
    ctx.restoreGState()
}

book(x: 250, width: 96, height: 380, fill: 0xF2CC8F)
book(x: 358, width: 74, height: 318, fill: 0xE07A5F)
book(x: 444, width: 108, height: 424, fill: 0x81B29A)
// Leaning on the green one: its top-left corner touches the green book's right side.
let lean: CGFloat = 18, leanHeight: CGFloat = 340
book(x: 552 + leanHeight * sin(lean * .pi / 180), width: 84, height: leanHeight, fill: 0xF4F1DE, angle: lean)

// The shelf.
ctx.addPath(CGPath(roundedRect: CGRect(x: 210, y: shelfTop - 26, width: 604, height: 26),
                   cornerWidth: 8, cornerHeight: 8, transform: nil))
ctx.setFillColor(color(0xF4F1DE))
ctx.fillPath()
ctx.restoreGState()

let dir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let png = dir.appendingPathComponent("AppIcon.png")
let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try rep.representation(using: .png, properties: [:])!.write(to: png)

// Every size macOS wants, then pack them into .icns.
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
func run(_ tool: String, _ args: [String]) throws {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: tool)
    p.arguments = args
    p.standardOutput = FileHandle.nullDevice
    try p.run()
    p.waitUntilExit()
    guard p.terminationStatus == 0 else { throw NSError(domain: tool, code: Int(p.terminationStatus)) }
}
for s in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(s)x\(s)\(scale == 2 ? "@2x" : "").png"
        try run("/usr/bin/sips", ["-z", "\(s * scale)", "\(s * scale)", png.path, "--out", iconset.appendingPathComponent(name).path])
    }
}
try run("/usr/bin/iconutil", ["-c", "icns", iconset.path, "-o", dir.appendingPathComponent("AppIcon.icns").path])
print("Done: \(dir.appendingPathComponent("AppIcon.icns").path)")
