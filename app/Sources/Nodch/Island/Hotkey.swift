// Adapted from Pippa: app/Sources/Pippa/App/Hotkey.swift
import AppKit
import Carbon.HIToolbox
import NodchCore

/// The quick prompt's global shortcut via Carbon, which needs no Accessibility permission. One shortcut, id 1.
@MainActor
final class HotkeyCenter {
    static let shared = HotkeyCenter()
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var onPress: (@MainActor () -> Void)?

    /// Registers the shortcut from `nodch.hotkey`. Returns what is in effect, nil when it is off or taken.
    @discardableResult func apply(_ defaults: UserDefaults = .standard) -> HotkeySpec? {
        let saved = defaults.string(forKey: HotkeySpec.defaultsKey)
        let setting = HotkeySpec.setting(saved) ?? {
            print("nodch: \(HotkeySpec.defaultsKey) = \"\(saved ?? "")\" is not a shortcut; using \(HotkeySpec.standard.display)")
            return .on(HotkeySpec.standard)
        }()
        guard case .on(let spec) = setting else { register(nil); return nil }
        guard !Self.takenBySystem(spec) else {
            print("nodch: \(spec.display) is a macOS shortcut; choose another one with `defaults write` \(HotkeySpec.defaultsKey)")
            register(nil)
            return nil
        }
        return register(spec) ? spec : nil
    }

    /// Enabled macOS shortcuts (e.g. switch input source) silently win; hence check beforehand.
    static func takenBySystem(_ spec: HotkeySpec) -> Bool {
        var list: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&list) == noErr, let entries = list?.takeRetainedValue() as? [[String: Any]] else { return false }
        let mask = cmdKey | shiftKey | optionKey | controlKey
        return entries.contains { entry in
            guard (entry[kHISymbolicHotKeyEnabled as String] as? Bool) == true,
                  let key = entry[kHISymbolicHotKeyCode as String] as? Int,
                  let mods = entry[kHISymbolicHotKeyModifiers as String] as? Int else { return false }
            return UInt32(truncatingIfNeeded: key) == spec.keyCode && mods & mask == Int(spec.modifiers) & mask
        }
    }

    @discardableResult private func register(_ spec: HotkeySpec?) -> Bool {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        guard let spec else { return true }
        if handler == nil {
            var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                var key = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                  MemoryLayout<EventHotKeyID>.size, nil, &key)
                guard key.id == 1 else { return noErr }
                // Carbon delivers on the main thread.
                MainActor.assumeIsolated { HotkeyCenter.shared.onPress?() }
                return noErr
            }, 1, &type, nil, &handler)
        }
        var newRef: EventHotKeyRef?
        let status = RegisterEventHotKey(spec.keyCode, spec.modifiers, EventHotKeyID(signature: OSType(0x4E44_4348), id: 1), // "NDCH"
                                         GetApplicationEventTarget(), 0, &newRef)
        guard status == noErr, let newRef else {
            print("nodch: \(spec.display) is taken by another app (\(status))")
            return false
        }
        ref = newRef
        return true
    }
}
