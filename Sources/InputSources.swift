import AppKit
import Carbon

struct InputSource {
    let reference: TISInputSource
    let id: String
    let name: String
}

enum InputSources {
    static func string(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }

    static func flag(_ source: TISInputSource, _ key: CFString) -> Bool {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return false }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(pointer).takeUnretainedValue())
    }

    static func all() -> [InputSource] {
        let filter = [kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource] as CFDictionary
        let references = TISCreateInputSourceList(filter, false).takeRetainedValue() as! [TISInputSource]
        var seen = Set<String>()
        return references.compactMap { source in
            guard flag(source, kTISPropertyInputSourceIsEnabled),
                  flag(source, kTISPropertyInputSourceIsSelectCapable),
                  let id = string(source, kTISPropertyInputSourceID), seen.insert(id).inserted else { return nil }
            return InputSource(reference: source, id: id,
                               name: string(source, kTISPropertyLocalizedName) ?? id)
        }
    }

    static func current() -> InputSource? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let id = string(source, kTISPropertyInputSourceID) else { return nil }
        return InputSource(reference: source, id: id,
                           name: string(source, kTISPropertyLocalizedName) ?? id)
    }

    static func conflicts() -> [String] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.processIdentifier != ownPID else { return nil }
            let name = app.localizedName ?? ""
            let bundle = app.bundleIdentifier ?? ""
            if bundle == "milu.inputlocker" || bundle == "local.czk.inputlocker.prototype"
                || name == "LockIME" || name == "InputLock" {
                return name
            }
            return nil
        }
    }
}
