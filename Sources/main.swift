import AppKit
import Carbon
import UniformTypeIdentifiers
import ServiceManagement

private enum AppRuleMode: Equatable {
    case global, unlocked, source(String)
}

private struct AppRuleChoice {
    let app: AppIdentity
    let mode: AppRuleMode
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var item: NSStatusItem!
    private let menu = NSMenu()
    private let controller: LockController

    init(controller: LockController) {
        self.controller = controller
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !CommandLine.arguments.contains("--smoke-test"), let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).count > 1 {
            NSApp.terminate(nil)
            return
        }
        NSApp.setActivationPolicy(.accessory)
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menu.delegate = self
        item.menu = menu
        controller.onChange = { [weak self] in self?.refreshIcon() }
        controller.start()
        refreshIcon()
        if CommandLine.arguments.contains("--smoke-test") {
            rebuildMenu()
            print("GUI_STARTED: statusItem=\(item.button != nil) enabled=\(controller.enabled)")
            let rows = menu.items.filter { !$0.isSeparatorItem && $0.view == nil }.count
            print("COMPACT_MENU: rows=\(rows) headerHeight=\(menu.items.first?.view?.frame.height ?? 0)")
            dumpMenu(menu)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { NSApp.terminate(nil) }
        }
    }

    func applicationWillTerminate(_ notification: Notification) { controller.stop() }

    private func refreshIcon() {
        item.button?.image = Branding.statusIcon(pinned: controller.effectiveLock)
        item.button?.title = ""
        item.button?.toolTip = "Input Method Locked · \(controller.statusLabel)"
        item.button?.setAccessibilityLabel(item.button?.toolTip ?? "Input Method Locked")
    }

    func menuWillOpen(_ menu: NSMenu) {
        controller.refreshFrontmostApp()
        rebuildMenu()
    }

    private func dumpMenu(_ menu: NSMenu, indent: String = "") {
        for entry in menu.items where !entry.isSeparatorItem {
            print("MENU: \(indent)\(entry.state == .on ? "✓ " : "")\(entry.title)")
            if let submenu = entry.submenu { dumpMenu(submenu, indent: indent + "  ") }
        }
    }

    @discardableResult
    private func add(_ title: String, action: Selector? = nil, key: String = "", to parent: NSMenu? = nil) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
        entry.target = self
        (parent ?? menu).addItem(entry)
        return entry
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        menu.minimumWidth = 300
        let sources = InputSources.all()
        let displayTargetID = controller.effectiveTargetID ?? controller.targetID
        let target = controller.currentAppIsExcluded ? "自由切换输入法" :
            (sources.first(where: { $0.id == displayTargetID })?.name ?? "未启用的输入法")
        let app = controller.frontmostApp
        let header = add("Input Method Locked · \(controller.statusLabel)")
        header.view = headerView(target: target, appName: app?.name ?? "未知应用")
        let global = add("全局锁定", action: #selector(toggle))
        global.state = controller.enabled ? .on : .off
        global.image = NSImage(systemSymbolName: "pin", accessibilityDescription: nil)
        global.toolTip = "开启输入法锁定：普通 App 使用全局输入法，例外 App 使用各自的设置。"
        let globalTarget = sources.first(where: { $0.id == controller.targetID })?.name ?? "未选择"
        let inputPicker = add("全局输入法：\(globalTarget)")
        let inputMenu = NSMenu(title: "全局输入法")
        inputPicker.submenu = inputMenu
        for source in sources {
            let entry = add(source.name, action: #selector(selectSource(_:)), to: inputMenu)
            entry.representedObject = source.id
            entry.state = source.id == controller.targetID ? .on : .off
        }
        if let app {
            let rule = controller.rule(for: app.bundleID)
            let summary = rule.map { $0.targetID.map { id in
                sources.first(where: { $0.id == id })?.name ?? "已停用的输入法"
            } ?? "不锁定" } ?? "跟随全局"
            let quick = add("当前 App：\(summary)")
            quick.submenu = ruleMenu(for: app, sources: sources)
            quick.toolTip = "为 \(app.name) 选择独立输入法、不锁定，或跟随全局。"
        } else {
            add("无法识别当前 App").isEnabled = false
        }
        let exceptions = add("应用规则（\(controller.appRules.count)）")
        let submenu = NSMenu(title: "应用例外")
        exceptions.submenu = submenu
        if controller.appRules.isEmpty {
            let empty = NSMenuItem(title: "暂无例外 App", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
        } else {
            for app in controller.appRules {
                let summary = app.targetID.map { id in sources.first(where: { $0.id == id })?.name ?? "已停用的输入法" } ?? "不锁定"
                let entry = NSMenuItem(title: "\(app.name) · \(summary)", action: nil, keyEquivalent: "")
                entry.submenu = ruleMenu(for: AppIdentity(bundleID: app.bundleID, name: app.name), sources: sources)
                submenu.addItem(entry)
            }
        }
        submenu.addItem(.separator())
        add("添加 App…", action: #selector(addApps), to: submenu)
        menu.addItem(.separator())
        let settings = NSMenu(title: "设置")
        add("设置").submenu = settings
        let launchAtLogin = add("开机自动启动", action: #selector(toggleLaunchAtLogin), to: settings)
        switch SMAppService.mainApp.status {
        case .enabled:
            launchAtLogin.state = .on
        case .requiresApproval:
            launchAtLogin.state = .mixed
            launchAtLogin.toolTip = "等待系统允许；再次点击可取消。"
            add("在系统设置中允许自动启动…", action: #selector(loginItemSettings), to: settings)
        default:
            launchAtLogin.state = .off
        }
        add("打开键盘设置…", action: #selector(keyboardSettings), to: settings)
        settings.addItem(.separator())
        add("关于 Input Method Locked…", action: #selector(about), to: settings)
        add("退出", action: #selector(quit), key: "q")
    }

    private func ruleMenu(for app: AppIdentity, sources: [InputSource]) -> NSMenu {
        let submenu = NSMenu(title: app.name)
        let rule = controller.rule(for: app.bundleID)
        let selected: AppRuleMode = rule.map { $0.targetID.map(AppRuleMode.source) ?? .unlocked } ?? .global
        func choice(_ title: String, mode: AppRuleMode) {
            let entry = NSMenuItem(title: title, action: #selector(selectAppRule(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = AppRuleChoice(app: app, mode: mode)
            entry.state = mode == selected ? .on : .off
            submenu.addItem(entry)
        }
        choice("跟随全局", mode: .global)
        choice("不锁定", mode: .unlocked)
        submenu.addItem(.separator())
        let heading = NSMenuItem(title: "使用指定输入法", action: nil, keyEquivalent: "")
        heading.isEnabled = false
        submenu.addItem(heading)
        for source in sources { choice(source.name, mode: .source(source.id)) }
        if let target = rule?.targetID, !sources.contains(where: { $0.id == target }) {
            let missing = NSMenuItem(title: "已停用的输入法", action: nil, keyEquivalent: "")
            missing.state = .on
            missing.isEnabled = false
            submenu.addItem(missing)
        }
        return submenu
    }

    private func headerView(target: String, appName: String) -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 58))
        func label(_ text: String, y: CGFloat, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
            let field = NSTextField(labelWithString: text)
            field.frame = NSRect(x: 16, y: y, width: 268, height: 20)
            field.font = .systemFont(ofSize: size, weight: weight)
            field.textColor = color
            field.lineBreakMode = .byTruncatingTail
            field.toolTip = text
            view.addSubview(field)
        }
        let color: NSColor = controller.message != nil ? .systemOrange : controller.effectiveLock ? .systemGreen :
            (controller.enabled ? .systemOrange : .secondaryLabelColor)
        label(controller.message ?? controller.statusLabel, y: 32, size: 13, weight: .semibold, color: color)
        label("\(target)  ·  \(appName)", y: 9, size: 11, weight: .regular, color: .secondaryLabelColor)
        return view
    }

    @objc private func selectAppRule(_ sender: NSMenuItem) {
        guard let choice = sender.representedObject as? AppRuleChoice else { return }
        switch choice.mode {
        case .global: controller.followGlobal(app: choice.app)
        case .unlocked: controller.setAppTarget(nil, app: choice.app)
        case .source(let id): controller.setAppTarget(id, app: choice.app)
        }
    }

    @objc private func addApps() {
        let panel = NSOpenPanel()
        panel.title = "添加应用例外"
        panel.message = "为选中的 App 选择独立输入法，或设为不锁定。"
        panel.prompt = "添加"
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 32))
        let label = NSTextField(labelWithString: "输入法：")
        label.frame = NSRect(x: 0, y: 5, width: 70, height: 22)
        accessory.addSubview(label)
        let sourcePicker = NSPopUpButton(frame: NSRect(x: 72, y: 1, width: 240, height: 28), pullsDown: false)
        sourcePicker.addItem(withTitle: "不锁定")
        for source in InputSources.all() {
            sourcePicker.addItem(withTitle: source.name)
            sourcePicker.lastItem?.representedObject = source.id
        }
        sourcePicker.setAccessibilityLabel("应用例外的输入法")
        accessory.addSubview(sourcePicker)
        panel.accessoryView = accessory
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] response in
            guard response == .OK, let self else { return }
            for url in panel.urls {
                guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { continue }
                let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                self.controller.setAppTarget(sourcePicker.selectedItem?.representedObject as? String,
                                             app: AppIdentity(bundleID: id, name: name))
            }
        }
    }

    @objc private func toggle() { controller.setEnabled(!controller.enabled) }
    @objc private func selectSource(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        controller.choose(id)
    }
    @objc private func keyboardSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
    }
    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            switch service.status {
            case .enabled, .requiresApproval:
                try service.unregister()
            default:
                try service.register()
            }
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "无法更新开机自动启动"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "好")
            alert.runModal()
        }
    }
    @objc private func loginItemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
    @objc private func about() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Input Method Locked \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.4.1")"
        alert.informativeText = "Input Method Locked 是一款轻量的 macOS 菜单栏工具，用于固定常用输入法。\n\n设置全局输入法，也可为不同 App 单独指定输入法或设为不锁定。切换 App 时自动应用对应规则。\n\n输入法和应用规则会自动保存，支持开机自动启动。"
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
    @objc private func quit() { NSApp.terminate(nil) }
}

