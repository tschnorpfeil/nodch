// Adapted from Pippa: app/Sources/Pippa/Views/IslandViews.swift (IslandCompactView, IslandLine)
import NodchCore
import SwiftUI

/// The wings beside the housing, or the pill below the menu bar: a glyph and a line on the leading side; elapsed time,
/// Stop, "+N" or the shortcut on the trailing side. A click anywhere but Stop opens the card.
struct IslandCompactView: View {
    var model: IslandModel

    var body: some View {
        let shown = model.shown, layout = model.layout
        ZStack {
            if layout.leading > 0 {
                leading(shown)
                    .padding(.leading, IslandMetrics.inset)
                    .padding(.trailing, layout.notch ? IslandMetrics.inner : IslandMetrics.pillInner)
                    .frame(width: layout.leading, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if layout.trailing > 0 {
                trailing(shown)
                    .padding(.leading, layout.notch ? IslandMetrics.inner : IslandMetrics.pillInner)
                    .padding(.trailing, layout.notch ? IslandMetrics.inset - 2 : IslandMetrics.inset - 4)
                    .frame(width: layout.trailing, alignment: .trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { model.onCompactClick() }
        .contextMenu { IslandAppMenu(commands: model.commands) }
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel(shown))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.onCompactClick() }
    }

    private func accessibilityLabel(_ shown: IslandModel.Shown) -> String {
        if shown.drop != .none { return "Drop files to attach them to a prompt" }
        return switch shown.tone {
        case .rest: "nodch. Open the quick prompt"
        case .needsYou: "Nod needs you: \(shown.line)"
        default: "Nod, \(IslandPresentation.heading(shown.tone).lowercased()): \(shown.line)"
        }
    }

    private func leading(_ shown: IslandModel.Shown) -> some View {
        HStack(spacing: IslandMetrics.glyphGap) {
            if shown.drop != .none {
                Image(systemName: "arrow.down.doc.fill").font(.system(size: IslandMetrics.glyph - 2, weight: .semibold))
                    .foregroundStyle(shown.drop == .over ? IslandStyle.accent : IslandStyle.white(IslandStyle.secondary))
                    .frame(width: IslandMetrics.glyph, height: IslandMetrics.glyph)
                    .accessibilityHidden(true)
            } else if shown.wing.showsGlyph {
                IslandGlyph(tone: shown.tone, size: IslandMetrics.glyph)
            }
            if shown.wing.showsLine, !shown.line.isEmpty {
                Text(shown.line)
                    .font(IslandStyle.line)
                    .foregroundStyle(shown.drop == .over ? IslandStyle.accent
                                     : IslandStyle.white(shown.tone == .working ? IslandStyle.primary - 0.1 : IslandStyle.primary))
                    .lineLimit(1).truncationMode(.tail)
                    .contentTransition(.opacity)
                    .transition(.opacity)
            }
        }
        .animation(IslandStyle.fade, value: shown.line)
        .animation(IslandStyle.fade, value: shown.wing.showsLine)
    }

    private func trailing(_ shown: IslandModel.Shown) -> some View {
        HStack(spacing: 6) {
            if shown.wing.showsElapsed, let since = shown.since {
                IslandElapsed(since: since).font(IslandStyle.line).foregroundStyle(IslandStyle.white(IslandStyle.secondary))
            }
            if shown.wing.showsStop { IslandStopButton(model: model) }
            if shown.wing.more > 0 { IslandMoreBadge(more: shown.wing.more) }
            if shown.wing.showsChevron {
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                    .foregroundStyle(IslandStyle.white(IslandStyle.secondary))
                    .frame(width: IslandMetrics.chevron)
                    .accessibilityHidden(true)
            }
            if shown.wing.showsHint, let hotkey = model.hotkey {
                Text(hotkey).font(Font(IslandMetrics.hintFont as CTFont)).foregroundStyle(IslandStyle.white(IslandStyle.tertiary))
                    .fixedSize()
                    .accessibilityLabel("Quick prompt: \(hotkey)")
            }
        }
    }
}

/// The state's sign: a spinner while Nod works, a raised hand when it waits for you, a check, a warning, "offline",
/// and at rest a small green dot that says nodch is connected.
struct IslandGlyph: View {
    let tone: IslandTone
    var size: CGFloat = 14
    /// The raised hand pulses in the wing; in a header it holds still.
    var pulses = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch tone {
            case .working:
                SpinRing(size: size - 3, lineWidth: 1.75, color: IslandStyle.accent)
            case .rest:
                Circle().fill(IslandStyle.ok).frame(width: 6, height: 6)
                    .accessibilityLabel("Connected")
            case .needsYou:
                Image(systemName: "hand.raised.fill").font(.system(size: size - 2, weight: .semibold))
                    .foregroundStyle(IslandStyle.accent)
                    .symbolEffect(.pulse, options: .repeating, isActive: pulses && !reduceMotion)
            case .done:
                Image(systemName: "checkmark.circle.fill").font(.system(size: size - 1, weight: .semibold))
                    .foregroundStyle(IslandStyle.ok)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: size - 2, weight: .semibold))
                    .foregroundStyle(IslandStyle.bad)
            case .offline:
                Image(systemName: "wifi.slash").font(.system(size: size - 3, weight: .semibold))
                    .foregroundStyle(IslandStyle.white(IslandStyle.secondary))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(tone != .rest)
    }
}

/// A turning arc, turned by the render server; under Reduce Motion a still one.
struct SpinRing: View {
    var size: CGFloat
    var lineWidth: CGFloat
    var color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SpinRingLayer(lineWidth: lineWidth, color: NSColor(color), still: reduceMotion)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

private struct SpinRingLayer: NSViewRepresentable {
    var lineWidth: CGFloat
    var color: NSColor
    var still: Bool

