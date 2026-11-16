import AppKit
import ApplicationServices

final class ScrollSettings: NSObject {
    static let standaloneBundleID = "local.czk.ScrollDirection"
    private static let preferencesKey = "ScrollSettings"

    struct Preferences {
        var enabled: Bool
        var trackpad: ScrollDirection
        var mouse: ScrollDirection
        var smooth: Bool

        init(_ values: [String: Any]) {
            enabled = values["Enabled"] as? Bool ?? true
            trackpad = Self.direction(values["TrackpadDirection"], fallback: .natural)
            mouse = Self.direction(values["MouseDirection"], fallback: .classic)
            smooth = values["SmoothMouseScrolling"] as? Bool ?? true
        }

        private static func direction(_ raw: Any?, fallback: ScrollDirection) -> ScrollDirection {
            guard let number = raw as? Int,
                  [ScrollDirection.natural.rawValue, ScrollDirection.classic.rawValue,
                   ScrollDirection.system.rawValue].contains(number) else { return fallback }
            return ScrollDirection(rawValue: number) ?? fallback
        }

        var values: [String: Any] {
            ["Enabled": enabled, "TrackpadDirection": trackpad.rawValue,
             "MouseDirection": mouse.rawValue, "SmoothMouseScrolling": smooth]
        }
    }

    private let defaults: UserDefaults?
    private var preferences: Preferences
    private let tap = ScrollTap()
    private var timer: Timer?
    var onStatusChange: (() -> Void)?
    var isRunning: Bool { tap.isRunning }
    private(set) var statusLabel = "滚动设置已暂停"
    var menuSummary: String {
        guard statusLabel == "滚动设置运行中" else { return statusLabel }
        return preferences.smooth ? "运行中 · 平滑滚动已开启" : "运行中 · 平滑滚动已关闭"
    }

    static func loadPreferences(from defaults: UserDefaults?) -> Preferences {
        if let saved = defaults?.dictionary(forKey: preferencesKey) {
            return Preferences(saved)
        }
        let saved = defaults?.persistentDomain(forName: standaloneBundleID) ?? [:]
        let preferences = Preferences(saved)
        defaults?.set(preferences.values, forKey: preferencesKey)
        return preferences
    }

    init(defaults: UserDefaults?) {
        self.defaults = defaults
        preferences = Self.loadPreferences(from: defaults)
        super.init()
        tap.trackpadDirection = preferences.trackpad
        tap.mouseDirection = preferences.mouse
        tap.smoothMouseScrolling = preferences.smooth
    }

    func start() {
        refresh()
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        tap.stop()
    }

    private var standaloneRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Self.standaloneBundleID).isEmpty
    }

    private func refresh() {
        let supported = ScrollTap.canIdentifyDevices
        let conflict = standaloneRunning
        let trusted = AXIsProcessTrusted()
        if preferences.enabled && supported && !conflict && trusted {
            _ = tap.start()
            if preferences.smooth { tap.refreshPostingPermission() }
        } else {
            tap.stop()
        }
        let status: String
        if !preferences.enabled { status = "滚动设置已暂停" }
        else if !supported { status = "当前系统无法识别滚动设备" }
        else if conflict { status = "独立「滚动方向」运行中" }
        else if !trusted { status = "滚动设置等待授权" }
        else if !tap.isRunning { status = "无法接收滚动事件" }
        else if preferences.smooth && !tap.canPostScrollEvents { status = "平滑滚动等待授权" }
        else { status = "滚动设置运行中" }
        if statusLabel != status {
            statusLabel = status
            onStatusChange?()
        }
    }

    func addItems(to menu: NSMenu) {
        let supported = ScrollTap.canIdentifyDevices
        let trusted = AXIsProcessTrusted()
        let conflict = standaloneRunning
        let enabled = checkbox("启用滚动设置", #selector(toggleEnabled), preferences.enabled)
        enabled.image = Branding.menuSymbol("power")
        menu.addItem(enabled)
        if !supported {
            menu.addItem(withTitle: "当前系统无法识别滚动设备", action: nil, keyEquivalent: "")
        } else if conflict {
            menu.addItem(withTitle: "独立「滚动方向」运行中，合并版已暂停", action: nil, keyEquivalent: "")
        } else if preferences.enabled && (!trusted || (preferences.smooth && !tap.canPostScrollEvents)) {
            menu.addItem(actionItem(trusted ? "授权发送平滑滚动事件…" : "授权辅助功能…",
                                    #selector(requestAccessibility)))
        } else if preferences.enabled && !tap.isRunning {
            menu.addItem(withTitle: "无法接收滚动事件", action: nil, keyEquivalent: "")
        }
        menu.addItem(directionItem("触控板方向", symbol: "rectangle", preferences.trackpad, #selector(setTrackpad(_:))))
        menu.addItem(directionItem("鼠标滚轮方向", symbol: "computermouse", preferences.mouse, #selector(setMouse(_:))))
        let smooth = checkbox("鼠标平滑滚动", #selector(toggleSmooth), preferences.smooth)
        smooth.image = Branding.menuSymbol("waveform.path")
        menu.addItem(smooth)
    }

    private func actionItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func checkbox(_ title: String, _ action: Selector, _ isOn: Bool) -> NSMenuItem {
        let item = actionItem(title, action)
        item.state = isOn ? .on : .off
        return item
    }

    private func directionItem(_ title: String, symbol: String, _ current: ScrollDirection, _ action: Selector) -> NSMenuItem {
        let options: [(String, ScrollDirection)] = [("自然滚动", .natural), ("传统滚动", .classic), ("跟随系统", .system)]
        let selected = options.first { $0.1 == current }?.0 ?? "跟随系统"
        let parent = NSMenuItem(title: "\(title)：\(selected)", action: nil, keyEquivalent: "")
        parent.image = Branding.menuSymbol(symbol)
        let submenu = NSMenu(title: title)
        for (title, direction) in options {
            let item = checkbox(title, action, current == direction)
            item.tag = direction.rawValue
            submenu.addItem(item)
        }
        parent.submenu = submenu
        return parent
    }

    private func save() {
        defaults?.set(preferences.values, forKey: Self.preferencesKey)
    }

    @objc private func toggleEnabled() {
        preferences.enabled.toggle()
        save()
        refresh()
    }

    @objc private func toggleSmooth() {
        preferences.smooth.toggle()
        tap.smoothMouseScrolling = preferences.smooth
        save()
        refresh()
    }

    @objc private func setTrackpad(_ item: NSMenuItem) {
        guard let direction = ScrollDirection(rawValue: item.tag) else { return }
        preferences.trackpad = direction
        tap.trackpadDirection = direction
        save()
    }

    @objc private func setMouse(_ item: NSMenuItem) {
        guard let direction = ScrollDirection(rawValue: item.tag) else { return }
        preferences.mouse = direction
        tap.mouseDirection = direction
        save()
    }

    @objc private func requestAccessibility() {
        if AXIsProcessTrusted() {
            CGRequestPostEventAccess()
        } else {
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
