// Adapted from Pippa: app/Sources/Pippa/App/Island.swift
import AppKit
import NodchCore
import Observation

/// Follows `IslandStore.state` and drives the presenter: the wing for each state, the card that opens by itself for an
/// approval (without the keyboard), "done" that goes back to rest, the quick prompt on the shortcut (listening) or a
/// click, files dragged onto the island, and the display the island lives on. The microphone is on only while the
/// card shows the prompt: every way of closing it turns it off.
@MainActor
final class IslandController {
    let model: IslandModel
    let presenter: IslandPresenter
    private var openCause: IslandPresentation.OpenCause?
    private var lastState: IslandState
    /// The app in front when the shortcut was pressed: it gets the keyboard back when the prompt closes.
    private var previousApp: NSRunningApplication?
    private var doneTimer: Task<Void, Never>?
    private var ticker: Timer?
    private var observers: [NSObjectProtocol] = []
    private var dragMonitor: Any?
    /// The drag pasteboard when the button went down: a file drag changes it.
    private var dragStart = 0
    private var dragEnd: Task<Void, Never>?

    init(store: IslandStore, voice: VoiceSource? = MicrophoneVoice()) {
        model = IslandModel(store: store)
        model.voice = voice
        presenter = IslandPresenter(model: model)
        if case .asks = store.state { lastState = .rest } else { lastState = store.state }
    }

