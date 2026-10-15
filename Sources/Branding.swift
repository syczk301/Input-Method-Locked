import AppKit

enum Branding {
    static func statusIcon(pinned: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 22, height: 18), flipped: false) { _ in
            NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil)?
                .draw(in: NSRect(x: 0, y: 3, width: 20, height: 13))
            if pinned {
                let context = NSGraphicsContext.current!.cgContext
                context.saveGState()
                context.setBlendMode(.clear)
                context.fillEllipse(in: CGRect(x: 12, y: 0, width: 11, height: 12))
                context.restoreGState()
                NSImage(systemSymbolName: "pin.fill", accessibilityDescription: nil)?
                    .draw(in: NSRect(x: 14, y: 0, width: 7, height: 11))
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = pinned ? "Input Method Locked · 锁定中" : "Input Method Locked · 已暂停"
        return image
    }
}
