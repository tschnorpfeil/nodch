// Adapted from Pippa: app/Sources/Pippa/App/Hotkey.swift
import Carbon.HIToolbox

/// The quick prompt's global shortcut, from the `nodch.hotkey` default: "option+space" (the default), "ctrl+option+n",
/// "⌃⌥N", "cmd-shift-k" or "off". At least one modifier: a bare key would swallow typing everywhere.
public struct HotkeySpec: Equatable, Sendable {
    public var keyCode: UInt32
    /// Carbon modifiers (`cmdKey`, `optionKey`, …).
    public var modifiers: UInt32
    public var key: String

    public init(keyCode: UInt32, modifiers: UInt32, key: String) {
        self.keyCode = keyCode; self.modifiers = modifiers; self.key = key
    }

    public static let defaultsKey = "nodch.hotkey"
    public static let standard = HotkeySpec(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey), key: "Space")

    public enum Setting: Equatable, Sendable {
        case off, on(HotkeySpec)

        /// The text saved in `nodch.hotkey`: "off" or `HotkeySpec.stored`.
        public var stored: String {
            switch self {
            case .off: "off"
            case .on(let spec): spec.stored
            }
        }
    }

    /// The setting for a saved value: missing means the default; nil means the value cannot be read.
    public static func setting(_ text: String?) -> Setting? {
        guard let text = text?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return .on(standard) }
        if ["off", "none", "disabled"].contains(text.lowercased()) { return .off }
        return parse(text).map(Setting.on)
    }

    public static func parse(_ text: String) -> HotkeySpec? {
        var spelled = text.lowercased()
        for (symbol, word) in [("⌘", "cmd+"), ("⌥", "option+"), ("⌃", "control+"), ("⇧", "shift+")] {
            spelled = spelled.replacingOccurrences(of: symbol, with: word)
        }
        let tokens = spelled.split(whereSeparator: { "+- ".contains($0) }).map(String.init)
        guard let last = tokens.last, tokens.count >= 2, let (code, name) = keys[last] else { return nil }
        var mods: UInt32 = 0
        for token in tokens.dropLast() {
            guard let mod = modifierNames[token], mods & mod == 0 else { return nil }
            mods |= mod
        }
        return HotkeySpec(keyCode: code, modifiers: mods, key: name)
    }

    /// A key pressed with these Carbon modifiers, as a shortcut; nil for a key nodch does not know or without a modifier.
    public static func from(keyCode: UInt32, modifiers: UInt32) -> HotkeySpec? {
        let mods = modifiers & modifierMask
        guard mods != 0, let (_, name) = keys.values.first(where: { $0.0 == keyCode }) else { return nil }
        return HotkeySpec(keyCode: keyCode, modifiers: mods, key: name)
    }

    /// The text saved in `nodch.hotkey`: "ctrl+option+n", modifiers in the order control, option, shift, cmd.
    public var stored: String {
        var tokens: [String] = []
        if modifiers & UInt32(controlKey) != 0 { tokens.append("ctrl") }
        if modifiers & UInt32(optionKey) != 0 { tokens.append("option") }
        if modifiers & UInt32(shiftKey) != 0 { tokens.append("shift") }
        if modifiers & UInt32(cmdKey) != 0 { tokens.append("cmd") }
        return (tokens + [key.lowercased()]).joined(separator: "+")
    }

    /// "⌥ Space", "⌃⌥ N".
    public var display: String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + " " + key
    }

    private static let modifierMask = UInt32(cmdKey | optionKey | controlKey | shiftKey)

    private static let modifierNames: [String: UInt32] = [
        "cmd": UInt32(cmdKey), "command": UInt32(cmdKey),
        "opt": UInt32(optionKey), "option": UInt32(optionKey), "alt": UInt32(optionKey),
        "ctrl": UInt32(controlKey), "control": UInt32(controlKey),
        "shift": UInt32(shiftKey),
    ]

    private static let keys: [String: (UInt32, String)] = {
        var keys: [String: (UInt32, String)] = [
            "space": (UInt32(kVK_Space), "Space"), "return": (UInt32(kVK_Return), "Return"),
            "enter": (UInt32(kVK_Return), "Return"), "tab": (UInt32(kVK_Tab), "Tab"),
        ]
        let letters: [(String, Int)] = [
            ("a", kVK_ANSI_A), ("b", kVK_ANSI_B), ("c", kVK_ANSI_C), ("d", kVK_ANSI_D), ("e", kVK_ANSI_E), ("f", kVK_ANSI_F),
            ("g", kVK_ANSI_G), ("h", kVK_ANSI_H), ("i", kVK_ANSI_I), ("j", kVK_ANSI_J), ("k", kVK_ANSI_K), ("l", kVK_ANSI_L),
            ("m", kVK_ANSI_M), ("n", kVK_ANSI_N), ("o", kVK_ANSI_O), ("p", kVK_ANSI_P), ("q", kVK_ANSI_Q), ("r", kVK_ANSI_R),
            ("s", kVK_ANSI_S), ("t", kVK_ANSI_T), ("u", kVK_ANSI_U), ("v", kVK_ANSI_V), ("w", kVK_ANSI_W), ("x", kVK_ANSI_X),
            ("y", kVK_ANSI_Y), ("z", kVK_ANSI_Z), ("0", kVK_ANSI_0), ("1", kVK_ANSI_1), ("2", kVK_ANSI_2), ("3", kVK_ANSI_3),
            ("4", kVK_ANSI_4), ("5", kVK_ANSI_5), ("6", kVK_ANSI_6), ("7", kVK_ANSI_7), ("8", kVK_ANSI_8), ("9", kVK_ANSI_9),
        ]
        for (name, code) in letters { keys[name] = (UInt32(code), name.uppercased()) }
        return keys
    }()
}

/// What became of a shortcut: in effect, off, or refused because macOS or another app already uses it.
public enum HotkeyStatus: Equatable, Sendable {
    case on(HotkeySpec)
    case off
    case takenBySystem(HotkeySpec)
    case takenByApp(HotkeySpec)

    /// The shortcut that works now; nil when it is off or taken.
    public var inEffect: HotkeySpec? {
        if case .on(let spec) = self { spec } else { nil }
    }

    /// The shortcut asked for, whether or not it works; nil when it is off.
    public var spec: HotkeySpec? {
        switch self {
        case .on(let spec), .takenBySystem(let spec), .takenByApp(let spec): spec
        case .off: nil
        }
    }

    /// Why the shortcut does not work, in plain words; nil when nothing is wrong.
    public var message: String? {
        switch self {
        case .on, .off: nil
        case .takenBySystem(let spec): "\(spec.display) is used by macOS. Choose another shortcut."
        case .takenByApp(let spec): "\(spec.display) is used by another app. Choose another shortcut."
        }
    }
}
