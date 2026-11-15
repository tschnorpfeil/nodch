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

    /// The shortcut asked for: from `nodch.hotkey` at launch, then the last one chosen that worked.
    private(set) var setting = HotkeySpec.Setting.on(.standard)
    /// What became of `setting`.
    private(set) var status = HotkeyStatus.on(.standard)
    /// While Settings records a new shortcut, the current one is unregistered so the keys reach the recorder.
    private(set) var suspended = false

    /// Registers the shortcut from `nodch.hotkey` and returns what became of it.
    @discardableResult func apply(_ defaults: SettingsDefaults = UserDefaults.standard) -> HotkeyStatus {
        let saved = defaults.string(forKey: HotkeySpec.defaultsKey)
        setting = HotkeySpec.setting(saved) ?? {
            print("nodch: \(HotkeySpec.defaultsKey) = \"\(saved ?? "")\" is not a shortcut; using \(HotkeySpec.standard.display)")
            return .on(HotkeySpec.standard)
        }()
        suspended = false
        status = attempt(setting)
        if let message = status.message { print("nodch: \(message)") }
        return status
    }

    /// From Settings: registers `setting` and saves it when that works. When it is taken nothing is saved and the
    /// previous shortcut comes back. Returns what became of the choice.
    func choose(_ setting: HotkeySpec.Setting, defaults: SettingsDefaults = UserDefaults.standard) -> HotkeyStatus {
        suspended = false
        let result = PromptSettings.chooseHotkey(setting, previous: self.setting, defaults: defaults, register: attempt)
        if result.chosen.message == nil { self.setting = setting }
        status = result.inEffect
        return result.chosen
    }

    /// Unregisters the shortcut until `resume`, so pressing it while recording does not open the prompt.
    func suspend() {
        guard !suspended else { return }
        suspended = true
        register(nil)
    }

    /// Registers the shortcut again after `suspend`.
    func resume() {
        guard suspended else { return }
        suspended = false
        status = attempt(setting)
    }

    private func attempt(_ setting: HotkeySpec.Setting) -> HotkeyStatus {
        guard case .on(let spec) = setting else { register(nil); return .off }
        guard !Self.takenBySystem(spec) else { register(nil); return .takenBySystem(spec) }
        return register(spec) ? .on(spec) : .takenByApp(spec)
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
        guard status == noErr, let newRef else { return false }
        ref = newRef
        return true
    }
}
