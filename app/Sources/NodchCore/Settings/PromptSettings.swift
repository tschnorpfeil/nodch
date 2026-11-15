import Foundation

/// The prompt's part of Settings: its shortcut and the dictation language, both kept in defaults.
public enum PromptSettings {
    /// Tries `setting` with `register`. Saved only when it works; otherwise nothing is written and `previous` is
    /// registered again, so a refused shortcut never leaves the person without the one they had. Returns what became
    /// of the choice and what is in effect afterwards.
    public static func chooseHotkey(_ setting: HotkeySpec.Setting, previous: HotkeySpec.Setting, defaults: SettingsDefaults,
                                    register: (HotkeySpec.Setting) -> HotkeyStatus) -> (chosen: HotkeyStatus, inEffect: HotkeyStatus) {
        let chosen = register(setting)
        switch chosen {
        case .on, .off:
            defaults.set(setting.stored, forKey: HotkeySpec.defaultsKey)
            return (chosen, chosen)
        case .takenBySystem, .takenByApp:
            return (chosen, register(previous))
        }
    }

    /// The saved dictation language; nil follows the system.
    public static func speechLanguage(_ defaults: SettingsDefaults) -> String? {
        SpeechLanguage.choice(defaults.string(forKey: SpeechLanguage.defaultsKey))
    }

    /// A BCP 47 identifier, or nil for Automatic, which removes the saved choice.
    public static func setSpeechLanguage(_ id: String?, defaults: SettingsDefaults) {
        defaults.set(id, forKey: SpeechLanguage.defaultsKey)
    }
}
