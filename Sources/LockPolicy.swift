import Foundation

struct AppIdentity: Equatable {
    let bundleID: String
    let name: String
}

struct AppRule: Codable, Equatable {
    let bundleID: String
    let name: String
    // nil means no lock. Missing targetID in legacy saved exceptions decodes as nil.
    let targetID: String?

    init(bundleID: String, name: String, targetID: String? = nil) {
        self.bundleID = bundleID
        self.name = name
        self.targetID = targetID
    }
}

struct LockPolicy {
    var enabled = false
    private(set) var appRules: [AppRule] = []

    init(enabled: Bool = false, appRules: [AppRule] = []) {
        self.enabled = enabled
        for app in appRules {
            setAppTarget(app.targetID, app: AppIdentity(bundleID: app.bundleID, name: app.name))
        }
    }

    func rule(for bundleID: String?) -> AppRule? {
        guard let bundleID else { return nil }
        return appRules.first { $0.bundleID == bundleID }
    }

    func isExcluded(_ bundleID: String?) -> Bool {
        guard let rule = rule(for: bundleID) else { return false }
        return rule.targetID == nil
    }

    func shouldLock(in bundleID: String?) -> Bool { enabled && !isExcluded(bundleID) }

    func effectiveTarget(globalID: String?, in bundleID: String?) -> String? {
        guard enabled else { return nil }
        if let rule = rule(for: bundleID) { return rule.targetID }
        return globalID
    }

    mutating func setExcluded(_ value: Bool, app: AppIdentity) {
        if value { setAppTarget(nil, app: app) } else { removeRule(app.bundleID) }
    }

    mutating func removeRule(_ bundleID: String) {
        appRules.removeAll { $0.bundleID == bundleID }
    }

    mutating func setAppTarget(_ targetID: String?, app: AppIdentity) {
        guard !app.bundleID.isEmpty else { return }
        removeRule(app.bundleID)
        appRules.append(AppRule(bundleID: app.bundleID, name: app.name, targetID: targetID))
        appRules.sort {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.bundleID < $1.bundleID : order == .orderedAscending
        }
    }
}
