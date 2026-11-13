// Adapted from Pippa: app/Sources/PippaCore/Island/IslandGeometry.swift
import CoreGraphics

/// Where the island lives on a display. Global AppKit coordinates (origin bottom left, y up).
public enum IslandPlacement: Equatable, Sendable {
    /// Hanging from the camera housing: `housing` is its bounding box, `screen` the display's frame.
    case notch(housing: CGRect, screen: CGRect)
    /// A display without a notch: a pill hanging just below the menu bar, centred on `anchor` (the middle of the menu
    /// bar), kept inside `visible` (the display's `visibleFrame`).
    case menuBar(anchor: CGRect, visible: CGRect)

    public var isNotch: Bool { if case .notch = self { true } else { false } }
}

/// The black shape at one moment: a rectangle with rounded lower corners. At the notch it is flush with the top of
/// the display and meets the menu bar with concave flares; below the menu bar it floats with four round corners.
public struct IslandSilhouette: Equatable, Sendable {
    public var rect: CGRect
    public var radius: CGFloat
    /// Width of the concave flares beside the top edge (notch only, 0 while the shape is inside the housing).
    public var flare: CGFloat
    public var hangsFromTop: Bool

    public init(rect: CGRect, radius: CGFloat, flare: CGFloat, hangsFromTop: Bool) {
        self.rect = rect; self.radius = radius; self.flare = flare; self.hangsFromTop = hangsFromTop
    }

    /// The outline in global coordinates; `offset` moves it into a window (pass the window origin).
    public func path(offset: CGPoint = .zero) -> CGPath {
        let r = rect.offsetBy(dx: -offset.x, dy: -offset.y)
        let path = CGMutablePath()
        guard r.width > 0.01, r.height > 0.01 else { return path }
        let radius = min(radius, r.width / 2, r.height / 2)
        guard hangsFromTop else {
            path.addRoundedRect(in: r, cornerWidth: radius, cornerHeight: radius)
            return path
        }
        let f = min(flare, r.height / 2)
        path.move(to: CGPoint(x: r.minX - f, y: r.maxY))
        path.addLine(to: CGPoint(x: r.maxX + f, y: r.maxY))
        if f > 0.01 {
            path.addArc(center: CGPoint(x: r.maxX + f, y: r.maxY - f), radius: f, startAngle: .pi / 2, endAngle: .pi, clockwise: false)
        }
        path.addLine(to: CGPoint(x: r.maxX, y: r.minY + radius))
        if radius > 0.01 {
            path.addArc(center: CGPoint(x: r.maxX - radius, y: r.minY + radius), radius: radius, startAngle: 0, endAngle: -.pi / 2, clockwise: true)
        }
        path.addLine(to: CGPoint(x: r.minX + radius, y: r.minY))
        if radius > 0.01 {
            path.addArc(center: CGPoint(x: r.minX + radius, y: r.minY + radius), radius: radius, startAngle: -.pi / 2, endAngle: -.pi, clockwise: true)
        }
        path.addLine(to: CGPoint(x: r.minX, y: r.maxY - f))
        if f > 0.01 {
            path.addArc(center: CGPoint(x: r.minX - f, y: r.maxY - f), radius: f, startAngle: 0, endAngle: .pi / 2, clockwise: false)
        }
        path.closeSubpath()
        return path
    }

    /// Hit area: inside the shape, flares excluded.
    public func contains(_ point: CGPoint) -> Bool { path().contains(point) && rect.contains(point) }
}

/// Frames of the island. Pure functions of the display's public geometry (`NSScreen.frame`, `safeAreaInsets.top`,
/// `auxiliaryTopLeftArea`, `auxiliaryTopRightArea`, `visibleFrame`), so checks can run them for any Mac.
///
/// Three resting shapes: `rest` (hidden inside the camera housing, or a line with no height below the menu bar),
/// `compact` (wings left and right of the housing, or a pill below the menu bar) and `open` (the card).
public enum IslandGeometry {
    public static let openWidth: CGFloat = 420
    public static let cornerRadius: CGFloat = 22
    public static let wingRadius: CGFloat = 10
    public static let flare: CGFloat = 6
    /// Distance to the display's edges.
    public static let margin: CGFloat = 8
    /// Between the menu bar and the floating pill.
    public static let menuBarGap: CGFloat = 6
    public static let capsuleHeight: CGFloat = 30
    /// Widest a wing beside the housing may be; its line truncates beyond.
    public static let wingMax: CGFloat = 250
    public static let capsuleMaxWidth: CGFloat = 380
    /// How far a shape stays inside the housing where it has no wing: hidden in the camera cutout, whose corners
    /// curve up before the shape's would.
    public static let housingInset: CGFloat = 6
    /// The menu bar height assumed when it is hidden (full screen, auto-hide).
    public static let fallbackMenuBar: CGFloat = 24

