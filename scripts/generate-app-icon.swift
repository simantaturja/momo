#!/usr/bin/env swift
//
// Renders Momo's dumpling mark onto a terracotta squircle at every size macOS
// needs, builds assets/AppIcon.icns, and drops a 512x512 assets/icon-social.png
// for favicon/social use. Re-run whenever the artwork changes.
//
// Usage (from repo root): swift scripts/generate-app-icon.swift
//
import AppKit

func renderIcon(size: CGFloat) -> NSImage {
    NSImage(size: NSSize(width: size, height: size), flipped: true) { _ in
        guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

        let radius = size * 224.0 / 1024.0
        let bg = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: size, height: size),
                              xRadius: radius, yRadius: radius)
        NSColor(srgbRed: 201.0 / 255, green: 121.0 / 255, blue: 58.0 / 255, alpha: 1).setFill() // #C9793A
        bg.fill()

        ctx.saveGState()
        let scale = size * 40.0 / 1024.0
        ctx.translateBy(x: size * 152.0 / 1024.0, y: size * 136.0 / 1024.0)
        ctx.scaleBy(x: scale, y: scale)

        let body = NSBezierPath()
        body.move(to: NSPoint(x: 2.6, y: 14))
        body.curve(to: NSPoint(x: 15.4, y: 14), controlPoint1: NSPoint(x: 5.5, y: 15.7), controlPoint2: NSPoint(x: 12.5, y: 15.7))
        body.curve(to: NSPoint(x: 11.6, y: 6), controlPoint1: NSPoint(x: 16.6, y: 10.2), controlPoint2: NSPoint(x: 14.8, y: 7))
        body.curve(to: NSPoint(x: 9.9, y: 4.7), controlPoint1: NSPoint(x: 12.1, y: 4.4), controlPoint2: NSPoint(x: 10.9, y: 3.9))
        body.curve(to: NSPoint(x: 8.1, y: 4.7), controlPoint1: NSPoint(x: 9.4, y: 3.1), controlPoint2: NSPoint(x: 8.6, y: 3.1))
        body.curve(to: NSPoint(x: 6.4, y: 6), controlPoint1: NSPoint(x: 7.1, y: 3.9), controlPoint2: NSPoint(x: 5.9, y: 4.4))
        body.curve(to: NSPoint(x: 2.6, y: 14), controlPoint1: NSPoint(x: 3.2, y: 7), controlPoint2: NSPoint(x: 1.4, y: 10.2))
        body.close()
        NSColor(srgbRed: 251.0 / 255, green: 231.0 / 255, blue: 192.0 / 255, alpha: 1).setFill() // #FBE7C0
        body.fill()
        NSColor(srgbRed: 122.0 / 255, green: 74.0 / 255, blue: 30.0 / 255, alpha: 1).setStroke() // #7A4A1E
        body.lineWidth = 0.35
        body.stroke()

        NSColor(srgbRed: 176.0 / 255, green: 110.0 / 255, blue: 30.0 / 255, alpha: 1).setStroke() // #B06E1E
        let pleats: [(NSPoint, NSPoint, NSPoint)] = [
            (NSPoint(x: 6.6, y: 6.8), NSPoint(x: 4.6, y: 12), NSPoint(x: 5.0, y: 9)),
            (NSPoint(x: 8.9, y: 6.4), NSPoint(x: 8.6, y: 12.4), NSPoint(x: 8.2, y: 9.2)),
            (NSPoint(x: 11.2, y: 6.8), NSPoint(x: 13.2, y: 12), NSPoint(x: 12.8, y: 9.0)),
        ]
        for (from, to, cp) in pleats {
            let p = NSBezierPath()
            p.move(to: from)
            p.curve(to: to, controlPoint1: cp, controlPoint2: cp)
            p.lineWidth = 1.0
            p.lineCapStyle = .round
            p.stroke()
        }

        let topknot = NSBezierPath()
        topknot.move(to: NSPoint(x: 6.6, y: 5.9))
        topknot.curve(to: NSPoint(x: 11.4, y: 5.9), controlPoint1: NSPoint(x: 8, y: 6.7), controlPoint2: NSPoint(x: 10, y: 6.7))
        topknot.lineWidth = 0.9
        topknot.lineCapStyle = .round
        topknot.stroke()

        ctx.restoreGState()
        return true
    }
}

func writePNG(_ image: NSImage, to url: URL) throws {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("Failed to encode PNG for \(url.lastPathComponent)")
    }
    try png.write(to: url)
}

let fm = FileManager.default
let iconsetURL = URL(fileURLWithPath: "assets/AppIcon.iconset")
try? fm.removeItem(at: iconsetURL)
try fm.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let specs: [(name: String, px: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for spec in specs {
    let image = renderIcon(size: CGFloat(spec.px))
    try writePNG(image, to: iconsetURL.appendingPathComponent("\(spec.name).png"))
}

try writePNG(renderIcon(size: 512), to: URL(fileURLWithPath: "assets/icon-social.png"))

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconsetURL.path, "-o", "assets/AppIcon.icns"]
try task.run()
task.waitUntilExit()
guard task.terminationStatus == 0 else {
    fatalError("iconutil failed with status \(task.terminationStatus)")
}

try fm.removeItem(at: iconsetURL)
print("Wrote assets/AppIcon.icns and assets/icon-social.png")
