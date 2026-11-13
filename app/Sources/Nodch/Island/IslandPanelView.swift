// Adapted from Pippa: app/Sources/Pippa/Views/IslandViews.swift (IslandPanelView, IslandButtonStyle, IslandButtonRow)
import AppKit
import NodchCore
import SwiftUI

/// The open card: at the notch a row beside the housing names the state, and the card grows below it. It shows the
/// quick prompt, or what Nod is doing, waiting for, finished or failed at.
struct IslandPanelView: View {
    var model: IslandModel
    var onHeight: (CGFloat) -> Void = { _ in }
    @FocusState private var promptFocused: Bool

    var body: some View {
        let layout = model.layout
        VStack(spacing: 0) {
            if layout.notch { menuBarRow(layout) }
            VStack(alignment: .leading, spacing: IslandStyle.gap) {
                if !layout.notch { header }
                ZStack(alignment: .topLeading) {
                    if model.showsPromptCard {
                        IslandPromptCard(model: model, focused: $promptFocused).transition(.opacity)
                    } else {
                        IslandStatusCard(model: model).transition(.opacity)
                    }
                }
                .animation(IslandStyle.fade, value: model.showsPrompt)
                .animation(IslandStyle.fade, value: model.tone)
            }
            .padding(.horizontal, IslandStyle.padding)
            .padding(.top, layout.notch ? IslandStyle.notchTop : IslandStyle.padding - 2)
            .padding(.bottom, IslandStyle.padding)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onHeight($0) }
        }
        .overlay { if model.dropZone == .over { dropHighlight(layout) } }
        .animation(IslandStyle.fade, value: model.dropZone)
        .frame(maxHeight: .infinity, alignment: .top)
        .fontDesign(.rounded)
        .environment(\.colorScheme, .dark)
        .onAppear { if model.showsPrompt { promptFocused = true } }
        .onChange(of: model.focusToken) { if model.showsPrompt { promptFocused = true } }
    }

    /// Files over the open card: it lights up as one target.
    private func dropHighlight(_ layout: IslandModel.Layout) -> some View {
        let shape = RoundedRectangle(cornerRadius: IslandGeometry.cornerRadius - 6, style: .continuous)
        return shape.fill(IslandStyle.accent.opacity(0.1))
            .overlay(shape.strokeBorder(IslandStyle.accent.opacity(0.9), lineWidth: 1.5))
            // At the notch the ring starts just below the menu bar row, clear of the field.
            .padding(.top, layout.notch ? max(0, layout.rowHeight - 4) : 0)
            .padding(6)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var heading: String {
        model.showsPrompt ? "Ask Nod" : IslandPresentation.heading(model.tone)
    }

    /// Beside the housing: the state on the left, the count or time on the right. A click on it folds the card away.
    private func menuBarRow(_ layout: IslandModel.Layout) -> some View {
        HStack(spacing: 0) {
            // The words when they fit beside the housing, the sign alone when they do not: never a cut word.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    IslandGlyph(tone: model.tone, size: 13, pulses: false)
                    Text(heading).font(IslandStyle.line).foregroundStyle(IslandStyle.white(IslandStyle.primary))
                        .fixedSize()
                }
                IslandGlyph(tone: model.tone, size: 13, pulses: false)
            }
            .padding(.leading, IslandStyle.padding)
            .padding(.trailing, 6)
            .frame(width: max(0, layout.rowLeft), alignment: .leading)
            Spacer(minLength: 0)
            rowTrailing
                .padding(.leading, 6)
                .padding(.trailing, IslandStyle.padding)
                .frame(width: max(0, layout.rowRight), alignment: .trailing)
        }
        .frame(height: layout.rowHeight)
        .contentShape(Rectangle())
        .onTapGesture { model.onCollapse() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(heading)
        .accessibilityAction(named: "Collapse") { model.onCollapse() }
    }

    @ViewBuilder private var rowTrailing: some View {
        if !model.showsPrompt, let (_, more) = model.approval, more > 0 {
            IslandMoreBadge(more: more)
        } else if !model.showsPrompt, let activity = model.activity {
            IslandElapsed(since: activity.since).font(IslandStyle.line).foregroundStyle(IslandStyle.white(IslandStyle.secondary))
        } else if model.showsPrompt, let hotkey = model.hotkey {
            Text(hotkey).font(Font(IslandMetrics.hintFont as CTFont)).foregroundStyle(IslandStyle.white(IslandStyle.tertiary))
        }
    }

    /// Below the menu bar the card carries its own header.
    private var header: some View {
        HStack(spacing: 8) {
            IslandGlyph(tone: model.tone, size: 14, pulses: false)
            Text(heading).font(IslandStyle.line).foregroundStyle(IslandStyle.white(IslandStyle.primary))
            Spacer(minLength: 0)
            rowTrailing
            Button { model.onCollapse() } label: {
                Image(systemName: "chevron.up").font(.system(size: 10, weight: .bold))
                    .foregroundStyle(IslandStyle.white(IslandStyle.secondary))
                    .frame(width: 22, height: 22).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Collapse (esc)")
            .accessibilityLabel("Collapse")
        }
    }
}

