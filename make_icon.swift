import AppKit
import Foundation
let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("App/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
    bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor(calibratedRed: 0.025, green: 0.22, blue: 0.25, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1024, height: 1024)).fill()
let glow = NSGradient(starting: NSColor(calibratedRed: 0.02, green: 0.64, blue: 0.59, alpha: 1),
                      ending: NSColor(calibratedRed: 0.02, green: 0.31, blue: 0.39, alpha: 1))!
glow.draw(in: NSBezierPath(ovalIn: NSRect(x: -200, y: 150, width: 1300, height: 1300)), angle: -45)
NSColor.white.setStroke()
let path = NSBezierPath(); path.lineWidth = 30; path.lineCapStyle = .round
let heights: [CGFloat] = [100, 185, 280, 410, 540, 360, 240, 150, 90]
for (index, height) in heights.enumerated() {
    let x = CGFloat(index)*72+224
    path.move(to: NSPoint(x: x, y: 512-height/2)); path.line(to: NSPoint(x: x, y: 512+height/2))
}
path.stroke()
let sparkle = NSBezierPath()
sparkle.move(to: NSPoint(x: 794, y: 832)); sparkle.line(to: NSPoint(x: 814, y: 884))
sparkle.line(to: NSPoint(x: 834, y: 832)); sparkle.line(to: NSPoint(x: 886, y: 812))
sparkle.line(to: NSPoint(x: 834, y: 792)); sparkle.line(to: NSPoint(x: 814, y: 740))
sparkle.line(to: NSPoint(x: 794, y: 792)); sparkle.line(to: NSPoint(x: 742, y: 812)); sparkle.close()
NSColor.white.setFill(); sparkle.fill()
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("AppIcon.png"))
let contents = """
{"images":[{"filename":"AppIcon.png","idiom":"universal","platform":"ios","size":"1024x1024"}],"info":{"author":"xcode","version":1}}
"""
try contents.write(to: directory.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
try "{\"info\":{\"author\":\"xcode\",\"version\":1}}".write(to: directory.deletingLastPathComponent().appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
