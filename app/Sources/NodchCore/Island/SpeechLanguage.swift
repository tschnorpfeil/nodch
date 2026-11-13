import Foundation

/// The dictation language. By default the person's own languages in the order System Settings lists them, then US
/// English. A choice from the microphone's menu (or `defaults write dev.nodch.Nodch nodch.speechLanguage de-DE`) comes
/// first. Not `Locale.current`: nodch ships only in English, so inside the app that is English whatever the system says.
public enum SpeechLanguage {
    public static let defaultsKey = "nodch.speechLanguage"
    public static let fallback = "en-US"

    /// The saved choice as a BCP 47 identifier; nil follows the system.
    public static func choice(_ saved: String?) -> String? {
        guard let text = saved?.trimmingCharacters(in: .whitespaces), !text.isEmpty,
              !["system", "auto", "automatic"].contains(text.lowercased()),
              Locale.Language(identifier: text).languageCode != nil else { return nil }
        return Locale(identifier: text).identifier(.bcp47)
    }

    /// The languages to try, best first: the choice, the system's languages, US English. Each once.
    public static func candidates(choice: String?, system: [String]) -> [String] {
        var seen = Set<String>()
        return ([choice].compactMap { $0 } + system + [fallback]).filter { seen.insert($0.lowercased()).inserted }
    }

    /// The menu's two parts: the supported languages that are among the system's, in the system's order (an exact
    /// region first), then every other one by name.
    public static func menu(supported: [String], system: [String]) -> (yours: [String], others: [String]) {
        let ids = supported.map { Locale(identifier: $0).identifier(.bcp47) }
        var yours: [String] = []
        for preferred in system {
            let language = Locale.Language(identifier: preferred)
            let matching = ids.filter { Locale.Language(identifier: $0).languageCode == language.languageCode && !yours.contains($0) }
            let exact = matching.filter { Locale.Language(identifier: $0).region == language.region }
            yours += exact + byName(matching.filter { !exact.contains($0) })
        }
        return (yours, byName(ids.filter { !yours.contains($0) }))
    }

    /// The language's name in that language, as language pickers show it: "Deutsch (Deutschland)".
    public static func name(_ id: String) -> String {
        let name = Locale(identifier: id).localizedString(forIdentifier: id) ?? id
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    /// Only the language, in that language: "Deutsch".
    public static func shortName(_ id: String) -> String {
        let code = Locale.Language(identifier: id).languageCode?.identifier ?? id
        let name = Locale(identifier: id).localizedString(forLanguageCode: code) ?? id
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    private static func byName(_ ids: [String]) -> [String] {
        ids.sorted { name($0).localizedStandardCompare(name($1)) == .orderedAscending }
    }
}
