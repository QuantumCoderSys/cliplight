import AppKit
import Foundation
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let s = CGFloat(pixels)
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor(calibratedRed: 0.35, green: 0.38, blue: 0.81, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: s*0.05, y: s*0.05, width: s*0.9, height: s*0.9), xRadius: s*0.22, yRadius: s*0.22).fill()
        NSColor.white.setStroke()
        let clipboard = NSBezierPath(roundedRect: NSRect(x: s*0.28, y: s*0.19, width: s*0.44, height: s*0.57), xRadius: s*0.055, yRadius: s*0.055)
        clipboard.lineWidth = s*0.032; clipboard.stroke()
        NSColor.white.setFill()
        NSBezierPath(roundedRect: NSRect(x: s*0.39, y: s*0.715, width: s*0.22, height: s*0.11), xRadius: s*0.035, yRadius: s*0.035).fill()
        for (offset,width) in [(0.0,0.24),(0.11,0.24),(0.22,0.15)] {
            let line = NSBezierPath()
            line.move(to: NSPoint(x: s*0.38, y: s*(0.60-offset)))
            line.line(to: NSPoint(x: s*(0.38+width), y: s*(0.60-offset)))
            line.lineWidth = s*0.027; line.lineCapStyle = .round; line.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
