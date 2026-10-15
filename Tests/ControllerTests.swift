import AppKit
import Carbon

@main enum ControllerTests {
    static func main() {
        let suite = "local.czk.imepin.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let editor = AppIdentity(bundleID: "test.editor", name: "Editor")
        let chat = AppIdentity(bundleID: "test.chat", name: "Chat")
        var front: AppIdentity? = editor
        var source = "ABC"
        var selected: [String] = []
        var available = ["ABC", "Pinyin", "Other"]
        let mock = InputSourceAccess(currentID: { source }, availableIDs: { available },
                                     select: { id in selected.append(id); source = id; return noErr })
        let controller = LockController(defaults: defaults, frontmostProvider: { front },
                                        sources: mock, conflicts: { [] })
        controller.choose("Pinyin")
        assert(source == "Pinyin" && controller.enabled)
        controller.setExcluded(true, app: editor)
        source = "ABC"
        let before = selected.count
        controller.restore()
        assert(source == "ABC" && selected.count == before && !controller.effectiveLock)
        // Switching target while in an excluded app must also leave its source alone.
        controller.choose("ABC")
        source = "Pinyin"
        controller.restore()
        assert(source == "Pinyin")
        print("PASS: 例外 App 内自由切换，更改全局目标也不抢占输入源")
        front = chat
        controller.restore()
        assert(source == "ABC" && controller.effectiveLock)
        print("PASS: 控制器离开例外后应用全局目标")
        front = editor
        source = "Pinyin"
        controller.restore()
        assert(source == "Pinyin")
        front = nil
        controller.restore()
        assert(source == "Pinyin" && controller.currentAppIsExcluded)
        print("PASS: 菜单或应用选择器自身获得焦点时保留外部 App 上下文")
        let reloaded = LockController(defaults: defaults, frontmostProvider: { editor },
                                      sources: mock, conflicts: { [] })
        assert(reloaded.enabled && reloaded.targetID == "ABC" && reloaded.currentAppIsExcluded)
        assert(reloaded.appRules.count == 1)
        print("PASS: 例外、目标和全局开关从独立 UserDefaults 域回读")
        front = editor
        controller.setExcluded(false, app: editor)
        assert(source == "ABC" && controller.effectiveLock)
        controller.setEnabled(false)
        source = "Pinyin"
        front = chat
        controller.restore()
        assert(source == "Pinyin")
        print("PASS: 移除当前例外立即恢复；全局关闭后切 App 也不切输入源")
        var contender = false
        let conflictController = LockController(defaults: nil, frontmostProvider: { chat },
            sources: mock, conflicts: { contender ? ["Other"] : [] })
        conflictController.setEnabled(true)
        contender = true
        assert(!conflictController.setEnabled(true) && !conflictController.enabled)
        print("PASS: 保留其他锁定工具的冲突保护")
        front = editor
        controller.setExcluded(true, app: editor)
        controller.setEnabled(true)
        controller.start()
        defer { controller.stop() }
        source = "Pinyin"
        RunLoop.main.run(until: Date().addingTimeInterval(1.1))
        assert(source == "Pinyin")
        front = chat
        RunLoop.main.run(until: Date().addingTimeInterval(1.1))
        assert(source == "ABC")
        controller.stop()
        source = "Pinyin"
        RunLoop.main.run(until: Date().addingTimeInterval(1.1))
        assert(source == "Pinyin")
        print("PASS: 定时检查尊重例外、离开后恢复，停止控制器后不再切换")
        front = editor
        let overrides = LockController(defaults: defaults, frontmostProvider: { front }, sources: mock, conflicts: { [] })
        overrides.choose("ABC")
        overrides.setAppTarget("Pinyin", app: editor)
        assert(source == "Pinyin" && overrides.targetID == "ABC" && overrides.effectiveTargetID == "Pinyin")
        overrides.choose("Other")
        assert(source == "Pinyin" && overrides.targetID == "Other")
        front = chat
        overrides.restore()
        assert(source == "Other")
        front = editor
        overrides.restore()
        assert(source == "Pinyin")
        print("PASS: App 独立输入法优先，修改全局目标不覆盖它；切 App 后使用对应目标")
        let saved = LockController(defaults: defaults, frontmostProvider: { editor }, sources: mock, conflicts: { [] })
        assert(saved.targetID == "Other" && saved.effectiveTargetID == "Pinyin")
        assert(saved.rule(for: editor.bundleID)?.targetID == "Pinyin")
        overrides.setAppTarget(nil, app: editor)
        source = "ABC"
        overrides.restore()
        assert(source == "ABC" && !overrides.effectiveLock)
        overrides.setAppTarget("Pinyin", app: editor)
        assert(source == "Pinyin")
        overrides.followGlobal(app: editor)
        assert(source == "Other" && overrides.rule(for: editor.bundleID) == nil)
        print("PASS: 指定输入法、不锁定、跟随全局可互相切换，并从偏好回读")
        overrides.setAppTarget("Pinyin", app: editor)
        available.removeAll { $0 == "Pinyin" }
        source = "ABC"
        let count = selected.count
        overrides.restore()
        assert(source == "ABC" && selected.count == count && overrides.message != nil)
        available.append("Pinyin")
        overrides.restore()
        assert(source == "Pinyin")
        overrides.setEnabled(false)
        source = "ABC"
        overrides.restore()
        assert(source == "ABC")
        print("PASS: 指定输入法停用时不擅自回退全局；重新启用可恢复，总开关关闭不执行规则")
        print("LIMIT: 模拟 App 和输入源服务；未操作真实桌面焦点或真实输入法。")
    }
}