func spin(_ seconds: TimeInterval) {
    let until = Date().addingTimeInterval(seconds)
    while Date() < until { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
}

func selfTest() -> Int32 {
    let conflicts = InputSources.conflicts()
    guard conflicts.isEmpty else {
        print("SKIP: 其他锁定工具正在运行：\(conflicts.joined(separator: ", "))。请退出后重测。")
        return 2
    }
    guard let original = InputSources.current() else { print("FAIL: 无当前输入源"); return 1 }
    let sources = InputSources.all()
    guard let alternate = sources.first(where: { $0.id != original.id }) else {
        print("SKIP: 至少需要两个启用的输入源"); return 2
    }
    let controller = LockController(defaults: nil)
    controller.start()
    controller.choose(original.id)
    let driftResult = TISSelectInputSource(alternate.reference)
    let drifted = driftResult == noErr && InputSources.current()?.id == alternate.id
    spin(1.2)
    let restored = drifted && InputSources.current()?.id == original.id
    print("\(restored ? "PASS" : "FAIL"): 锁定后偏离输入源自动恢复")
    controller.setEnabled(false)
    let pauseResult = TISSelectInputSource(alternate.reference)
    spin(1.2)
    let paused = pauseResult == noErr && InputSources.current()?.id == alternate.id
    print("\(paused ? "PASS" : "FAIL"): 暂停后允许切换")
    controller.setEnabled(true)
    spin(0.6)
    let resumed = InputSources.current()?.id == original.id
    print("\(resumed ? "PASS" : "FAIL"): 恢复锁定重新选择目标")
    controller.setEnabled(false)
    controller.stop()
    let restoreResult = TISSelectInputSource(original.reference)
    spin(0.3)
    let cleanedUp = restoreResult == noErr && InputSources.current()?.id == original.id
    print("\(cleanedUp ? "PASS" : "FAIL"): 结束后恢复原输入法 \(original.id)")
    print("LIMIT: 以上检查输入源 API 状态；未验证第三方输入法实际文字、系统保护输入框。")
    return restored && paused && resumed && cleanedUp ? 0 : 1
}

if CommandLine.arguments.contains("--diagnose") {
    print("Current: \(InputSources.current()?.id ?? "nil")")
    for source in InputSources.all() { print("\(source.id)\t\(source.name)") }
    print("Other lockers: \(InputSources.conflicts())")
} else if CommandLine.arguments.contains("--self-test") {
    exit(selfTest())
} else {
    let app = NSApplication.shared
    // A brief menu smoke test stays paused in memory, without reading or writing user preferences.
    let delegate = AppDelegate(controller: LockController(
        defaults: CommandLine.arguments.contains("--smoke-test") ? nil : .standard))
    app.delegate = delegate
    app.run()
}
