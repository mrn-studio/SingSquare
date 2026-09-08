// Renders the app icon (green-accent variant from icon-refined-variants.svg)
// into SingSquare.iconset/ and builds AppIcon.icns.
// Run: swift makeicon.swift
import AppKit

func c(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: 1)
}
let bg = c(0x0f1a13), dim = c(0x2e5c3e), bright = c(0x4de08a)

// (x, y, w, h, r, fill) in the SVG's 220x220 space, y measured from the top.
let shapes: [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGColor)] = [
    (0, 0, 220, 220, 49, bg),
    (48, 70, 124, 16, 8, dim),
    (38, 102, 144, 18, 9, bright),
    (54, 136, 112, 16, 8, dim),
]

func png(_ px: Int) -> Data {
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let canvas = CGFloat(px)
    let margin = canvas * 100 / 1024                 // standard macOS icon padding
    let scale = (canvas - margin * 2) / 220
    ctx.translateBy(x: margin, y: margin)
    ctx.scaleBy(x: scale, y: scale)
    ctx.translateBy(x: 0, y: 220); ctx.scaleBy(x: 1, y: -1)   // flip to SVG's top-left origin
    for (x, y, w, h, r, fill) in shapes {
        ctx.addPath(CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h),
                           cornerWidth: r, cornerHeight: r, transform: nil))
        ctx.setFillColor(fill)
        ctx.fillPath()
    }
    return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
}

let dir = "SingSquare.iconset"
try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64),
                   ("128x128", 128), ("128x128@2x", 256), ("256x256", 256),
                   ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try! png(px).write(to: URL(fileURLWithPath: "\(dir)/icon_\(name).png"))
}

let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", dir, "-o", "AppIcon.icns"]
try! p.run(); p.waitUntilExit()
print(p.terminationStatus == 0 ? "wrote AppIcon.icns" : "iconutil failed")