    func makeNSView(context: Context) -> SpinRingNSView { SpinRingNSView() }

    func updateNSView(_ view: SpinRingNSView, context: Context) {
        view.lineWidth = lineWidth
        view.color = color
        view.still = still
    }
}

/// A track and an arc as shape layers; the arc turns by a repeating Core Animation rotation (0.9 s, linear).
private final class SpinRingNSView: NSView {
    private let track = CAShapeLayer()
    private let arc = CAShapeLayer()
    private static let key = "spin"

    var lineWidth: CGFloat = 1.5 { didSet { if lineWidth != oldValue { needsLayout = true } } }
    var color: NSColor = .white { didSet { applyColor() } }
    var still = false { didSet { if still != oldValue { updateSpin() } } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        clipsToBounds = false
        for layer in [track, arc] {
            layer.fillColor = nil
            layer.lineCap = .round
            self.layer?.addSublayer(layer)
        }
        arc.strokeStart = 0
        arc.strokeEnd = 0.28
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        // The stroke is centered on the full-size circle and overflows by half its width, as SwiftUI's stroke did.
        let rect = bounds
        // A path from 12 o'clock, clockwise: strokeEnd 0.28 then covers 28 % of the circle.
        let path = CGMutablePath()
        path.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: rect.width / 2,
                    startAngle: .pi / 2, endAngle: .pi / 2 - 2 * .pi, clockwise: true)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in [track, arc] {
            layer.frame = bounds
            layer.path = path
            layer.lineWidth = lineWidth
        }
        arc.removeAnimation(forKey: Self.key)
        CATransaction.commit()
        applyColor()
        updateSpin()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        arc.removeAnimation(forKey: Self.key)
        updateSpin()
    }

    private func applyColor() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        track.strokeColor = color.withAlphaComponent(0.22 * color.alphaComponent).cgColor
        arc.strokeColor = color.cgColor
        CATransaction.commit()
    }

    private func updateSpin() {
        if still || window == nil {
            arc.removeAnimation(forKey: Self.key)
        } else if arc.animation(forKey: Self.key) == nil {
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = 0
            spin.toValue = -2 * Double.pi   // clockwise on screen, whatever the layer's flip
            spin.duration = 0.9
            spin.repeatCount = .infinity
            spin.timingFunction = CAMediaTimingFunction(name: .linear)
            spin.isRemovedOnCompletion = false
            arc.add(spin, forKey: Self.key)
        }
    }
}

/// Elapsed time since `since`, counting up every second.
struct IslandElapsed: View {
    let since: Date

    var body: some View {
        TimelineView(.periodic(from: since, by: 1)) { context in
            Text(IslandPresentation.elapsed(context.date.timeIntervalSince(since)))
                .monospacedDigit()
                .fixedSize()
                .accessibilityLabel("Running for \(IslandPresentation.elapsed(context.date.timeIntervalSince(since)))")
        }
    }
}

struct IslandStopButton: View {
    var model: IslandModel

    var body: some View {
        Button { model.stop() } label: {
            ZStack {
                Circle().fill(IslandStyle.white(0.16))
                if model.stopping {
                    ProgressView().controlSize(.mini).scaleEffect(0.7)
                } else {
                    RoundedRectangle(cornerRadius: 1.5).fill(IslandStyle.white(IslandStyle.primary)).frame(width: 7, height: 7)
                }
            }
            .frame(width: IslandMetrics.stop, height: IslandMetrics.stop)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(model.stopping)
        .help("Stop Nod")
        .accessibilityLabel("Stop Nod")
    }
}

struct IslandMoreBadge: View {
    let more: Int

    var body: some View {
        Text("+\(more)")
            .font(IslandStyle.caption.weight(.bold)).monospacedDigit()
            .foregroundStyle(IslandStyle.accent)
            .padding(.horizontal, 6)
            .frame(height: 18)
            .background(Capsule().fill(IslandStyle.accent.opacity(0.2)))
            .fixedSize()
            .accessibilityLabel("\(more) more waiting")
    }
}
