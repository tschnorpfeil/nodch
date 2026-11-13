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

        var finishing = listening(final: "Hello", volatile: "world")
        check(finishing.toggleVoice() == [.stopVoice(finalize: true)] && finishing.voice == .finishing,
              "dictation: toggle finalizes to an editable draft")
        let takeover = finishing.typed("!")
        check(takeover == [.stopVoice(finalize: false)] && finishing.display == "Hello world!",
              "dictation: typing takes over during finalization")
        finishing.heard("late", final: true)
        check(finishing.voiceFinished().isEmpty && finishing.display == "Hello world!" && !finishing.sending,
              "dictation: late results cannot change or send an edit")
        var done = listening(final: "Hello")
        _ = done.toggleVoice()
        done.heard("world", final: true)
        check(done.voiceFinished().isEmpty && done.display == "Hello world" && !done.sending,
              "dictation: finalization leaves an editable draft without sending")

        var choosing = listening(final: "Hello", volatile: "world")
        _ = choosing.finishVoice()
        check(choosing.answerChoice() == [.stopVoice(finalize: false)] && choosing.sending && choosing.voice == .off,
              "dictation: an explicit choice during transcription is accepted and stops finalization")
        choosing.heard("late", final: true)
        check(choosing.voiceFinished().isEmpty && choosing.display == "Hello world",
              "dictation: a choice keeps shown words and ignores late transcription")

        var activity = VoiceActivity()
        for i in 1...20 {
            check(activity.sample(confidence: 0.2, end: Double(i) / 2) == (i == 20 ? true : nil),
                  "dictation: initial noise times out only after ten analyzed seconds")
        }
        activity = VoiceActivity()
        for i in 1...12 {
            check(activity.sample(confidence: 0.9, end: Double(i) / 2) == nil,
                  "dictation: continuous and repeated speech stays listening beyond three seconds")
        }
        check(activity.sample(confidence: 0.2, end: 7) == nil, "dictation: reordered quiet waits for missing audio")
        check(activity.sample(confidence: 0.9, end: 6.5) == nil, "dictation: delayed speech precedes quiet")
        check(activity.sample(confidence: 0.9, end: 7.5) == nil, "dictation: resumed speech resets silence")
        check(activity.sample(confidence: 0.2, end: 7.0) == nil, "dictation: stale result is ignored")
        check(activity.sample(confidence: 0.2, end: 8.5) == nil, "dictation: reordered quiet waits for earlier window")
        check(activity.sample(confidence: 0.2, end: 8) == nil, "dictation: short pause stays listening")
        check(activity.sample(confidence: 0.2, end: 9) == false, "dictation: analyzed silence finishes")
        check(activity.sample(confidence: 0.9, end: 9.5) == nil, "dictation: decision is emitted once")
        var explicitSend = listening(final: "Hello")
        _ = explicitSend.finishVoice()
        check(explicitSend.submit().isEmpty, "dictation: Return during transcription waits for final words")
        explicitSend.heard("world", final: true)
        check(explicitSend.voiceFinished() == [.send(prompt: "Hello world", attachments: [])],
              "dictation: Return during transcription sends exactly once")
        var silent = listening(final: "")
        check(silent.finishVoice(noSpeech: true) == [.stopVoice(finalize: true)], "dictation: timeout releases microphone")
        check(silent.voiceFinished().isEmpty && silent.voice == .unavailable(.noSpeech), "dictation: no speech is readable")
        var cancelled = listening(final: "keep")
        _ = cancelled.finishVoice()
        _ = cancelled.escape()
        cancelled.heard("late", final: true)
        check(cancelled.voiceFinished().isEmpty && cancelled.display.isEmpty && !cancelled.sending,
              "dictation: escape discards and ignores late results")

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