/// The quick prompt: Return sends once, Escape discards. Opened with the shortcut it listens, and the words stream
/// into the field; the first keystroke turns the microphone off and keeps them. Dropped files show as chips under
/// the field. A failed send keeps the text and says why under it. Nod's last answer sits above the field while a
/// follow-up still reads in context, and Nod's open question offers its choices there.
struct IslandPromptCard: View {
    var model: IslandModel
    var focused: FocusState<Bool>.Binding
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let draft = model.draft
        VStack(alignment: .leading, spacing: 10) {
            if let answer = model.shownAnswer {
                IslandAnswer(model: model, answer: answer)
            }
            if model.tone != .rest, model.tone != .done, model.asking == nil {
                Text(statusLine).lineLimit(1).truncationMode(.tail)
                .font(IslandStyle.small).foregroundStyle(IslandStyle.white(IslandStyle.secondary))
                // A new line replaces the old one at once: under the card's fade the two showed on top of each other.
                .contentTransition(.identity).transaction { $0.animation = nil }
                .accessibilityElement(children: .combine)
            }
            HStack(alignment: .top, spacing: IslandStyle.buttonGap) {
                field(draft)
                IslandOpenButton(model: model)
            }
            if !draft.attachments.isEmpty {
                IslandChips(model: model, attachments: draft.attachments)
            }
            voiceStatus(draft)
            footer(draft)
        }
        .animation(IslandStyle.fade, value: draft.error)
        .animation(IslandStyle.fade, value: draft.attachments)
        .animation(IslandStyle.fade, value: draft.voice)
    }

    private func field(_ draft: PromptDraft) -> some View {
        // The transcriber writes `draft` directly; only the person's own edits come through the binding.
        let text = Binding(get: { model.draft.display }, set: { model.typed($0) })
        // While the microphone is on, the words show in `live` on top of the field. The focused field does not
        // reliably take the transcriber's words while it is being edited (it stayed empty mid-sentence), so its own
        // text is hidden then; it keeps the focus, so the first keystroke still takes over (`PromptDraft.takeOver`).
        let live = draft.voice.isActive || draft.voice == .finishing
        return ZStack(alignment: .topLeading) {
            TextField("Ask Nod", text: text,
                      prompt: Text(live ? "" : placeholder(draft)).foregroundStyle(IslandStyle.white(IslandStyle.secondary)),
                      axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.plain)
                .foregroundStyle(live ? Color.clear : IslandStyle.white(IslandStyle.primary))
                .focused(focused)
                .disabled(draft.sending)
                .onSubmit { model.submitPrompt() }
            if live { liveWords(draft) }
        }
            .font(IslandStyle.body)
            .onChange(of: draft.display) {
                if let shown = IslandFieldEditor.show(model.draft.display) { model.draft.fieldShows(shown) }
            }
            .padding(.vertical, 6)
            .padding(.trailing, 50)
            .padding(.horizontal, 10)
            .frame(minHeight: IslandStyle.controlHeight)
            .background(RoundedRectangle(cornerRadius: IslandStyle.wellRadius, style: .continuous).fill(IslandStyle.white(0.1)))
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 2) {
                    IslandMicButton(model: model, voice: draft.voice, level: model.voiceLevel)
                    if draft.sending || draft.voice == .finishing {
                        ProgressView().controlSize(.small).scaleEffect(0.7)
                            .frame(width: 18, height: IslandStyle.controlHeight)
                            .accessibilityHidden(true)
                    } else {
                        // The same path as Return, so the mouse can send too.
                        Button { model.submitPrompt() } label: {
                            Image(systemName: "return").font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(IslandStyle.white(draft.canSend ? IslandStyle.secondary : IslandStyle.tertiary - 0.1))
                                .frame(width: 18, height: IslandStyle.controlHeight)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!draft.canSend)
                        .help("Send (↩)")
                        .accessibilityLabel("Send")
                    }
                }
                .padding(.trailing, 6)
            }
            .accessibilityLabel("Ask Nod")
            .accessibilityHint((draft.voice == .listening ? "Listening. Typing takes over, Return sends, " : "Return sends, ")
                               + (draft.discardsOnEscape ? "Escape discards" : "Escape closes"))
    }

    /// What was heard so far, the words still being recognized dimmed after it, or where the microphone is at.
    private func liveWords(_ draft: PromptDraft) -> some View {
        let (heard, hearing) = draft.live
        var words = AttributedString(heard)
        words.foregroundColor = IslandStyle.white(IslandStyle.primary)
        var pending = AttributedString(hearing)
        pending.foregroundColor = IslandStyle.white(IslandStyle.secondary)
        words.append(pending)
        return Group {
            if draft.display.isEmpty {
                Text(placeholder(draft)).foregroundStyle(IslandStyle.white(IslandStyle.secondary))
            } else {
                // The newest words stay in view: a long dictation loses its start, not its end.
                Text(words).lineLimit(5).truncationMode(.head)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .allowsHitTesting(false)
    }

    private func placeholder(_ draft: PromptDraft) -> String {
        switch draft.voice {
        case .starting: "Getting the microphone ready…"
        case .listening: model.listeningIn.map { "Listening in \(SpeechLanguage.shortName($0))… or type" } ?? "Listening… or type"
        default:
            if !draft.attachments.isEmpty { "Ask about the files…" }
            else if model.asking != nil { "Or answer in your own words…" }
            else if model.shownAnswer != nil { "Follow up…" }
            else { "Ask Nod…" }
        }
    }

    @ViewBuilder private func voiceStatus(_ draft: PromptDraft) -> some View {
        if case .unavailable(let hint) = draft.voice {
            footnote(hint.text, symbol: "mic.slash")
        } else if draft.voice.isActive || draft.voice == .finishing || draft.voiceReady {
            HStack(spacing: 7) {
                if draft.voice == .listening {
                    HStack(alignment: .center, spacing: 2) {
                        ForEach(0..<5) { index in
                            Capsule().fill(IslandStyle.accent)
                                .frame(width: 3, height: 4 + CGFloat(min(1, max(0, model.voiceLevel * 2 - Float(index) * 0.18))) * 10)
                        }
                    }
                    .frame(width: 23, height: 14)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: model.voiceLevel)
                    .accessibilityHidden(true)
                } else {
                    Image(systemName: draft.voiceReady ? "checkmark.circle.fill" : "mic.fill")
                        .foregroundStyle(IslandStyle.accent)
                }
                Text(draft.voice == .starting ? "Preparing microphone…" :
                     draft.voice == .listening ? "Listening · type to take over" :
                     draft.voice == .finishing ? "Transcribing…" : "Ready to edit")
            }
            .font(IslandStyle.caption).foregroundStyle(IslandStyle.white(IslandStyle.secondary))
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder private func footer(_ draft: PromptDraft) -> some View {
        if let error = draft.error {
            IslandErrorLine(text: error)
        } else if let notice = draft.notice {
            footnote(notice, symbol: "info.circle")
        } else {
            Text(IslandPresentation.promptHints(question: model.asking?.question, discards: draft.discardsOnEscape))
                .font(IslandStyle.caption).foregroundStyle(IslandStyle.white(IslandStyle.tertiary))
                .accessibilityHidden(true)
        }
    }

    private func footnote(_ text: String, symbol: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .font(IslandStyle.caption).foregroundStyle(IslandStyle.white(IslandStyle.secondary))
        .accessibilityElement(children: .combine)
    }

    private var statusLine: String {
        switch model.tone {
        case .offline: "Nod is offline"
        case .needsYou: "Waiting for you: \(model.line)"
        case .working: "Working: \(model.line)"
        default: model.line
        }
    }
}

/// The focused field's editor, from AppKit. SwiftUI may leave it at an older text when the binding changes from
/// outside (the transcriber) while it is being edited; then the next keystroke would edit that older text. `show`
/// puts the draft's text into it, caret at the end. A no-op when the editor already shows it, holds an unfinished
/// input-method composition, or is not the island's. Returns what the editor holds afterwards, nil when unknown.
@MainActor enum IslandFieldEditor {
    static func show(_ text: String) -> String? {
        guard let window = NSApp.keyWindow as? IslandPanel, let editor = window.firstResponder as? NSTextView,
              editor.isFieldEditor, !editor.hasMarkedText() else { return nil }
        if editor.string != text {
            editor.string = text
            editor.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        }
        return editor.string
    }
}

/// Nod's answer in full, as Markdown, scrolling when it is long. On an open question its choices follow: one click
/// answers a single-choice question; on a multiple-choice one the clicks tick choices and Send answers.
struct IslandAnswer: View {
    var model: IslandModel
    let answer: NodAnswer

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            IslandScrollingArea(maxHeight: max(80, min(300, model.layout.maxContent - 190))) {
                IslandMarkdown(text: answer.text)
            }
            if let question = answer.question {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(question.choices) { choice in choiceButton(choice, multiple: question.multiple) }
                }
                .disabled(model.draft.sending || model.answerGuarded)
                .opacity(model.answerGuarded ? 0.55 : 1)
                if question.multiple {
                    HStack {
                        Spacer(minLength: 0)
                        Button { model.sendPicks() } label: {
                            HStack(spacing: 6) {
                                if model.draft.sending { ProgressView().controlSize(.mini) }
                                Text(model.draft.display.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Send" : "Send with my words")
                            }
                        }
                        .buttonStyle(IslandButtonStyle(prominent: true))
                        .disabled(model.picked.isEmpty || model.draft.sending)
                        .accessibilityHint("Option-Return, when the field is empty")
                    }
                }
            }
        }
        .id(answer.id)
    }

    private func choiceButton(_ choice: NodQuestion.Choice, multiple: Bool) -> some View {
        let ticked = model.picked.contains(choice.id)
        let highlighted = model.asking?.id == answer.id && model.highlightedChoice == choice.id
        return Button { model.pick(choice) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if multiple {
                    Image(systemName: ticked ? "checkmark.square.fill" : "square").font(.system(size: 12, weight: .medium))
                        .foregroundStyle(ticked ? IslandStyle.accent : IslandStyle.white(IslandStyle.secondary))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(choice.label).font(IslandStyle.body).foregroundStyle(IslandStyle.white(IslandStyle.primary))
                    if let detail = choice.detail, !detail.isEmpty, detail.lowercased() != choice.label.lowercased() {
                        Text(detail).font(IslandStyle.small).foregroundStyle(IslandStyle.white(IslandStyle.secondary))
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 11).padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: IslandStyle.wellRadius, style: .continuous)
                .fill(ticked ? IslandStyle.accent.opacity(0.22) : IslandStyle.white(0.1)))
            .overlay(RoundedRectangle(cornerRadius: IslandStyle.wellRadius, style: .continuous)
                .stroke(highlighted ? IslandStyle.accent : .clear, lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(choice.label)
        .accessibilityAddTraits(ticked ? .isSelected : [])
    }
}

/// Voice on or off by hand. While it listens a soft ring breathes with the microphone's level.
struct IslandMicButton: View {
    var model: IslandModel
    let voice: VoiceState
    let level: Float
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let listening = voice == .listening
        Button { model.toggleVoice() } label: {
            ZStack {
                Circle().fill(IslandStyle.accent.opacity(listening ? 0.22 : 0))
                    .frame(width: 20, height: 20)
                    .scaleEffect(listening ? 0.8 + CGFloat(level) * 0.45 : 0.6)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: level)
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
            }
            .frame(width: 26, height: IslandStyle.controlHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(voice == .finishing || model.draft.sending)
        .help(listening || voice == .starting ? "Stop listening  ·  right-click for the language" : "Dictate  ·  right-click for the language")
        .accessibilityLabel(listening || voice == .starting ? "Stop listening" : "Dictate")
        .contextMenu { IslandLanguageMenu(model: model) }
    }

    private var symbol: String {
        switch voice {
        case .listening, .starting, .finishing: "mic.fill"
        case .unavailable: "mic.slash"
        case .off: "mic"
        }
    }

    private var color: Color {
        switch voice {
        case .listening: IslandStyle.accent
        case .starting, .finishing: IslandStyle.white(IslandStyle.secondary)
        case .unavailable: IslandStyle.white(IslandStyle.tertiary)
        case .off: IslandStyle.white(IslandStyle.secondary)
        }
    }
}

/// The dictation language: the system's by default, the person's own languages next, every other one below.
struct IslandLanguageMenu: View {
    var model: IslandModel

    var body: some View {
        let choice = Binding(get: { model.speechChoice }, set: { model.chooseSpeechLanguage($0) })
        let menu = model.speechLanguages
        Picker("Dictation Language", selection: choice) {
            Text(menu.yours.first.map { "Automatic (\(SpeechLanguage.name($0)))" } ?? "Automatic").tag(String?.none)
            ForEach(menu.yours, id: \.self) { Text(SpeechLanguage.name($0)).tag(Optional($0)) }
        }
        .pickerStyle(.inline)
        if !menu.others.isEmpty {
            Menu("Other Languages") {
                Picker("Other Languages", selection: choice) {
                    ForEach(menu.others, id: \.self) { Text(SpeechLanguage.name($0)).tag(Optional($0)) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
        }
    }
}

/// A small dot that says the microphone is on; it fades slowly in and out, still under Reduce Motion.
struct IslandListeningDot: View {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || !active)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
            let opacity = active ? (reduceMotion ? 1 : 0.7 + 0.3 * cos(phase * 2 * .pi)) : 0.4
            Circle().fill(active ? IslandStyle.accent : IslandStyle.white(IslandStyle.secondary))
                .frame(width: 6, height: 6)
                .opacity(opacity)
        }
        .frame(width: 6, height: 6)
    }
}

/// The dropped files under the field: uploading, ready or failed, each with its own ×. A failed one says why.
struct IslandChips: View {
    var model: IslandModel
    let attachments: [PromptAttachment]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            IslandFlow(spacing: 6) {
                ForEach(attachments) { chip($0) }
            }
            ForEach(attachments.filter { if case .failed = $0.status { true } else { false } }) { attachment in
                if case .failed(let reason) = attachment.status {
                    IslandErrorLine(text: "\(attachment.name): \(reason)")
                }
            }
        }
    }

    private func chip(_ attachment: PromptAttachment) -> some View {
        let failed = if case .failed = attachment.status { true } else { false }
        return HStack(spacing: 5) {
            Group {
                switch attachment.status {
                case .uploading: ProgressView().controlSize(.mini).scaleEffect(0.8)
                case .ready: Image(systemName: "doc.fill").foregroundStyle(IslandStyle.white(IslandStyle.secondary))
                case .failed: Image(systemName: "exclamationmark.circle.fill").foregroundStyle(IslandStyle.bad)
                }
            }
            .font(.system(size: 10, weight: .semibold))
            .frame(width: 12, height: 12)
            Text(attachment.name)
                .font(IslandStyle.caption)
                .foregroundStyle(failed ? IslandStyle.bad : IslandStyle.white(attachment.status == .uploading ? IslandStyle.secondary : IslandStyle.primary))
                .lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: 150, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)
            Button { model.removeAttachment(attachment.id) } label: {
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                    .foregroundStyle(IslandStyle.white(IslandStyle.secondary))
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(IslandStyle.white(0.1)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(model.draft.sending)
            .help("Remove")
            .accessibilityLabel("Remove \(attachment.name)")
        }
        .padding(.leading, 8).padding(.trailing, 4)
        .frame(height: 24)
        .background(Capsule().fill(failed ? IslandStyle.bad.opacity(0.14) : IslandStyle.white(0.1)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibility(attachment))
    }

    private func accessibility(_ attachment: PromptAttachment) -> String {
        switch attachment.status {
        case .uploading: "\(attachment.name), uploading"
        case .ready: "\(attachment.name), ready"
        case .failed(let reason): "\(attachment.name), failed: \(reason)"
        }
    }
}

/// Left to right, wrapping onto the next row.
struct IslandFlow: SwiftUI.Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (index, frame) in arrange(width: bounds.width, subviews: subviews).frames.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: ProposedViewSize(frame.size))
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (frames: [CGRect], size: CGSize) {
        var frames: [CGRect] = [], x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += row + spacing; row = 0 }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            row = max(row, size.height)
            widest = max(widest, x - spacing)
        }
        return (frames, CGSize(width: widest, height: frames.isEmpty ? 0 : y + row))
    }
}

