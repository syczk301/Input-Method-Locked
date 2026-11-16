import AppKit

enum Branding {
    static let menuWidth: CGFloat = 324

    static func menuSymbol(_ name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
        image?.isTemplate = true
        return image
    }

    static func sectionHeader(_ title: String, detail: String, symbol: String, tint: NSColor) -> NSMenuItem {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: menuWidth, height: 60))
        let card = NSView(frame: NSRect(x: 10, y: 6, width: menuWidth - 20, height: 48))
        card.autoresizingMask = [.width]
        card.wantsLayer = true
        card.layer?.cornerRadius = 10
        card.layer?.backgroundColor = tint.withAlphaComponent(0.10).cgColor
        view.addSubview(card)

        let icon = NSImageView(frame: NSRect(x: 10, y: 9, width: 30, height: 30))
        icon.wantsLayer = true
        icon.layer?.cornerRadius = 7
        icon.layer?.backgroundColor = tint.withAlphaComponent(0.15).cgColor
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 15, weight: .semibold))
        icon.imageScaling = .scaleNone
        icon.contentTintColor = tint
        card.addSubview(icon)

        let heading = NSTextField(labelWithString: title)
        heading.font = .systemFont(ofSize: 13, weight: .semibold)
        heading.frame = NSRect(x: 50, y: 25, width: card.bounds.width - 60, height: 17)
        heading.autoresizingMask = [.width]
        card.addSubview(heading)

        let subtitle = NSTextField(labelWithString: detail)
        subtitle.font = .systemFont(ofSize: 11, weight: .regular)
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byTruncatingTail
        subtitle.toolTip = detail
        subtitle.frame = NSRect(x: 50, y: 7, width: card.bounds.width - 60, height: 15)
        subtitle.autoresizingMask = [.width]
        card.addSubview(subtitle)

        let item = NSMenuItem(title: "\(title) · \(detail)", action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.view = view
        return item
    }

    static func statusIcon(locked: Bool, scrolling: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 29, height: 18), flipped: false) { _ in
            NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil)?
                .draw(in: NSRect(x: 0, y: 3, width: 17, height: 12), from: .zero,
                      operation: .sourceOver, fraction: locked ? 1 : 0.45)
            NSColor.black.withAlphaComponent(scrolling ? 1 : 0.45).setStroke()
            let mouse = NSBezierPath(roundedRect: NSRect(x: 20, y: 2.5, width: 8, height: 13),
                                     xRadius: 4, yRadius: 4)
            mouse.lineWidth = 1.35
            mouse.stroke()
            let wheel = NSBezierPath()
            wheel.lineWidth = 1.35
            wheel.lineCapStyle = .round
            wheel.move(to: NSPoint(x: 24, y: 9.5))
            wheel.line(to: NSPoint(x: 24, y: 12))
            wheel.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}
