import Foundation
import NodchCore

extension IslandChecks {
    /// Stop's scope and words, where Return goes when dictation finishes late, files beside an answer, and which
    /// answer offers choices.
    static func targets() {
        typealias P = IslandPresentation
        let now = Date()
        let task = "00000000-0000-4000-8000-00000000d0c1"

        // Stop names what it stops: the task on show, or all of the thread's work.
        let chat = WorkActivity(title: nil, step: nil, site: nil, since: now, doing: .model)
        let background = WorkActivity(title: "Watch prices", step: nil, site: nil, since: now, doing: .tool, taskID: task)
        check(chat.stopScope == .thread && background.stopScope == .task(task), "stop: a task stops on its own, the chat's turn stops all work")
        check(WorkActivity(title: nil, step: nil, site: nil, since: now, doing: .model, taskID: "").stopScope == .task(""),
              "stop: an empty task id is refused as a task, never widened to all work")
        check(WorkActivity(title: nil, step: nil, site: nil, since: now, doing: .model, taskID: "not-a-uuid").stopScope == .task("not-a-uuid"),
              "stop: an id Nod would refuse stays a task stop, never widened to all work")
        check(P.stopName(.thread) == "Stop all work" && P.stopName(.thread, short: true) == "Stop all work",
              "stop: the thread stop says Stop all work, on the button and in the tooltip")
        check(P.stopName(.task(task), short: true) == "Stop" && P.stopName(.task(task)) == "Stop this task",
              "stop: a task stop says which")

        // Return under question Q1 while the microphone finishes: the send still names Q1.
        var dictated = PromptDraft()
        _ = dictated.open(.hotkey)
        dictated.voiceStarted()
        dictated.heard("next week", final: false)
        check(dictated.submit(to: .question("q1")) == [.stopVoice(finalize: true)], "targets: Return while listening waits for the last words")
        let late = dictated.voiceFinished()
        check(late == [.send(prompt: "next week", attachments: [], target: .question("q1"))] && dictated.sending,
              "targets: the late send names the question Return was pressed on")
        // The model sends only if the card still shows that target; otherwise it calls the send off, words kept.
        check(PromptTarget.current(question: "q1", files: false) == .question("q1"), "targets: the same question still matches")
        for (now, name) in [("q2", "Q1→Q2"), (nil, "Q1→gone")] as [(String?, String)] {
            check(PromptTarget.current(question: now, files: false) != .question("q1"), "targets: \(name) no longer matches")
        }
        check(PromptTarget.current(question: "q1", files: false) != .message, "targets: prompt→question no longer matches")
        check(PromptTarget.current(question: "q1", files: true) == .message, "targets: files go out as a new message")
        dictated.sendFailed(P.targetChanged, token: dictated.sendToken)
        check(!dictated.sending && dictated.text == "next week" && dictated.error == P.targetChanged,
              "targets: a called-off send keeps the original words and says why")
        check(dictated.submit(to: .question("q2")) == [.send(prompt: "next week", attachments: [], target: .question("q2"))],
              "targets: Return again sends once to what the card shows now")

        // A file attached after Return must not silently turn the answer into a different kind of send.
        var withLateFile = PromptDraft(text: "next week")
        _ = withLateFile.open(.hotkey)
        withLateFile.voiceStarted()
        _ = withLateFile.submit(to: .question("q1"))
        let dropped = URL(fileURLWithPath: "/tmp/nodch-checks/late.pdf")
        let lateFile = NodAttachment(id: "late", name: "late.pdf", mimeType: "application/pdf", size: 1)
        _ = withLateFile.drop([.init(url: dropped, isDirectory: false)])
        withLateFile.uploaded(1, as: lateFile)
        check(withLateFile.voiceFinished() == [.send(prompt: "next week", attachments: [lateFile], target: .question("q1"))],
              "targets: a late file cannot change the captured question into a new message")

        // A Return that never went out leaves no target behind.
        var edited = PromptDraft()
        _ = edited.open(.hotkey)
        edited.voiceStarted()
        _ = edited.submit(to: .question("q1"))
        _ = edited.typed("my own words")
        check(edited.voiceFinished().isEmpty && edited.submit() == [.send(prompt: "my own words", attachments: [], target: .message)],
              "targets: typing over a finishing send drops its target")
        var closed = PromptDraft()
        _ = closed.open(.hotkey)
        closed.voiceStarted()
        closed.heard("hello", final: true)
        _ = closed.submit(to: .question("q1"))
        _ = closed.closed()
        _ = closed.startVoice()
        closed.voiceStarted()
        check(closed.finishVoice() == [.stopVoice(finalize: true)] && closed.voiceFinished().isEmpty && !closed.sending,
              "targets: a closed card's finishing send is not resumed by the next dictation")

        // Picks with words go out without files: the words clear, every chip stays as it was, under its id.
        var picks = PromptDraft(text: "only from Ana")
        let folder = URL(fileURLWithPath: "/tmp/nodch-checks", isDirectory: true)
        _ = picks.drop(["a.pdf", "b.pdf", "c.pdf"].map { DroppedFile(url: folder.appendingPathComponent($0), isDirectory: false) })
        let ready = NodAttachment(id: "u1", name: "a.pdf", mimeType: "application/pdf", size: 1)
        picks.uploaded(1, as: ready)
        picks.uploadFailed(3, reason: "Too big")
        let chips = picks.attachments
        _ = picks.answerChoice()
        picks.answeredKeepingFiles(token: picks.sendToken)
        check(!picks.sending && picks.display.isEmpty && picks.attachments == chips,
              "files: an answer with words clears the words and keeps uploading, ready and failed chips")
        picks.uploaded(2, as: NodAttachment(id: "u2", name: "b.pdf", mimeType: "application/pdf", size: 1))
        check(picks.ready.map(\.id) == ["u1", "u2"], "files: an upload still on its way lands on its kept chip")
        check(picks.typed("next").isEmpty && picks.text == "next", "files: the field takes words again")
        picks.remove(3)
        check(picks.submit() == [.send(prompt: "next", attachments: [ready, NodAttachment(id: "u2", name: "b.pdf", mimeType: "application/pdf", size: 1)])],
              "files: the kept files go out with the next message")

        // Choices show only for the question the island asks now; a cached one keeps its text.
        let question = NodQuestion(choices: [.init(id: "c1", label: "Now")], multiple: true)
        let cached = NodAnswer(id: "q1", text: "When?", at: now.addingTimeInterval(-60), question: question)
        let approval = PendingApproval(id: "a1", messageID: "m1", title: "Send?", app: "Gmail", fields: [], body: nil, bodyCut: false)
        for (state, name) in [(IslandState.working(chat), "working"), (.needsYou(approval, more: 0), "an approval"),
                              (.offline(reason: "down"), "offline"), (.rest, "rest")] {
            let shown = P.shownAnswer(cached, state: state, now: now)
            check(shown?.text == "When?" && shown?.question == nil, "choices: a cached question shows as text only while \(name)")
        }
        check(P.shownAnswer(cached, state: .asks(cached), now: now)?.question == question, "choices: the open question offers its choices")
    }
}
