import Foundation

@main enum PolicyTests {
    static func main() throws {
        let editor = AppIdentity(bundleID: "test.editor", name: "Editor")
        let chat = AppIdentity(bundleID: "test.chat", name: "Chat")
        var policy = LockPolicy(enabled: true)
        assert(policy.shouldLock(in: editor.bundleID))
        policy.setExcluded(true, app: editor)
        assert(policy.enabled && !policy.shouldLock(in: editor.bundleID))
        assert(policy.shouldLock(in: chat.bundleID))
        print("PASS: 例外只影响指定 App，离开后恢复全局策略")
        policy.enabled = false
        assert(!policy.shouldLock(in: editor.bundleID) && !policy.shouldLock(in: chat.bundleID))
        policy.enabled = true
        assert(!policy.shouldLock(in: editor.bundleID))
        print("PASS: 全局开关不覆盖应用例外")
        policy.setExcluded(true, app: AppIdentity(bundleID: editor.bundleID, name: "Renamed Editor"))
        assert(policy.appRules.count == 1 && policy.appRules[0].name == "Renamed Editor")
        policy.setExcluded(true, app: chat)
        let data = try JSONEncoder().encode(policy.appRules)
        let decoded = try JSONDecoder().decode([AppRule].self, from: data)
        let restored = LockPolicy(enabled: true, appRules: decoded + decoded)
        assert(restored.appRules.count == 2)
        assert(!restored.shouldLock(in: editor.bundleID) && !restored.shouldLock(in: chat.bundleID))
        print("PASS: 例外可序列化并去重，改名仍按 bundle ID 匹配")
        policy.setExcluded(false, app: editor)
        assert(policy.shouldLock(in: editor.bundleID) && !policy.shouldLock(in: chat.bundleID))
        policy.setExcluded(true, app: AppIdentity(bundleID: "", name: "Invalid"))
        assert(policy.appRules.count == 1)
        print("PASS: 移除例外恢复锁定，拒绝空应用标识")
        policy.setAppTarget("ABC", app: editor)
        assert(policy.effectiveTarget(globalID: "Pinyin", in: editor.bundleID) == "ABC")
        assert(!policy.isExcluded(editor.bundleID) && policy.shouldLock(in: editor.bundleID))
        assert(policy.effectiveTarget(globalID: "Pinyin", in: chat.bundleID) == nil)
        assert(policy.effectiveTarget(globalID: "Pinyin", in: "test.other") == "Pinyin")
        let roundTrip = LockPolicy(enabled: true, appRules:
            try JSONDecoder().decode([AppRule].self, from: JSONEncoder().encode(policy.appRules)))
        assert(roundTrip.effectiveTarget(globalID: "Other", in: editor.bundleID) == "ABC")
        policy.enabled = false
        assert(policy.effectiveTarget(globalID: "Pinyin", in: editor.bundleID) == nil)
        print("PASS: 独立输入法优先于全局目标，保存回读后保留；关闭总开关暂停所有规则")
        let legacy = Data(#"[{"bundleID":"test.editor","name":"Editor"}]"#.utf8)
        let migrated = LockPolicy(enabled: true, appRules: try JSONDecoder().decode([AppRule].self, from: legacy))
        assert(migrated.isExcluded(editor.bundleID))
        assert(migrated.effectiveTarget(globalID: "ABC", in: editor.bundleID) == nil)
        print("PASS: 旧版不锁定例外无损解码")
    }
}
