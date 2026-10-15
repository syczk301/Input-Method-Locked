import AppKit

// Original vector artwork. Regenerate every PNG size from these paths.
func rounded(_ rect: NSRect, _ radius: CGFloat, _ color: NSColor) {
    color.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}

func artwork() {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(calibratedWhite: 0.08, alpha: 0.22)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824),
                            xRadius: 184, yRadius: 184)
    NSGradient(starting: NSColor(srgbRed: 0.06, green: 0.22, blue: 0.37, alpha: 1),
               ending: NSColor(srgbRed: 0.10, green: 0.57, blue: 0.64, alpha: 1))!.draw(in: tile, angle: 65)
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    let keyboardShadow = NSShadow()
    keyboardShadow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.25)
    keyboardShadow.shadowBlurRadius = 22
    keyboardShadow.shadowOffset = NSSize(width: 0, height: -14)
    keyboardShadow.set()
    rounded(NSRect(x: 220, y: 324, width: 584, height: 372), 56,
            NSColor(srgbRed: 0.86, green: 0.93, blue: 0.95, alpha: 1))
    NSGraphicsContext.restoreGraphicsState()
    rounded(NSRect(x: 220, y: 338, width: 584, height: 358), 56,
            NSColor(srgbRed: 0.96, green: 0.99, blue: 1, alpha: 1))

    let keyColor = NSColor(srgbRed: 0.20, green: 0.42, blue: 0.52, alpha: 1)
    for y: CGFloat in [590, 508] {
        for column in 0..<6 {
            rounded(NSRect(x: 262 + CGFloat(column) * 82, y: y, width: 64, height: 58), 12, keyColor)
        }
    }
    rounded(NSRect(x: 262, y: 402, width: 94, height: 66), 13, keyColor)
    rounded(NSRect(x: 376, y: 402, width: 238, height: 66), 13, keyColor)
    rounded(NSRect(x: 634, y: 402, width: 102, height: 66), 13, keyColor)

    NSGraphicsContext.saveGraphicsState()
    let badgeShadow = NSShadow()
    badgeShadow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.24)
    badgeShadow.shadowBlurRadius = 18
    badgeShadow.shadowOffset = NSSize(width: 0, height: -8)
    badgeShadow.set()
    NSColor(srgbRed: 1, green: 0.66, blue: 0.32, alpha: 1).setFill()
    let badge = NSBezierPath(ovalIn: NSRect(x: 636, y: 228, width: 244, height: 244))
    badge.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSColor(srgbRed: 1, green: 0.87, blue: 0.70, alpha: 1).setStroke()
    let rim = NSBezierPath(ovalIn: NSRect(x: 641, y: 233, width: 234, height: 234))
    rim.lineWidth = 8
    rim.stroke()

    NSGraphicsContext.saveGraphicsState()
    let transform = NSAffineTransform()
    transform.translateX(by: 758, yBy: 358)
    transform.rotate(byDegrees: -32)
    transform.concat()
    let white = NSColor.white
    rounded(NSRect(x: -24, y: -12, width: 48, height: 70), 8, white)
    rounded(NSRect(x: -52, y: 48, width: 104, height: 30), 13, white)
    rounded(NSRect(x: -53, y: -28, width: 106, height: 28), 11, white)
    let needle = NSBezierPath()
    needle.move(to: NSPoint(x: -9, y: -24))
    needle.line(to: NSPoint(x: 0, y: -92))
    needle.line(to: NSPoint(x: 9, y: -24))
    needle.close()
    white.setFill()
    needle.fill()
    NSGraphicsContext.restoreGraphicsState()
}

func render(_ pixels: Int, to url: URL) throws {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                              isPlanar: false, colorSpaceName: .deviceRGB,
                              bytesPerRow: pixels * 4, bitsPerPixel: 32)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let scale = NSAffineTransform()
    scale.scale(by: CGFloat(pixels) / 1024)
    scale.concat()
    artwork()
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let resources = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    try render(size, to: output.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(size * 2, to: output.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
try render(1024, to: resources.appendingPathComponent("AppIcon.png"))
try render(256, to: resources.appendingPathComponent("AppIcon-preview.png"))