/// What Nod is doing, waiting for, finished or failed at, with the actions that fit.
struct IslandStatusCard: View {
    var model: IslandModel

    var body: some View {
        switch model.tone {
        case .needsYou:
            if let (approval, more) = model.approval {
                IslandApprovalCard(model: model, approval: approval, more: more).id(approval.id)
            }
        case .working:
            working
        case .offline:
            message(title: "Nod isn’t connected", text: offlineReason, prominentOpen: true)
        case .failed:
            message(title: "Nod couldn’t finish", text: model.line, prominentOpen: true)
        case .rest, .done:
            // Shown by the prompt card, with the answer above the field.
            EmptyView()
        }
    }

    private var offlineReason: String? {
        if case .offline(let reason) = model.state { reason } else { nil }
    }

    private var working: some View {
        let activity = model.activity
        return VStack(alignment: .leading, spacing: IslandStyle.gap) {
            Text(activity?.title ?? "Nod is working")
                .font(IslandStyle.title).foregroundStyle(IslandStyle.white(IslandStyle.primary))
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 7) {
                if let step = activity?.step, !step.isEmpty {
                    row(text: step) { SpinRing(size: 11, lineWidth: 1.5, color: IslandStyle.accent) }
                } else if let activity {
                    row(text: IslandPresentation.line(.working(activity))) { SpinRing(size: 11, lineWidth: 1.5, color: IslandStyle.accent) }
                }
                if let site = activity?.site, !site.isEmpty {
                    row(text: site) {
                        Image(systemName: "globe").font(.system(size: 11, weight: .medium))
                            .foregroundStyle(IslandStyle.white(IslandStyle.secondary))
                    }
                }
            }
            if let error = model.actionError { IslandErrorLine(text: error) }
            HStack(spacing: IslandStyle.buttonGap) {
                IslandOpenButton(model: model)
                Spacer(minLength: 0)
                Button { model.stop() } label: {
                    HStack(spacing: 6) {
                        if model.stopping { ProgressView().controlSize(.mini) } else {
                            RoundedRectangle(cornerRadius: 1.5).frame(width: 8, height: 8)
                        }
                        Text("Stop")
                    }
                }
                .buttonStyle(IslandButtonStyle())
                .disabled(model.stopping)
                .help("Stop (⌘.)")
                .accessibilityLabel("Stop Nod")
                .accessibilityHint("Command-Period")
            }
        }
    }

    private func row<Icon: View>(text: String, @ViewBuilder icon: () -> Icon) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            icon().frame(width: 14, height: 14).alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            Text(text).font(IslandStyle.small).foregroundStyle(IslandStyle.white(IslandStyle.primary - 0.1))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func message(title: String, text: String?, prominentOpen: Bool) -> some View {
        VStack(alignment: .leading, spacing: IslandStyle.gap) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(IslandStyle.title).foregroundStyle(IslandStyle.white(IslandStyle.primary))
                if let text, !text.isEmpty {
                    IslandScrollingText(text: text, maxHeight: min(IslandStyle.bodyMaxHeight, model.layout.maxContent - 120), well: false)
                }
            }
            HStack {
                Spacer(minLength: 0)
                IslandOpenButton(model: model, prominent: prominentOpen)
            }
        }
    }
}