    /// The camera housing's bounding box, or nil on a display without one. The auxiliary areas are the menu bar parts
    /// left and right of the housing; AppKit reports them in global coordinates, some displays relative to the screen,
    /// so both are accepted.
    public static func housing(screen: CGRect, leftArea: CGRect?, rightArea: CGRect?, topInset: CGFloat) -> CGRect? {
        guard var left = leftArea, var right = rightArea, !left.isEmpty, !right.isEmpty, !screen.isEmpty,
              topInset.isFinite, topInset >= 16 else { return nil }
        if abs(left.maxY - screen.maxY) > 0.5, abs(left.maxY - screen.height) <= 0.5 {
            left = left.offsetBy(dx: screen.minX, dy: screen.minY)
            right = right.offsetBy(dx: screen.minX, dy: screen.minY)
        }
        guard abs(left.maxY - screen.maxY) <= 0.5, abs(right.maxY - screen.maxY) <= 0.5,
              left.minX >= screen.minX - 0.5, right.maxX <= screen.maxX + 0.5,
              right.minX - left.maxX >= 40 else { return nil }
        return CGRect(x: left.maxX, y: screen.maxY - topInset, width: right.minX - left.maxX, height: topInset)
    }

    /// The middle of the menu bar on a display without a notch: the pill hangs from it.
    public static func menuBarAnchor(screen: CGRect, visible: CGRect) -> CGRect {
        let bar = screen.maxY - visible.maxY
        let height = bar >= 16 ? bar : fallbackMenuBar
        return CGRect(x: (screen.midX - 15).rounded(), y: screen.maxY - height, width: 30, height: height)
    }

    /// The display the island belongs on: the one under the pointer, where the person works, so a MacBook's notch does
    /// not pull it away from an external display. Without a display under the pointer, `fallback` (the main display).
    public static func screenIndex(frames: [CGRect], pointer: CGPoint, fallback: Int?) -> Int? {
        // The top and right edges count too: a pointer pushed into the menu bar's corner sits on the frame's edge.
        frames.firstIndex { $0.minX <= pointer.x && pointer.x <= $0.maxX && $0.minY <= pointer.y && pointer.y <= $0.maxY }
            ?? fallback
    }

    /// Where the island goes on one display: at its notch when it has one, below the middle of its menu bar otherwise.
    public static func placement(screen: CGRect, visible: CGRect, leftArea: CGRect?, rightArea: CGRect?, topInset: CGFloat) -> IslandPlacement {
        if let housing = housing(screen: screen, leftArea: leftArea, rightArea: rightArea, topInset: topInset) {
            return .notch(housing: housing, screen: screen)
        }
        var visible = visible
        // A hidden menu bar leaves the visible frame at the top of the display: hang below where it would be.
        if screen.maxY - visible.maxY < 16 { visible.size.height = max(0, screen.maxY - fallbackMenuBar - visible.minY) }
        return .menuBar(anchor: menuBarAnchor(screen: screen, visible: visible), visible: visible)
    }

    /// Lower edge a floating pill hangs from: just below the menu bar.
    static func attachY(anchor: CGRect, visible: CGRect) -> CGFloat {
        min(anchor.minY, visible.maxY) - menuBarGap
    }

    /// At rest: inside the camera housing, where black on black is invisible but a pointer or click still finds it;
    /// below the menu bar, a line with no height.
    public static func rest(_ placement: IslandPlacement) -> CGRect {
        switch placement {
        case .notch(let housing, _):
            return CGRect(x: housing.minX + housingInset, y: housing.minY + 2,
                          width: max(0, housing.width - 2 * housingInset), height: max(0, housing.height - 2))
        case .menuBar(let anchor, let visible):
            let width: CGFloat = 60
            return CGRect(x: clampedX(center: anchor.midX, width: width, in: visible), y: attachY(anchor: anchor, visible: visible),
                          width: width, height: 0)
        }
    }

