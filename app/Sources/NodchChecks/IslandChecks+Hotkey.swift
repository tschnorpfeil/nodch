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
    }
}
