import NodchCore

extension IslandChecks {
    static func speech() {
        // The bug: inside an English-only app `Locale.current` is English; the person's list is what counts.
        check(SpeechLanguage.candidates(choice: nil, system: ["de-DE", "en-US"]) == ["de-DE", "en-US"],
              "speech: the system's languages in order, no Locale.current")
        check(SpeechLanguage.candidates(choice: nil, system: ["fr-FR"]) == ["fr-FR", "en-US"], "speech: US English last")
        check(SpeechLanguage.candidates(choice: nil, system: []) == ["en-US"], "speech: US English without a system list")
        check(SpeechLanguage.candidates(choice: "de-CH", system: ["de-DE", "en-US"]) == ["de-CH", "de-DE", "en-US"],
              "speech: a choice comes first, the system stays as fallback")
        check(SpeechLanguage.candidates(choice: "en-US", system: ["EN-us"]) == ["en-US"], "speech: each language once")

        check(SpeechLanguage.choice(nil) == nil && SpeechLanguage.choice(" ") == nil, "speech: no choice follows the system")
        check(SpeechLanguage.choice("System") == nil && SpeechLanguage.choice("auto") == nil, "speech: \"system\" follows the system")
        check(SpeechLanguage.choice("de_DE") == "de-DE" && SpeechLanguage.choice("de-AT") == "de-AT", "speech: a choice reads as BCP 47")

        let menu = SpeechLanguage.menu(supported: ["en_US", "de_CH", "fr_FR", "de_DE", "en_GB", "ja_JP", "de_AT"],
                                       system: ["de-DE", "en-GB"])
        check(menu.yours == ["de-DE", "de-AT", "de-CH", "en-GB", "en-US"],
              "speech: the menu lists the person's languages first, exact region first: \(menu.yours)")
        check(menu.others == ["fr-FR", "ja-JP"], "speech: every other language below, by name: \(menu.others)")
        check(SpeechLanguage.name("de-DE") == "Deutsch (Deutschland)" && SpeechLanguage.shortName("de-AT") == "Deutsch",
              "speech: names in their own language")
        check(SpeechLanguage.name("fr-FR").hasPrefix("F"), "speech: names start with a capital")
    }

    static func speechPrompt() {
        var listening = PromptDraft()
        _ = listening.open(.hotkey)
        listening.voiceStarted()
        listening.heard("Hallo", final: true)
        listening.heard("wie geht", final: false)
        check(listening.languageChanged() == [.stopVoice(finalize: false), .startVoice] && listening.voice == .starting
              && listening.display == "Hallo wie geht", "speech: a new language restarts the microphone and keeps the words")

        var unsupported = PromptDraft()
        _ = unsupported.open(.hotkey)
        unsupported.voiceUnavailable(.speechUnavailable)
        check(unsupported.languageChanged() == [.startVoice] && unsupported.voice == .starting,
              "speech: a language the model lacked is retried in the new one")

        var off = PromptDraft()
        check(off.languageChanged().isEmpty && off.voice == .off, "speech: with the microphone off it waits for next time")
        var denied = PromptDraft()
        _ = denied.open(.hotkey)
        denied.voiceUnavailable(.microphoneDenied)
        check(denied.languageChanged().isEmpty, "speech: no microphone stays no microphone")
    }
}