/// An approval: what Nod wants to do, in full, and the person's decision. Nothing is pre-selected, Return never
/// approves, and Escape only folds the card away.
struct IslandApprovalCard: View {
    var model: IslandModel
    let approval: PendingApproval
    let more: Int

    var body: some View {
        VStack(alignment: .leading, spacing: IslandStyle.gap) {
            IslandScrollingArea(maxHeight: detailsMax) { details }
            if approval.bodyCut {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Image(systemName: "scissors").font(.system(size: 11, weight: .semibold)).foregroundStyle(IslandStyle.warn)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Nod shortened this text. The full text is in Nod.")
                            .font(IslandStyle.small).foregroundStyle(IslandStyle.white(IslandStyle.secondary + 0.1))
                            .fixedSize(horizontal: false, vertical: true)
                        Button { model.openNod() } label: {
                            HStack(spacing: 3) {
                                Text("Open in Nod")
                                Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .bold))
                            }
                            .font(IslandStyle.small.weight(.semibold)).foregroundStyle(IslandStyle.accent)
                            .fixedSize()
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open the full text in Nod")
                    }
                }
            }
            if let error = model.actionError { IslandErrorLine(text: error) }
            IslandButtonRow(lead: true) {
                IslandOpenButton(model: model)
                decision("Decline", approved: false)
                decision("Approve", approved: true)
            }
            if more > 0 {
                Text(more == 1 ? "1 more approval waits after this one." : "\(more) more approvals wait after this one.")
                    .font(IslandStyle.caption).foregroundStyle(IslandStyle.white(IslandStyle.tertiary + 0.1))
            }
            Text(IslandPresentation.approvalHints).font(IslandStyle.caption)
                .foregroundStyle(IslandStyle.white(IslandStyle.tertiary))
                .accessibilityHidden(true)
        }
        .animation(IslandStyle.fade, value: model.actionError)
        // The click guard runs from when the card is on screen, also after the prompt hid it or it was folded away.
        .onAppear { model.startAnswerGuard() }
        .onChange(of: approval.id) { model.startAnswerGuard() }
    }

    /// Title, question, fields and body scroll together in what the display leaves after the button row, so the
    /// decision stays reachable however long Nod's text is.
    private var detailsMax: CGFloat {
        max(120, model.layout.maxContent - 170)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: IslandStyle.gap) {
            VStack(alignment: .leading, spacing: 4) {
                if !approval.app.isEmpty {
                    Text(approval.app.uppercased())
                        .font(IslandStyle.caption.weight(.semibold)).tracking(0.6)
                        .foregroundStyle(IslandStyle.accent)
                        .accessibilityLabel("App: \(approval.app)")
                }
                Text(approval.title.isEmpty ? "Nod wants to go ahead" : approval.title)
                    .font(IslandStyle.title).foregroundStyle(IslandStyle.white(IslandStyle.primary))
                    .fixedSize(horizontal: false, vertical: true)
                if let question = approval.question {
                    Text(question).font(IslandStyle.small)
                        .foregroundStyle(IslandStyle.white(IslandStyle.secondary))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !approval.fields.isEmpty {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 6) {
                    ForEach(Array(approval.fields.enumerated()), id: \.offset) { _, field in
                        GridRow {
                            Text(field.label).font(IslandStyle.small)
                                .foregroundStyle(IslandStyle.white(IslandStyle.secondary))
                                .gridColumnAlignment(.leading)
                                .fixedSize()
                            Text(field.value).font(IslandStyle.small.weight(.medium))
                                .foregroundStyle(IslandStyle.white(IslandStyle.primary))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            if let body = approval.body, !body.isEmpty {
                Text(body)
                    .font(IslandStyle.body).foregroundStyle(IslandStyle.white(IslandStyle.primary - 0.05))
                    .lineSpacing(2).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: IslandStyle.wellRadius - 2, style: .continuous).fill(IslandStyle.white(0.07)))
            }
        }
    }

    private func decision(_ title: String, approved: Bool) -> some View {
        let busy = model.answering
        return Button { model.answer(approved: approved) } label: {
            HStack(spacing: 6) {
                if busy == approved { ProgressView().controlSize(.mini).tint(.white) }
                Text(title)
            }
        }
        .buttonStyle(IslandButtonStyle(prominent: approved))
        // Dimmed while the click guard holds, so an early click is visibly not taken.
        .disabled(busy != nil || model.answerGuarded)
        .accessibilityLabel(approved ? "Approve: \(approval.title)" : "Decline: \(approval.title)")
        .accessibilityHint(approved ? "Option-Return" : "Option-Delete")
    }
}

/// Content shown in full: up to `maxHeight` as is, taller inside a scroll view that says it scrolls. Never cut.
struct IslandScrollingArea<Content: View>: View {
    let maxHeight: CGFloat
    @ViewBuilder var content: Content
    /// Without Xcode there is no SwiftUI macro plugin: `@State` is spelled out.
    private let heightState = State(initialValue: CGFloat(0))
    private var height: CGFloat { heightState.wrappedValue }

    var body: some View {
        let overflows = height > maxHeight + 0.5
        VStack(alignment: .leading, spacing: 5) {
            ScrollView {
                content
                    .padding(.bottom, overflows ? 8 : 0)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heightState.wrappedValue = $0 }
            }
            .scrollIndicators(overflows ? .visible : .never)
            .frame(height: max(1, min(height, maxHeight)))
            .mask {
                VStack(spacing: 0) {
                    Color.black
                    LinearGradient(colors: [.black, overflows ? .black.opacity(0.15) : .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: 18)
                }
            }
            if overflows {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down").font(.system(size: 9, weight: .bold))
                    Text("Scroll for the full text")
                }
                .font(IslandStyle.caption).foregroundStyle(IslandStyle.white(IslandStyle.tertiary + 0.1))
                .accessibilityHidden(true)
            }
        }
    }
}

