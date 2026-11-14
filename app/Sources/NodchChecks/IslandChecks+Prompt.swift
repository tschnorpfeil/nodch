import Foundation
import NodchCore

extension IslandChecks {
    /// The quick prompt's voice and attachment decisions (`PromptDraft`).
    static func prompt() {
        func listening(_ words: String = "", final: Bool = true) -> PromptDraft {
            var draft = PromptDraft()
            _ = draft.open(.hotkey)
            draft.voiceStarted()
            if !words.isEmpty { draft.heard(words, final: final) }
            return draft
        }
        func file(_ name: String, folder: Bool = false) -> DroppedFile {
            DroppedFile(url: URL(fileURLWithPath: "/tmp/drop/\(name)"), isDirectory: folder)
        }
        let report = NodAttachment(id: "u1", name: "report.pdf", mimeType: "application/pdf", size: 10)

        // Opening.
        var draft = PromptDraft()
        check(draft.open(.hotkey) == [.startVoice] && draft.voice == .starting, "prompt: the shortcut opens with the microphone starting")
        draft.voiceStarted()
        check(draft.voice == .listening, "prompt: hotkey-open → listening")
        var click = PromptDraft()
        check(click.open(.click).isEmpty && click.voice == .off, "prompt: click-open → voice off")
        var dropOpen = PromptDraft()
        check(dropOpen.open(.drop).isEmpty && dropOpen.voice == .off, "prompt: drop-open → voice off")
        var again = listening()
        check(again.open(.hotkey).isEmpty && again.voice == .listening, "prompt: the shortcut on a listening prompt starts nothing twice")

        // Transcript.
        draft = listening("Please summarize")
        draft.heard("my unread", final: false)
        check(draft.display == "Please summarize my unread", "prompt: volatile words follow the final ones")
        draft.heard("my unread email.", final: true)
        check(draft.display == "Please summarize my unread email." && draft.volatile.isEmpty, "prompt: final words replace the volatile ones")
        check(PromptDraft.join("Hello", ", world") == "Hello, world" && PromptDraft.join("", " Hi ") == "Hi"
              && PromptDraft.join("a ", "b") == "a b", "prompt: words join with one space")

        // First keystroke.
        draft = listening("Please summarize")
        draft.heard("my unread", final: false)
        draft.fieldShows(draft.display) // the card keeps the field's editor in step with the words
        let typed = draft.typed(draft.display + "!")
        check(typed == [.stopVoice(finalize: false)] && draft.voice == .off && draft.display == "Please summarize my unread!",
              "prompt: keystroke → voice off, transcript kept")
        draft.heard("late words", final: true)
        check(draft.display == "Please summarize my unread!", "prompt: words after the keystroke are ignored")
        check(draft.typed(draft.display).isEmpty, "prompt: an unchanged field is no keystroke")
        check(draft.typed("x").isEmpty && draft.voice == .off, "prompt: typing with voice off touches no microphone")

        // Mic button.
        var toggled = listening("Hello")
        check(toggled.toggleVoice() == [.stopVoice(finalize: true)] && toggled.voice == .finishing && toggled.display == "Hello",
              "prompt: the mic button stops listening and keeps the words")
        _ = toggled.voiceFinished()
        check(toggled.toggleVoice() == [.startVoice] && toggled.voice == .starting, "prompt: the mic button starts listening again")

        // Escape.
        var escaped = listening("Draft text")
        _ = escaped.drop([file("a.pdf")])
        check(escaped.escape() == [.stopVoice(finalize: false)] && escaped.voice == .off && escaped.display.isEmpty
              && escaped.attachments.isEmpty, "prompt: Esc → stopped + discarded")
        var starting = PromptDraft()
        _ = starting.open(.hotkey)
        check(starting.escape() == [.stopVoice(finalize: false)], "prompt: Esc while the microphone is still starting stops it")

        // Enter while listening: stop first, then exactly one send.
        draft = listening("Summarize my mail")
        draft.heard("from today", final: false)
        check(draft.submit() == [.stopVoice(finalize: true)] && draft.voice == .finishing, "prompt: Enter → microphone stops first")
        check(draft.submit().isEmpty, "prompt: a second Enter while finishing sends nothing")
        draft.heard("from today.", final: true)
        let sent = draft.voiceFinished()
        check(sent == [.send(prompt: "Summarize my mail from today.", attachments: [])] && draft.sending,
              "prompt: Enter → stopped, then one send with the final words")
        check(draft.voiceFinished().isEmpty && draft.submit().isEmpty, "prompt: no second send")
        check(draft.sent() && draft.display.isEmpty && !draft.sending, "prompt: a sent prompt starts empty")
        var plain = PromptDraft(text: "Hi")
        check(plain.submit() == [.send(prompt: "Hi", attachments: [])], "prompt: Enter with voice off sends at once")
        var failing = PromptDraft(text: "Hi")
        _ = failing.submit()
        failing.sendFailed("503")
        check(failing.error == "503" && failing.display == "Hi" && !failing.sending, "prompt: a failed send keeps the text and says why")
        // Enter before the first words show: the microphone may have heard some, so it finalizes and sends what came.
        var early = listening()
        check(early.submit() == [.stopVoice(finalize: true)] && early.voice == .finishing, "prompt: Enter before any words still stops the microphone")
        early.heard("Call mum", final: true)
        check(early.voiceFinished() == [.send(prompt: "Call mum", attachments: [])], "prompt: … and sends the words that were still on their way")
        var starting2 = PromptDraft()
        _ = starting2.open(.hotkey)
        check(starting2.submit() == [.stopVoice(finalize: true)] && starting2.voice == .finishing, "prompt: Enter while the microphone starts stops it")
        check(starting2.voiceFinished().isEmpty && starting2.voice == .off && !starting2.sending, "prompt: … and with nothing heard sends nothing")

        // A send from a discarded draft that finishes late leaves the new draft alone.
        var stale = PromptDraft(text: "A")
        _ = stale.submit()
        let old = stale.sendToken
        _ = stale.escape()
        _ = stale.typed("B")
        _ = stale.submit()
        check(!stale.sent(token: old) && stale.sending && stale.display == "B", "prompt: a discarded send's success does not clear the new one")
        stale.sendFailed("late", token: old)
        check(stale.sending && stale.error == nil, "prompt: a discarded send's failure does not unlock the new one")
        check(stale.sent(token: stale.sendToken) && !stale.sending, "prompt: the current send still completes")

        // Closing.
        var closed = listening("Remind me")
        closed.heard("tomorrow", final: false)
        check(closed.closed() == [.stopVoice(finalize: false)] && closed.voice == .off && closed.display == "Remind me tomorrow",
              "prompt: close → stopped, words kept")
        var finishing = listening("Send it")
        _ = finishing.submit()
        check(finishing.closed() == [.stopVoice(finalize: false)] && finishing.voiceFinished().isEmpty,
              "prompt: closing while finishing stops the microphone and sends nothing")
        var reopened = closed
        check(reopened.open(.click).isEmpty && reopened.voice == .off, "prompt: reopened by click, voice stays off")

        // Text only.
        for hint in [VoiceHint.microphoneDenied, .noMicrophone, .speechUnavailable, .preparing] {
            var denied = PromptDraft()
            _ = denied.open(.hotkey)
            denied.voiceUnavailable(hint)
            let typedOK = denied.typed("Hello").isEmpty && denied.display == "Hello"
            check(denied.voice == .unavailable(hint) && !hint.text.isEmpty && typedOK
                  && denied.submit() == [.send(prompt: "Hello", attachments: [])],
                  "prompt: \(hint) → text-only with a hint")
        }
        var late = PromptDraft()
        late.voiceUnavailable(.microphoneDenied)
        check(late.voice == .off, "prompt: a late failure does not touch a prompt that is not listening")

        // Drops.
        let folder = PromptDraft.accept([file("Photos", folder: true), file("a.pdf")])
        check(folder.accepted.map(\.lastPathComponent) == ["a.pdf"] && folder.notice == PromptDraft.folderRefused, "drop: folder rejected with a hint")
        check(PromptDraft.accept([]).accepted.isEmpty && PromptDraft.accept([]).notice == PromptDraft.nothingArrived,
              "drop: a drop that brought nothing says so instead of vanishing")
        let many = PromptDraft.accept((1...12).map { file("f\($0).txt") })
        check(many.accepted.count == PromptDraft.maxAttachments && many.notice?.contains("2 left out") == true, "drop: more than 10 capped")
        var capped = PromptDraft()
        _ = capped.drop((1...8).map { file("f\($0).txt") })
        let more = capped.drop((9...12).map { file("f\($0).txt") })
        check(more.count == 2 && capped.attachments.count == 10, "drop: the cap counts chips already there")
        check(PromptDraft.accept([file("a.pdf"), file("a.pdf")]).accepted.count == 1, "drop: the same file once")

        var files = PromptDraft()
        let uploads = files.drop([file("report.pdf"), file("big.mov")])
        check(uploads == [.upload(id: 1, file: URL(fileURLWithPath: "/tmp/drop/report.pdf")),
                          .upload(id: 2, file: URL(fileURLWithPath: "/tmp/drop/big.mov"))]
              && files.attachments.allSatisfy { $0.status == .uploading }, "drop: each file uploads at once")
        files.uploaded(1, as: report)
        check(!files.canSend && files.submit().isEmpty && files.notice == PromptDraft.waitsForUploads, "drop: send blocked while uploading")
        files.uploadFailed(2, reason: "too large")
        check(files.attachments[1].status == .failed("too large") && files.notice == nil, "drop: a failed upload shows its reason")
        check(files.canSend && files.submit() == [.send(prompt: "", attachments: [report])],
              "drop: empty text + ready attachment allowed; failed chip not sent")
        var removed = PromptDraft()
        _ = removed.drop([file("a.pdf")])
        removed.remove(1)
        removed.uploaded(1, as: report)
        check(removed.attachments.isEmpty && !removed.canSend, "drop: a removed chip stays gone when its upload ends")
        var discarded = PromptDraft()
        _ = discarded.drop([file("a.pdf")])
        _ = discarded.escape()
        _ = discarded.drop([file("b.pdf")])
        discarded.uploaded(1, as: report)
        check(discarded.attachments.first?.status == .uploading, "drop: an upload from a discarded prompt lands nowhere")
        var withText = PromptDraft(text: "Compare")
        _ = withText.drop([file("a.pdf"), file("b.pdf")])
        withText.uploaded(1, as: report)
        withText.uploadFailed(2, reason: "x")
        check(withText.submit() == [.send(prompt: "Compare", attachments: [report])], "drop: text goes with the ready files only")
        var nothing = PromptDraft()
        _ = nothing.drop([file("a.pdf")])
        nothing.uploadFailed(1, reason: "x")
        check(!nothing.canSend && nothing.submit().isEmpty, "drop: only failed files and no text sends nothing")

        // Where a drag counts as heading for the island.
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let notch = IslandPlacement.notch(housing: CGRect(x: 663, y: 950, width: 185, height: 32), screen: screen)
        let other = CGRect(x: 1512, y: 0, width: 1920, height: 1080)
        check(IslandDropZone.isNear(pointer: CGPoint(x: 200, y: 900), placement: notch, screens: [screen, other]),
              "drop: a drag near the top of the island's display is near")
        check(!IslandDropZone.isNear(pointer: CGPoint(x: 200, y: 500), placement: notch, screens: [screen, other])
              && !IslandDropZone.isNear(pointer: CGPoint(x: 2000, y: 1070), placement: notch, screens: [screen, other]),
              "drop: lower down, or on another display, is not")
        check(IslandPresentation.takesKey(.drop) && IslandPresentation.closesOnOutsideClick(.drop),
              "drop: a drop is the person's own action and takes the keyboard")
    }
}
