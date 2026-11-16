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

    let casing = NSColor(srgbRed: 0.96, green: 0.99, blue: 1, alpha: 1)
    let detail = NSColor(srgbRed: 0.12, green: 0.36, blue: 0.44, alpha: 1)
    let wheel = NSColor(srgbRed: 0.12, green: 0.71, blue: 0.69, alpha: 1)

    NSGraphicsContext.saveGraphicsState()
    let deviceShadow = NSShadow()
    deviceShadow.shadowColor = NSColor(calibratedWhite: 0.06, alpha: 0.28)
    deviceShadow.shadowBlurRadius = 20
    deviceShadow.shadowOffset = NSSize(width: 0, height: -12)
    deviceShadow.set()
    rounded(NSRect(x: 198, y: 370, width: 432, height: 284), 52, casing)
    rounded(NSRect(x: 680, y: 332, width: 146, height: 360), 73, casing)
    NSGraphicsContext.restoreGraphicsState()

    for y: CGFloat in [556, 480] {
        for column in 0..<5 {
            rounded(NSRect(x: 236 + CGFloat(column) * 74, y: y, width: 60, height: 57), 12, detail)
        }
    }
    rounded(NSRect(x: 236, y: 406, width: 60, height: 55), 12, detail)
    rounded(NSRect(x: 310, y: 406, width: 208, height: 55), 12, detail)
    rounded(NSRect(x: 532, y: 406, width: 60, height: 55), 12, detail)

    rounded(NSRect(x: 727, y: 535, width: 52, height: 112), 26, detail)
    rounded(NSRect(x: 740, y: 558, width: 26, height: 66), 13, wheel)
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