/// Text that is shown in full: up to `maxHeight` as is, longer inside a scroll view that says it scrolls. Never cut.
struct IslandScrollingText: View {
    let text: String
    let maxHeight: CGFloat
    var well: Bool
    /// Without Xcode there is no SwiftUI macro plugin: `@State` is spelled out.
    private let heightState = State(initialValue: CGFloat(0))
    private var height: CGFloat { heightState.wrappedValue }

    var body: some View {
        let overflows = height > maxHeight + 0.5
        VStack(alignment: .leading, spacing: 5) {
            ScrollView {
                Text(text)
                    .font(well ? IslandStyle.body : IslandStyle.small)
                    .foregroundStyle(IslandStyle.white(well ? IslandStyle.primary - 0.05 : IslandStyle.secondary + 0.15))
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(well ? 10 : 0)
                    .padding(.bottom, overflows ? 8 : 0)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heightState.wrappedValue = $0 }
            }
            .scrollIndicators(overflows ? .visible : .never)
            .frame(height: max(1, min(height, maxHeight)))
            .mask {
                VStack(spacing: 0) {
                    Color.black
                    LinearGradient(colors: [.black, overflows ? .black.opacity(0.15) : .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: 18)
                }
            }
            .background {
                if well { RoundedRectangle(cornerRadius: IslandStyle.wellRadius - 2, style: .continuous).fill(IslandStyle.white(0.07)) }
            }
            if overflows {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down").font(.system(size: 9, weight: .bold))
                    Text("Scroll for the full text")
                }
                .font(IslandStyle.caption).foregroundStyle(IslandStyle.white(IslandStyle.tertiary + 0.1))
                .accessibilityHidden(true)
            }
        }
    }
}