    /// Wings beside the housing: `leading` points left of it, `trailing` right of it. A side without a wing ends inside
    /// the housing. Below the menu bar the two make one pill.
    public static func compact(_ placement: IslandPlacement, leading: CGFloat, trailing: CGFloat) -> CGRect {
        switch placement {
        case .notch(let housing, let screen):
            let left = min(max(0, leading), wingMax, max(0, housing.minX - screen.minX - margin))
            let right = min(max(0, trailing), wingMax, max(0, screen.maxX - margin - housing.maxX))
            let minX = left > 0 ? housing.minX - left : housing.minX + housingInset
            let maxX = right > 0 ? housing.maxX + right : housing.maxX - housingInset
            return CGRect(x: minX, y: housing.minY, width: max(0, maxX - minX), height: housing.height)
        case .menuBar(let anchor, let visible):
            let width = min(max(leading + trailing, capsuleHeight), capsuleMaxWidth, visible.width - 2 * margin)
            let top = attachY(anchor: anchor, visible: visible)
            return CGRect(x: clampedX(center: anchor.midX, width: width, in: visible), y: top - capsuleHeight,
                          width: width, height: capsuleHeight)
        }
    }

    /// The open card, `contentHeight` tall below the housing (or below the menu bar), centred on it.
    public static func open(_ placement: IslandPlacement, contentHeight: CGFloat) -> CGRect {
        switch placement {
        case .notch(let housing, let screen):
            let width = min(openWidth, screen.width - 2 * margin)
            let height = housing.height + min(max(0, contentHeight), max(0, screen.height - housing.height - 2 * margin))
            return CGRect(x: clampedX(center: housing.midX, width: width, in: screen), y: screen.maxY - height,
                          width: width, height: height)
        case .menuBar(let anchor, let visible):
            let width = min(openWidth, visible.width - 2 * margin)
            let top = attachY(anchor: anchor, visible: visible)
            let height = min(max(0, contentHeight), max(0, top - visible.minY - margin))
            return CGRect(x: clampedX(center: anchor.midX, width: width, in: visible), y: top - height,
                          width: width, height: height)
        }
    }

    /// The tallest the card's content may be on this display: what is longer scrolls inside it.
    public static func maxContentHeight(_ placement: IslandPlacement) -> CGFloat {
        switch placement {
        case .notch(let housing, let screen): max(0, screen.height - housing.height - 2 * margin)
        case .menuBar(let anchor, let visible): max(0, attachY(anchor: anchor, visible: visible) - visible.minY - margin)
        }
    }

    private static func clampedX(center: CGFloat, width: CGFloat, in bounds: CGRect) -> CGFloat {
        let low = bounds.minX + margin, high = bounds.maxX - margin - width
        return min(max((center - width / 2).rounded(), low), max(low, high))
    }

    /// The shape between `from` (rest or compact) and `to` (compact or open) at `progress` 0...1. Width leads height
    /// (`IslandChoreography.widthProgress`); the top edge stays where both shapes have it.
    public static func silhouette(_ placement: IslandPlacement, from: CGRect, to: CGRect, progress: CGFloat) -> IslandSilhouette {
        let p = min(max(progress, 0), 1)
        let w = IslandChoreography.widthProgress(p)
        func mix(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }
        let minX = mix(from.minX, to.minX, w), maxX = mix(from.maxX, to.maxX, w)
        let maxY = mix(from.maxY, to.maxY, p), minY = mix(from.minY, to.minY, p)
        let rect = CGRect(x: minX, y: minY, width: max(0, maxX - minX), height: max(0, maxY - minY))
        switch placement {
        case .notch(let housing, _):
            func radius(_ r: CGRect) -> CGFloat { r.height > housing.height + 1 ? cornerRadius : wingRadius }
            // Flares only once the shape reaches past the housing on both sides; inside it they would show.
            let flare = max(0, min(Self.flare, housing.minX - rect.minX, rect.maxX - housing.maxX))
            return IslandSilhouette(rect: rect, radius: mix(radius(from), radius(to), p), flare: flare, hangsFromTop: true)
        case .menuBar:
            return IslandSilhouette(rect: rect, radius: min(cornerRadius, rect.height / 2, rect.width / 2), flare: 0, hangsFromTop: false)
        }
    }

    /// One window large enough for every shape in `rects` (and the flares beside them), in whole points.
    public static func windowFrame(_ placement: IslandPlacement, covering rects: [CGRect]) -> CGRect {
        let union = rects.dropFirst().reduce(rects.first ?? .zero) { $0.union($1) }
        let outset = placement.isNotch ? flare : 0
        let minX = (union.minX - outset).rounded(.down), maxX = (union.maxX + outset).rounded(.up)
        let minY = union.minY.rounded(.down), maxY = union.maxY.rounded(.up)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: max(1, maxY - minY))
    }
}
