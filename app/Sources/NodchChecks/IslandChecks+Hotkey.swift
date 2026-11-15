import Carbon.HIToolbox
import NodchCore

extension IslandChecks {
    static func hotkey() {
        check(HotkeySpec.setting(nil) == .on(.standard) && HotkeySpec.setting("") == .on(.standard), "hotkey: ⌥Space by default")
        check(HotkeySpec.standard.keyCode == UInt32(kVK_Space) && HotkeySpec.standard.modifiers == UInt32(optionKey)
              && HotkeySpec.standard.display == "⌥ Space", "hotkey: the default is ⌥ Space")
        check(HotkeySpec.setting("off") == .off && HotkeySpec.setting("None") == .off, "hotkey: \"off\" switches it off")
        let words = HotkeySpec.parse("ctrl+option+n")
        check(words?.keyCode == UInt32(kVK_ANSI_N) && words?.modifiers == UInt32(controlKey | optionKey) && words?.display == "⌃⌥ N",
              "hotkey: ctrl+option+n")
        check(HotkeySpec.parse("⌃⌥P") == HotkeySpec(keyCode: UInt32(kVK_ANSI_P), modifiers: UInt32(controlKey | optionKey), key: "P"),
              "hotkey: symbols ⌃⌥P")
        check(HotkeySpec.parse("Cmd-Shift-K")?.modifiers == UInt32(cmdKey | shiftKey), "hotkey: cmd-shift-k, any case")
        check(HotkeySpec.parse("alt + space") == .standard, "hotkey: alt is option, spaces allowed")
        check(HotkeySpec.parse("space") == nil, "hotkey: a bare key is refused")
        check(HotkeySpec.parse("option+foo") == nil && HotkeySpec.parse("hyper+space") == nil, "hotkey: unknown keys and modifiers are refused")
        check(HotkeySpec.parse("option+option+space") == nil, "hotkey: a doubled modifier is refused")
        check(HotkeySpec.setting("option+") == nil, "hotkey: an unreadable value is reported, not guessed")

        for (text, stored) in [("option+space", "option+space"), ("ctrl+option+n", "ctrl+option+n"), ("cmd+shift+k", "shift+cmd+k")] {
            let spec = HotkeySpec.parse(text)
            check(spec?.stored == stored && spec.flatMap { HotkeySpec.parse($0.stored) } == spec, "hotkey: \(text) round-trips as stored text")
        }
        check(HotkeySpec.standard.stored == "option+space" && HotkeySpec.parse(HotkeySpec.standard.stored) == .standard,
              "hotkey: the default round-trips as stored text")
        check(HotkeySpec.parse("⌘⇧⌥⌃R")?.stored == "ctrl+option+shift+cmd+r", "hotkey: stored modifiers are in the order ctrl, option, shift, cmd")
        check(HotkeySpec.Setting.off.stored == "off" && HotkeySpec.setting(HotkeySpec.Setting.off.stored) == .off, "hotkey: off is stored as off")
        check(HotkeySpec.from(keyCode: UInt32(kVK_ANSI_N), modifiers: UInt32(controlKey | optionKey)) == HotkeySpec.parse("ctrl+option+n")
              && HotkeySpec.from(keyCode: UInt32(kVK_Return), modifiers: UInt32(cmdKey))?.stored == "cmd+return",
              "hotkey: a recorded key with modifiers becomes a shortcut")
        check(HotkeySpec.from(keyCode: UInt32(kVK_ANSI_N), modifiers: 0) == nil, "hotkey: from refuses a bare key")
        check(HotkeySpec.from(keyCode: UInt32(kVK_F5), modifiers: UInt32(optionKey)) == nil
              && HotkeySpec.from(keyCode: UInt32(kVK_Escape), modifiers: UInt32(cmdKey)) == nil, "hotkey: from refuses an unknown key code")
        check(HotkeySpec.from(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey) | UInt32(alphaLock)) == .standard,
              "hotkey: from ignores Caps Lock")

        let other = HotkeySpec.parse("ctrl+option+n")!
        check(HotkeyStatus.on(.standard).message == nil && HotkeyStatus.off.message == nil, "hotkey status: on and off need no message")
        check(HotkeyStatus.takenBySystem(other).message == "⌃⌥ N is used by macOS. Choose another shortcut.",
              "hotkey status: taken by macOS says so")
        check(HotkeyStatus.takenByApp(.standard).message == "⌥ Space is used by another app. Choose another shortcut.",
              "hotkey status: taken by another app says so")
        check(HotkeyStatus.takenByApp(other).inEffect == nil && HotkeyStatus.takenByApp(other).spec == other
              && HotkeyStatus.on(other).inEffect == other && HotkeyStatus.off.spec == nil,
              "hotkey status: only a shortcut that is on is in effect")
    }
}