struct IslandErrorLine: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.circle.fill").font(.system(size: 11)).foregroundStyle(IslandStyle.bad)
            Text(text).font(IslandStyle.small).foregroundStyle(IslandStyle.bad)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(text)")
    }
}

/// "Open Nod": everything bigger than the notch happens in Nod's own window.
struct IslandOpenButton: View {
    var model: IslandModel
    var prominent = false

    var body: some View {
        Button { model.openNod() } label: {
            HStack(spacing: 5) {
                Text("Open Nod")
                Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .bold)).opacity(0.8)
            }
        }
        .buttonStyle(IslandButtonStyle(prominent: prominent))
        .accessibilityLabel("Open Nod")
    }
}

/// Capsule buttons that read on black: quiet, or the one primary action with white text on blue.
struct IslandButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(IslandStyle.detail)
            .lineLimit(1)
            .foregroundStyle(prominent ? Color.white : IslandStyle.white(IslandStyle.primary))
            .padding(.horizontal, 13)
            .frame(height: IslandStyle.controlHeight)
            .background(Capsule().fill(prominent ? IslandStyle.accentFill.opacity(configuration.isPressed ? 0.8 : 1)
                                                 : IslandStyle.white(configuration.isPressed ? 0.24 : 0.14)))
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.55)
            .fixedSize()
    }
}

