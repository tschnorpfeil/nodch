import NodchCore

extension IslandChecks {
    /// What the card shows while the microphone is on, and the first keystroke taking over without losing words, also
    /// when the focused field never showed them.
    static func dictationTakeover() {
        func listening(base: String = "", final: String, volatile: String = "") -> PromptDraft {
            var draft = PromptDraft(text: base)
            _ = draft.open(.hotkey)
            draft.voiceStarted()
            draft.heard(final, final: true)
            if !volatile.isEmpty { draft.heard(volatile, final: false) }
            return draft
        }

        // The live line.
        let live = listening(final: "Please summarize my unread email", volatile: "from today")
        check(live.live.heard == "Please summarize my unread email" && live.live.hearing == " from today",
              "dictation: the heard words bright, the ones still being recognized dimmed with their space: \(live.live)")
        check(live.live.heard + live.live.hearing == live.display, "dictation: the live line is the whole text")
        check(listening(final: "Hello").live.hearing.isEmpty, "dictation: nothing dimmed without words in flight")
        var opened = PromptDraft()
        _ = opened.open(.hotkey)
        check(opened.live.heard.isEmpty && opened.live.hearing.isEmpty, "dictation: an empty live line before the first words")

        // The field stayed empty while the words came in: its first keystroke arrives as just that key.
        var stale = listening(final: "Please summarize my unread email", volatile: "from today")
        let effects = stale.typed(",")
        check(effects == [.stopVoice(finalize: false)] && stale.voice == .off
              && stale.display == "Please summarize my unread email from today,",
              "dictation: typing into a field that missed the words keeps them: \(stale.display)")
        check(stale.live.hearing.isEmpty, "dictation: after taking over nothing is still being recognized")

        // The field showed an older part of the dictation.
        var partial = listening(final: "Please summarize my unread email", volatile: "from today")
        partial.fieldShows("Please summarize")
        _ = partial.typed("Please summarize and")
        check(partial.display == "Please summarize my unread email from today and",
              "dictation: a field behind the transcript keeps all of it: \(partial.display)")

        // The field held what was typed before the microphone went on.
        var typedFirst = listening(base: "Hello", final: "world")
        _ = typedFirst.typed("Hello!")
        check(typedFirst.display == "Hello world!", "dictation: text typed before dictating stays in front: \(typedFirst.display)")

        // The field was up to date (the card pushed the words into it): edits are taken as they are.
        func synced(_ words: String) -> PromptDraft { var d = listening(final: words); d.fieldShows(d.display); return d }
        var atEnd = synced("Book a table")
        _ = atEnd.typed("Book a table for two")
        check(atEnd.display == "Book a table for two", "dictation: typing at the end of the full text")
        var backspace = synced("Book a table")
        _ = backspace.typed("Book a tabl")
        check(backspace.display == "Book a tabl", "dictation: one Backspace on the full text")
        var inside = synced("Book a table")
        _ = inside.typed("Book a big table")
        check(inside.display == "Book a big table", "dictation: an insertion inside the full text")

        var pasted = synced("Book a table")
        _ = pasted.typed("Send an email")
        check(pasted.display == "Send an email", "dictation: a paste over the selected full text replaces it (review S1)")
        var cleared = synced("Book a table")
        _ = cleared.typed("")
        check(cleared.display.isEmpty, "dictation: select all and delete clears it (review S1)")
        var word = synced("Book a table")
        _ = word.typed("Book a ")
        check(word.display == "Book a ", "dictation: ⌥⌫ deletes the last word (review S1)")
        var sameLetter = listening(final: "Hello")
        _ = sameLetter.typed("H")
        check(sameLetter.display == "HelloH", "dictation: a first key that matches the dictation's start is not lost (review S1): \(sameLetter.display)")

        // After taking over, the keyboard edits the text as usual.
        _ = stale.typed(stale.display + " please")
        check(stale.display == "Please summarize my unread email from today, please", "dictation: typing goes on after taking over")

        // The transcriber failed while listening: the microphone is reported off, the words stay, typing works.
        var failed = listening(final: "Remind me")
        failed.voiceUnavailable(.failed)
        check(failed.voice == .unavailable(.failed) && failed.display == "Remind me", "dictation: a failed transcriber keeps the words")
        check(failed.typed("Remind me tomorrow").isEmpty && failed.display == "Remind me tomorrow",
              "dictation: after a failure typing needs no microphone")
    }
}
