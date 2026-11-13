// Adapted from Pippa: app/Sources/Pippa/Views/IslandViews.swift (IslandPanelView, IslandButtonStyle, IslandButtonRow)
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
                    if model.showsPrompt || model.tone == .rest {
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
        .frame(maxHeight: .infinity, alignment: .top)
        .fontDesign(.rounded)
        .environment(\.colorScheme, .dark)
        .onAppear { if model.showsPrompt { promptFocused = true } }
        .onChange(of: model.focusToken) { if model.showsPrompt { promptFocused = true } }
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

/// The quick prompt: Return sends once, Escape discards. A failed send keeps the text and says why under it.
struct IslandPromptCard: View {
    var model: IslandModel
    var focused: FocusState<Bool>.Binding

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 10) {
            if model.tone != .rest {
                Text(statusLine).lineLimit(1).truncationMode(.tail)
                .font(IslandStyle.small).foregroundStyle(IslandStyle.white(IslandStyle.secondary))
                .accessibilityElement(children: .combine)
            }
            HStack(spacing: IslandStyle.buttonGap) {
                TextField("Ask Nod", text: $model.prompt,
                          prompt: Text("Ask Nod…").foregroundStyle(IslandStyle.white(IslandStyle.secondary)))
                    .textFieldStyle(.plain)
                    .font(IslandStyle.body)
                    .foregroundStyle(IslandStyle.white(IslandStyle.primary))
                    .focused(focused)
                    .disabled(model.sending)
                    .onSubmit { model.submitPrompt() }
                    .padding(.trailing, 22)
                    .islandWell()
                    .overlay(alignment: .trailing) {
                        Group {
                            if model.sending {
                                ProgressView().controlSize(.small).scaleEffect(0.7)
                            } else {
                                Image(systemName: "return").font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(IslandStyle.white(model.prompt.isEmpty ? IslandStyle.tertiary - 0.1 : IslandStyle.secondary))
                            }
                        }
                        .frame(width: 22).padding(.trailing, 6)
                        .accessibilityHidden(true)
                    }
                    .accessibilityLabel("Ask Nod")
                    .accessibilityHint("Return sends, Escape discards")
                IslandOpenButton(model: model)
            }
            if let error = model.promptError {
                IslandErrorLine(text: error)
            } else {
                Text("↩ send  ·  esc close").font(IslandStyle.caption)
                    .foregroundStyle(IslandStyle.white(IslandStyle.tertiary))
                    .accessibilityHidden(true)
            }
        }
        .animation(IslandStyle.fade, value: model.promptError)
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
        case .done:
            message(title: "Done", text: doneSummary, prominentOpen: false)
        case .rest:
            EmptyView()
        }
    }

    private var offlineReason: String? {
        if case .offline(let reason) = model.state { reason } else { nil }
    }

    private var doneSummary: String? {
        if case .done(let summary) = model.state { summary } else { nil }
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
                .accessibilityLabel("Stop Nod")
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
                IslandScrollingText(text: body, maxHeight: bodyMax, well: true)
            }
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
        }
        .animation(IslandStyle.fade, value: model.actionError)
    }

    /// The body may take what the display leaves after the rest of the card.
    private var bodyMax: CGFloat {
        max(80, min(IslandStyle.bodyMaxHeight, model.layout.maxContent - 260))
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
        .disabled(busy != nil)
        .accessibilityLabel(approved ? "Approve: \(approval.title)" : "Decline: \(approval.title)")
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
