import AppKit
import Carbon

// All callbacks and TIS calls run on the main run loop. No keyboard event taps.
final class LockController {
    private let defaults: UserDefaults?
    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?
    private var pending: DispatchWorkItem?
    private var attempts: [Date] = []
    private var retryAfter = Date.distantPast
    private var sleeping = false
    private var sessionActive = true
    private var policy: LockPolicy
    private let frontmostProvider: () -> AppIdentity?
    private let sources: InputSourceAccess
    private let conflicts: () -> [String]
    private(set) var frontmostApp: AppIdentity?
    var enabled: Bool { policy.enabled }
    var appRules: [AppRule] { policy.appRules }
    var currentAppIsExcluded: Bool { policy.isExcluded(frontmostApp?.bundleID) }
    var effectiveTargetID: String? { policy.effectiveTarget(globalID: targetID, in: frontmostApp?.bundleID) }
    var effectiveLock: Bool { effectiveTargetID != nil }
    var statusLabel: String {
        if !enabled { return "全局锁定已关闭" }
        if currentAppIsExcluded { return "当前 App 不锁定" }
        return rule(for: frontmostApp?.bundleID) != nil ? "当前 App 使用独立输入法" : "全局锁定中"
    }
    private(set) var targetID: String?
    private(set) var message: String?
    var onChange: (() -> Void)?

    init(defaults: UserDefaults? = .standard,
         frontmostProvider: @escaping () -> AppIdentity? = LockController.systemFrontmostApp,
         sources: InputSourceAccess = .system,
         conflicts: @escaping () -> [String] = InputSources.conflicts) {
        self.defaults = defaults
        self.frontmostProvider = frontmostProvider
        self.sources = sources
        self.conflicts = conflicts
        frontmostApp = frontmostProvider()
        targetID = defaults?.string(forKey: "targetID") ?? sources.currentID()
        let exclusions = defaults?.data(forKey: "excludedApps")
            .flatMap { try? JSONDecoder().decode([AppRule].self, from: $0) } ?? []
        policy = LockPolicy(enabled: defaults?.bool(forKey: "enabled") ?? false, appRules: exclusions)
        if !conflicts().isEmpty {
            policy.enabled = false
            message = "检测到其他输入法锁定工具，请先退出它。"
        }
    }

    static func systemFrontmostApp() -> AppIdentity? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let id = app.bundleIdentifier else { return nil }
        return AppIdentity(bundleID: id, name: app.localizedName ?? id)
    }

    func refreshFrontmostApp() {
        // Keep the last external app when our menu or app picker has focus.
        guard let app = frontmostProvider(), app != frontmostApp else { return }
        frontmostApp = app
        pending?.cancel()
        attempts.removeAll()
        retryAfter = .distantPast
        message = nil
        onChange?()
    }

    func isExcluded(_ bundleID: String) -> Bool { policy.isExcluded(bundleID) }

    func rule(for bundleID: String?) -> AppRule? { policy.rule(for: bundleID) }

    func setExcluded(_ value: Bool, app: AppIdentity) {
        policy.setExcluded(value, app: app)
        rulesDidChange()
    }

    func setAppTarget(_ id: String?, app: AppIdentity) {
        if let id, !sources.availableIDs().contains(id) { return }
        policy.setAppTarget(id, app: app)
        rulesDidChange()
    }

    func followGlobal(app: AppIdentity) {
        policy.removeRule(app.bundleID)
        rulesDidChange()
    }

    private func rulesDidChange() {
        if let data = try? JSONEncoder().encode(policy.appRules) {
            defaults?.set(data, forKey: "excludedApps")
        }
        pending?.cancel()
        attempts.removeAll()
        retryAfter = .distantPast
        message = nil
        restore()
        onChange?()
    }

    func start() {
        let distributed = DistributedNotificationCenter.default()
        for name in [kTISNotifySelectedKeyboardInputSourceChanged, kTISNotifyEnabledKeyboardInputSourcesChanged] {
            observers.append(distributed.addObserver(forName: Notification.Name(name! as String),
                                                     object: nil, queue: .main) { [weak self] _ in
                self?.scheduleRestore()
                self?.onChange?()
            })
        }
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            // App activation may precede the destination application's own source selection.
            self?.refreshFrontmostApp()
            self?.scheduleRestore()
            self?.onChange?()
        })
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification,
                     NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let self else { return }
                if note.name == NSWorkspace.willSleepNotification { self.sleeping = true }
                if note.name == NSWorkspace.didWakeNotification { self.sleeping = false }
                if note.name == NSWorkspace.sessionDidResignActiveNotification { self.sessionActive = false }
                if note.name == NSWorkspace.sessionDidBecomeActiveNotification { self.sessionActive = true }
                self.scheduleRestore()
            })
        }
        let timer = Timer(timeInterval: 0.75, repeats: true) { [weak self] _ in self?.restore() }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        scheduleRestore()
    }

    func stop() {
        pending?.cancel()
        pending = nil
        timer?.invalidate()
        timer = nil
        for token in observers {
            DistributedNotificationCenter.default().removeObserver(token)
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        observers.removeAll()
    }

    @discardableResult
    func setEnabled(_ value: Bool) -> Bool {
        if value, !conflicts().isEmpty {
            policy.enabled = false
            message = "请先退出其他输入法锁定工具。"
            onChange?()
            return false
        }
        policy.enabled = value
        message = nil
        attempts.removeAll()
        retryAfter = .distantPast
        pending?.cancel()
        defaults?.set(enabled, forKey: "enabled")
        if value { restore() }
        onChange?()
        return true
    }

    func choose(_ id: String) {
        guard sources.availableIDs().contains(id) else { return }
        targetID = id
        defaults?.set(id, forKey: "targetID")
        setEnabled(true)
    }

    private func scheduleRestore() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.restore() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
    }

    func restore() {
        refreshFrontmostApp()
        guard !sleeping, sessionActive, let targetID = effectiveTargetID else { return }
        guard sources.availableIDs().contains(targetID) else {
            message = "目标输入法已停用，请重新选择。"
            onChange?()
            return
        }
        guard sources.currentID() != targetID else {
            if message != nil { message = nil; onChange?() }
            return
        }
        let now = Date()
        guard now >= retryAfter else { return }
        attempts = attempts.filter { now.timeIntervalSince($0) < 3 }
        if attempts.count >= 5 {
            // Avoid fighting another utility or a protected system field indefinitely.
            retryAfter = now.addingTimeInterval(5)
            message = "切换频繁，暂缓 5 秒；可点击暂停锁定。"
            attempts.removeAll()
            onChange?()
            return
        }
        attempts.append(now)
        let result = sources.select(targetID)
        message = result == noErr ? nil : "系统未接受切换（\(result)），稍后重试。"
        onChange?()
    }
}
