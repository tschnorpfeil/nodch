// Adapted from Pippa: app/Sources/Pippa/App/IslandStatus.swift and app/Sources/Pippa/Views/IslandViews.swift
import AppKit
import NodchCore
import SwiftUI

/// Island colours and measures. The island is always dark: black like the camera housing, white type in three steps.
/// No Nod or n8n colours or marks: nodch is unofficial.
enum IslandStyle {
    static let primary = 0.95
    static let secondary = 0.62
    /// Hints and captions: 0.5 on black reads at about 5.3:1, above WCAG's 4.5:1 for small text.
    static let tertiary = 0.5
    /// A control that is off now, e.g. Send with an empty field. Deliberately below `tertiary`.
    static let disabled = 0.3

    static func white(_ opacity: Double) -> Color { Color.white.opacity(opacity) }
    static let accent = Color(red: 0x80 / 255, green: 0xB8 / 255, blue: 0xFF / 255)
    static let ok = Color(red: 0x45 / 255, green: 0xD9 / 255, blue: 0x7F / 255)
    static let bad = Color(red: 0xFF / 255, green: 0x8E / 255, blue: 0x8E / 255)
    static let warn = Color(red: 0xFF / 255, green: 0xC8 / 255, blue: 0x5C / 255)
    /// The one primary button's fill: white text on it reads at 4.5:1.
    static let accentFill = Color(red: 0x1F / 255, green: 0x6F / 255, blue: 0xE0 / 255)

    // Type: SF Pro Rounded. The wing's line is `IslandMetrics.lineFont`, 12 semibold with tabular digits.
    static let title = Font.system(size: 14, weight: .semibold, design: .rounded)
    static let body = Font.system(size: 13, design: .rounded)
    static let detail = Font.system(size: 13, weight: .medium, design: .rounded)
    static let small = Font.system(size: 12, design: .rounded)
    static let caption = Font.system(size: 11, weight: .medium, design: .rounded)
    static let line = Font(IslandMetrics.lineFont as CTFont)

    // Motion: critically damped like the island's own springs (`IslandSpring`), so nothing overshoots.
    static let arrive = Animation.spring(response: 0.32, dampingFraction: 1)
    static let fade = Animation.easeOut(duration: 0.2)

    /// Between the card's edges and everything in it.
    static let padding: CGFloat = 16
    /// Between blocks.
    static let gap: CGFloat = 12
    static let buttonGap: CGFloat = 8
    static let wellRadius: CGFloat = 12
    static let controlHeight: CGFloat = 28
    /// At the notch, between the menu bar row and the card's content.
    static let notchTop: CGFloat = 4
    /// The longest a field value or the body may be before it scrolls inside the card.
    static let bodyMaxHeight: CGFloat = 220

    static func tint(_ tone: IslandTone) -> Color {
        switch tone {
        case .done: ok
        case .failed: bad
        case .needsYou: accent
        case .offline: white(tertiary)
        case .rest, .working: white(secondary)
        }
    }

    /// A small sign so the state never depends on colour alone.
    static func symbol(_ tone: IslandTone) -> String? {
        switch tone {
        case .needsYou: "hand.raised.fill"
        case .done: "checkmark"
        case .failed: "exclamationmark.triangle.fill"
        case .offline: "bolt.horizontal.circle"
        case .rest, .working: nil
        }
    }
}

/// Measures of the compact wing. The same font measures and draws the line, so the measured width is the drawn one.
enum IslandMetrics {
    nonisolated(unsafe) static let lineFont: NSFont = {
        let base = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let rounded = base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor
        let tabular = rounded.addingAttributes([.featureSettings: [[NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
                                                                     .selectorIdentifier: kMonospacedNumbersSelector]]])
        return NSFont(descriptor: tabular, size: 12) ?? base
    }()
    nonisolated(unsafe) static let hintFont: NSFont = {
        let base = NSFont.systemFont(ofSize: 11, weight: .medium)
        return NSFont(descriptor: base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor, size: 11) ?? base
    }()

    /// From the outer edge to the glyph.
    static let inset: CGFloat = 12
    static let glyph: CGFloat = 14
    static let glyphGap: CGFloat = 7
    /// Between the wing's content and the housing (half the gap in the middle of the pill).
    static let inner: CGFloat = 10
    static let pillInner: CGFloat = 5
    static let stop: CGFloat = 20
    static let chevron: CGFloat = 12

    static func width(_ text: String, font: NSFont = lineFont) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    /// The widest the elapsed time is at this magnitude ("0:00", "00:00", "0:00:00"): tabular digits all measure alike.
    static func elapsedWidth(_ seconds: TimeInterval) -> CGFloat {
        width(IslandPresentation.elapsed(seconds).replacingOccurrences(of: #"\d"#, with: "0", options: .regularExpression))
    }

    /// Widths of the leading and trailing part of the wing, before the geometry clamps them.
    static func wing(_ wing: IslandWing, line: String, elapsed: TimeInterval?, hint: String, notch: Bool) -> (leading: CGFloat, trailing: CGFloat) {
        let inner = notch ? Self.inner : pillInner
        var leading: CGFloat = 0
        if wing.showsGlyph || wing.showsLine {
            leading = inset + (wing.showsGlyph ? glyph : 0)
            if wing.showsLine, !line.isEmpty { leading += (wing.showsGlyph ? glyphGap : 0) + width(line) }
            leading += inner
        }
        var parts: [CGFloat] = []
        if wing.showsElapsed, let elapsed { parts.append(elapsedWidth(elapsed)) }
        if wing.showsStop { parts.append(stop) }
        if wing.more > 0 { parts.append(width("+\(wing.more)") + 12) }
        if wing.showsChevron { parts.append(chevron) }
        if wing.showsHint { parts.append(width(hint, font: hintFont)) }
        let trailing = parts.isEmpty ? 0 : inner + parts.reduce(0, +) + 6 * CGFloat(parts.count - 1) + (notch ? inset - 2 : inset - 4)
        // Under the menu bar the pill is one shape: an empty side still needs its inset.
        if !notch, trailing == 0, leading > 0 { return (leading + inset - inner, 0) }
        return (leading, trailing)
    }
}