extension View {
    /// A text field's quiet well on the island, as tall as the buttons beside it.
    func islandWell() -> some View {
        padding(.horizontal, 10)
            .frame(height: IslandStyle.controlHeight)
            .background(RoundedRectangle(cornerRadius: IslandStyle.wellRadius, style: .continuous).fill(IslandStyle.white(0.1)))
    }
}

/// Capsule buttons on the right, 8 pt apart, wrapping onto another row instead of truncating. With `lead`, the first
/// one sits at the left of the same row when everything fits, otherwise on its own row below the others.
struct IslandButtonRow: SwiftUI.Layout {
    var lead = false

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrangement(width: proposal.width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (index, frame) in arrangement(width: bounds.width, subviews: subviews).frames.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: ProposedViewSize(frame.size))
        }
    }

    private func arrangement(width: CGFloat?, subviews: Subviews) -> (frames: [CGRect], size: CGSize) {
        let gap = IslandStyle.buttonGap
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let oneRow = sizes.map(\.width).reduce(0, +) + gap * CGFloat(max(0, sizes.count - 1))
        let width = width ?? oneRow
        let first = lead ? 1 : 0
        var rows: [[Int]] = [[]]
        var used: CGFloat = 0
        for index in first..<sizes.count {
            let needed = (rows[rows.count - 1].isEmpty ? 0 : gap) + sizes[index].width
            if !rows[rows.count - 1].isEmpty, used + needed > width {
                rows.append([index]); used = sizes[index].width
            } else {
                rows[rows.count - 1].append(index); used += needed
            }
        }
        let leadBeside = lead && rows.count == 1 && oneRow <= width
        if lead && !leadBeside { rows.append([0]) }
        var frames = [CGRect](repeating: .zero, count: sizes.count)
        var y: CGFloat = 0
        for (number, row) in rows.enumerated() where !row.isEmpty {
            let height = (row + (leadBeside && number == 0 ? [0] : [])).map { sizes[$0].height }.max() ?? 0
            if lead && row == [0] && !leadBeside {
                frames[0] = CGRect(origin: CGPoint(x: 0, y: y + (height - sizes[0].height) / 2), size: sizes[0])
            } else {
                var x = width
                for index in row.reversed() {
                    x -= sizes[index].width
                    frames[index] = CGRect(origin: CGPoint(x: x, y: y + (height - sizes[index].height) / 2), size: sizes[index])
                    x -= gap
                }
                if leadBeside && number == 0 {
                    frames[0] = CGRect(origin: CGPoint(x: 0, y: y + (height - sizes[0].height) / 2), size: sizes[0])
                }
            }
            y += height + gap
        }
        return (frames, CGSize(width: width, height: max(0, y - gap)))
    }
}