    func start() {
        model.loadSpeechLanguages()
        // The speech model is checked and installed now, not on the first ⌥Space. No microphone, no permission prompt.
        model.voice?.prepare()
        model.onCompactClick = { [weak self] in self?.compactClicked() }
        model.onCollapse = { [weak self] in self?.presenter.close() }
        model.onSent = { [weak self] in self?.closePrompt() }
        presenter.view.onHover = { [weak self] inside in
            guard let self, model.hovering != inside else { return }
            model.hovering = inside
            refresh()
        }
        presenter.view.onPanelShown = { [weak self] in
            guard let self else { return }
            // Reopening keeps the SwiftUI card alive, so its onAppear does not run: restart the click guard here.
            if model.approval != nil, !model.showsPrompt { model.startAnswerGuard() }
            guard model.showsPrompt else { return }
            model.focusToken += 1
        }
        presenter.onEscape = { [weak self] in self?.escape() }
        presenter.onQuestionKey = { [weak self] key in self?.model.questionKey(key) ?? false }
        presenter.onCardKey = { [weak self] key, modifier in self?.cardKey(key, modifier) ?? false }
        presenter.closesOnOutsideClick = { [weak self] in
            guard let cause = self?.openCause else { return true }
            return IslandPresentation.closesOnOutsideClick(cause)
        }
        presenter.onClosed = { [weak self] in
            guard let self else { return }
            openCause = nil
            model.isOpen = false
            model.highlightedChoice = nil
            model.perform(model.draft.closed())
        }
        presenter.view.onDragOver = { [weak self] over in self?.dragOver(over) }
        presenter.view.onDrop = { [weak self] files in self?.dropped(files) }
        presenter.onIdle = { [weak self] in self?.refresh() }

        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                // A display came or went: start again from rest on whichever display has the island now.
                self?.presenter.close(animated: false)
                self?.refresh()
            }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
                                                                           object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        })

        // Mouse events of other apps need no permission; the drag pasteboard tells a file drag from any other.
        dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            let type = event.type
            MainActor.assumeIsolated { self?.followDrag(type) }
        }
        HotkeyCenter.shared.onPress = { [weak self] in self?.hotkeyPressed() }
        model.hotkey = HotkeyCenter.shared.apply()?.display
        observe()
        stateChanged()
    }

    private func observe() {
        withObservationTracking { _ = model.store.state } onChange: { [weak self] in
            Task { @MainActor in
                self?.stateChanged()
                self?.observe()
            }
        }
    }

    private func stateChanged() {
        let old = lastState, new = model.store.state
        lastState = new
        if case .done = new {
            if old != new || doneTimer == nil { startDoneTimer() }
        } else {
            doneTimer?.cancel()
            doneTimer = nil
            model.doneExpired = false
        }
        let newQuestion = IslandPresentation.newQuestion(from: old, to: new)
        if IslandPresentation.waitingID(old) != IslandPresentation.waitingID(new) {
            model.actionError = nil; model.startAnswerGuard(); model.picked = []; model.highlightedChoice = nil
        }
        if case .working = new {} else if case .working = old { model.actionError = nil }
        // An open card turns into the answer (with the prompt under it) when Nod finishes or asks, so it stays at rest.
        if model.isOpen, model.tone == .done || model.asking != nil { model.showsPrompt = true }
        switch IslandPresentation.reaction(from: old, to: new, open: openCause) {
        case .reveal: open(.approval)
        case .conceal: presenter.close()
        case .none: break
        }
        if newQuestion, model.isOpen {
            model.showsPrompt = true
            if IslandPresentation.questionTakesKey(open: openCause) {
                let front = NSWorkspace.shared.frontmostApplication
                if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApp = front }
                presenter.open(key: true)
                model.focusToken += 1
            }
        }
        refresh()
    }

    /// "Done" shows for a moment, then the island reads it as rest.
    private func startDoneTimer() {
        doneTimer?.cancel()
        model.doneExpired = false
        doneTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(IslandPresentation.doneDuration))
            guard !Task.isCancelled, let self else { return }
            model.doneExpired = true
            refresh()
        }
    }

    func refresh() {
        // A card on a state with nothing to show folds away (done went back to rest).
        if model.isOpen, !model.showsPrompt, model.tone == .rest { presenter.close() }
        if presenter.isIdle, !model.isOpen, let placement = Self.placement(), placement != presenter.placement {
            presenter.place(placement, compact: Self.compact(model, placement))
        }
        guard let placement = presenter.placement else { return }
        let compact = Self.compact(model, placement)
        Self.apply(compact, to: model, placement: placement)
        presenter.setCompact(compact)
        // The elapsed time grows a digit now and then: measure again every second while Nod works.
        if model.tone == .working {
            if ticker == nil {
                ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.refresh() }
                }
            }
        } else {
            ticker?.invalidate()
            ticker = nil
        }
    }

    /// The wing's two sides for the current state, or nil for rest.
    static func compact(_ model: IslandModel, _ placement: IslandPlacement, now: Date = Date()) -> (leading: CGFloat, trailing: CGFloat)? {
        guard let wing = model.wing else { return nil }
        let elapsed = model.activity.map { now.timeIntervalSince($0.since) }
        return IslandMetrics.wing(wing, line: model.wingLine, elapsed: elapsed, hint: model.hotkey ?? "", notch: placement.isNotch)
    }

    /// The content the wing shows and its sides after the geometry clamped them. A wing going back to rest keeps its
    /// last content, so its words fade with the shape instead of vanishing first.
    static func apply(_ compact: (leading: CGFloat, trailing: CGFloat)?, to model: IslandModel, placement: IslandPlacement) {
        guard let compact, let wing = model.wing else { return }
        let drop = model.isOpen ? IslandDropZone.none : model.dropZone
        let shown = IslandModel.Shown(tone: model.tone, wing: wing, line: model.wingLine, since: model.activity?.since, drop: drop)
        if shown != model.shown { model.shown = shown }
        let rect = IslandGeometry.compact(placement, leading: compact.leading, trailing: compact.trailing)
        var layout = model.layout
        switch placement {
        case .notch(let housing, _):
            layout.leading = max(0, housing.minX - rect.minX)
            layout.trailing = max(0, rect.maxX - housing.maxX)
        case .menuBar:
            layout.trailing = compact.trailing
            layout.leading = max(0, rect.width - compact.trailing)
        }
        if layout != model.layout { model.layout = layout }
    }

    /// On the display under the pointer: at its notch when it has one, otherwise below its menu bar.
    static func placement() -> IslandPlacement? {
        let screens = NSScreen.screens
        let main = NSScreen.main.flatMap { main in screens.firstIndex { $0 == main } } ?? (screens.isEmpty ? nil : 0)
        guard let index = IslandGeometry.screenIndex(frames: screens.map(\.frame), pointer: NSEvent.mouseLocation, fallback: main)
        else { return nil }
        let screen = screens[index]
        if let housing = IslandGeometry.housing(screen: screen.frame, leftArea: screen.auxiliaryTopLeftArea,
                                                rightArea: screen.auxiliaryTopRightArea, topInset: screen.safeAreaInsets.top) {
            return .notch(housing: housing, screen: screen.frame)
        }
        return IslandGeometry.placement(screen: screen.frame, visible: screen.visibleFrame, leftArea: nil, rightArea: nil, topInset: 0)
    }

    // MARK: Actions

    private func open(_ cause: IslandPresentation.OpenCause) {
        if !model.isOpen, presenter.isIdle, let placement = Self.placement(), placement != presenter.placement {
            presenter.place(placement, compact: Self.compact(model, placement))
        }
        guard presenter.placement != nil else { return }
        switch cause {
        case .hotkey, .drop:
            model.showsPrompt = true
            model.perform(model.draft.open(cause == .hotkey ? .hotkey : .drop))
        case .click:
            // At rest, right after an answer and on Nod's question the card is the prompt, with the answer above it.
            model.showsPrompt = model.tone == .rest || model.tone == .done || model.asking != nil
            if model.showsPrompt { model.perform(model.draft.open(.click)) }
        case .approval:
            // The person may be typing in the prompt they opened: the approval waits in the wing for them.
            if model.isOpen, model.showsPrompt { return }
            // Nod's question is answered in the prompt card; an approval has its own card.
            model.showsPrompt = model.asking != nil
        }
        openCause = cause
        model.isOpen = true
        presenter.open(key: IslandPresentation.takesKey(cause))
        if IslandPresentation.takesKey(cause), model.showsPrompt { model.focusToken += 1 }
        refresh()
    }

    private func compactClicked() {
        if model.isOpen { presenter.close(); return }
        open(.click)
    }

    private func hotkeyPressed() {
        let action = IslandPresentation.hotkey(open: model.isOpen, prompt: model.showsPrompt, key: presenter.panel.isKeyWindow,
                                               approvalCard: model.showsApprovalCard)
        // Closing turns the microphone off (`PromptDraft.closed`) and keeps the draft.
        if action == .hide { closePrompt(); return }
        // The approval card keeps showing; its keys work now. The click guard keeps running from when it appeared.
        if action == .takeKey { presenter.open(key: true); return }
        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApp = front }
        if action == .prompt {
            model.showsPrompt = true
            model.perform(model.draft.open(.hotkey))
            openCause = .hotkey
            presenter.open(key: true)
            model.focusToken += 1
        } else {
            open(.hotkey)
        }
    }

    /// ⌥Return, ⌥⌫ or ⌘. on the card that has the keyboard: the same as a click on its button.
    private func cardKey(_ key: IslandPresentation.CardKey, _ modifier: IslandPresentation.KeyModifier) -> Bool {
        guard let action = IslandPresentation.keyAction(key, modifier, offers: model.cardOffers) else { return false }
        switch action {
        case .approve: model.answer(approved: true)
        case .decline: model.answer(approved: false)
        case .stop: model.stop()
        case .sendPicks: model.sendPicks()
        }
        return true
    }

    /// Escape: the prompt is discarded and the keyboard goes back; any other card only folds away.
    private func escape() {
        if model.showsPrompt {
            model.perform(model.draft.escape())
            closePrompt()
        } else {
            presenter.close()
        }
    }

    private func closePrompt() {
        presenter.close()
        if let app = previousApp, !app.isTerminated { app.activate() }
        previousApp = nil
    }

    // MARK: Drops

    /// A file drag in another app: near the top of the island's display the closed island shows where to drop.
    private func followDrag(_ type: NSEvent.EventType) {
        let board = NSPasteboard(name: .drag)
        switch type {
        case .leftMouseDown:
            dragStart = board.changeCount
        case .leftMouseUp where model.dropZone != .none:
            // The drop reaches the island after this event: a zone that got nothing goes away once it would have.
            dragEnd?.cancel()
            dragEnd = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled, let self, NSEvent.pressedMouseButtons & 1 == 0 else { return }
                setDropZone(.none)
            }
        case .leftMouseDragged:
            guard board.changeCount != dragStart, DropReader.carriesFiles(board) else { return }
            if model.dropZone == .none, !model.isOpen, presenter.isIdle, let placement = Self.placement(), placement != presenter.placement {
                presenter.place(placement, compact: Self.compact(model, placement))
            }
            guard let placement = presenter.placement, model.dropZone != .over else { return }
            let near = IslandDropZone.isNear(pointer: NSEvent.mouseLocation, placement: placement, screens: NSScreen.screens.map(\.frame))
            setDropZone(near ? .near : .none)
        default:
            break
        }
    }

    private func dragOver(_ over: Bool) {
        if over { setDropZone(.over) } else if model.dropZone == .over { setDropZone(.near) }
    }

    private func setDropZone(_ zone: IslandDropZone) {
        guard model.dropZone != zone else { return }
        model.dropZone = zone
        refresh()
    }

    /// Files dropped on the island: the prompt opens with the keyboard (and the microphone as it was), one chip per
    /// file, each uploading at once. Nothing is sent until Return.
    private func dropped(_ files: [DroppedFile]) {
        dragEnd?.cancel()
        setDropZone(.none)
        guard !files.isEmpty else { return }
        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApp = front }
        if model.isOpen {
            if !model.showsPrompt {
                model.showsPrompt = true
                model.perform(model.draft.open(.drop))
            }
            openCause = .drop
            presenter.open(key: true)
            model.focusToken += 1
        } else {
            open(.drop)
        }
        model.dropped(files)
        refresh()
    }
}
