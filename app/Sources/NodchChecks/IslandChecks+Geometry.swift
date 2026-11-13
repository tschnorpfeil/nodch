import CoreGraphics
import NodchCore

extension IslandChecks {
    /// A 14" MacBook Pro: 1512 × 982 pt, a 32 pt menu bar beside a 202 pt wide housing.
    static let laptop = CGRect(x: 0, y: 0, width: 1512, height: 982)
    static let laptopLeft = CGRect(x: 0, y: 950, width: 655, height: 32)
    static let laptopRight = CGRect(x: 857, y: 950, width: 655, height: 32)
    /// An external 2560 × 1440 display left of it, without a notch, with a 24 pt menu bar.
    static let external = CGRect(x: -2560, y: 0, width: 2560, height: 1440)
    static let externalVisible = CGRect(x: -2560, y: 0, width: 2560, height: 1416)

    static func geometry() {
        // Which display: the one under the pointer (laptop with notch on the left, external display on the right).
        let laptop = CGRect(x: 0, y: 0, width: 1512, height: 982), monitor = CGRect(x: 1512, y: 0, width: 2560, height: 1440)
        check(IslandGeometry.screenIndex(frames: [laptop, monitor], pointer: CGPoint(x: 2400, y: 700), fallback: 0) == 1,
              "geometry: the island goes to the display under the pointer, not to the notch elsewhere")
        check(IslandGeometry.screenIndex(frames: [laptop, monitor], pointer: CGPoint(x: 700, y: 982), fallback: 1) == 0,
              "geometry: a pointer on the top edge (in the menu bar) still counts")
        check(IslandGeometry.screenIndex(frames: [laptop, monitor], pointer: CGPoint(x: -50, y: 50), fallback: 1) == 1
              && IslandGeometry.screenIndex(frames: [], pointer: .zero, fallback: nil) == nil,
              "geometry: without a display under the pointer the main display is used")
        // Notch detection.
        let housing = IslandGeometry.housing(screen: laptop, leftArea: laptopLeft, rightArea: laptopRight, topInset: 32)
        check(housing == CGRect(x: 655, y: 950, width: 202, height: 32), "geometry: housing from the auxiliary areas")
        let moved = laptop.offsetBy(dx: 2560, dy: 300)
        let relative = IslandGeometry.housing(screen: moved, leftArea: laptopLeft, rightArea: laptopRight, topInset: 32)
        check(relative == CGRect(x: 655 + 2560, y: 950 + 300, width: 202, height: 32), "geometry: screen-relative auxiliary areas are accepted")
        check(IslandGeometry.housing(screen: external, leftArea: nil, rightArea: nil, topInset: 0) == nil, "geometry: no notch without auxiliary areas")
        check(IslandGeometry.housing(screen: laptop, leftArea: laptopLeft, rightArea: laptopRight, topInset: 0) == nil,
              "geometry: no notch without a top safe area")
        check(IslandGeometry.housing(screen: laptop, leftArea: laptopLeft, rightArea: CGRect(x: 670, y: 950, width: 842, height: 32), topInset: 32) == nil,
              "geometry: a gap narrower than a camera is no notch")

        let notch = IslandGeometry.placement(screen: laptop, visible: CGRect(x: 0, y: 0, width: 1512, height: 950),
                                             leftArea: laptopLeft, rightArea: laptopRight, topInset: 32)
        check(notch.isNotch, "geometry: a notched display places at the notch")
        let pill = IslandGeometry.placement(screen: external, visible: externalVisible, leftArea: nil, rightArea: nil, topInset: 0)
        check(!pill.isNotch, "geometry: a display without a notch places the pill")

        // Rest hides inside the housing; under the menu bar it has no height.
        guard let housing, case .notch = notch else { return }
        let rest = IslandGeometry.rest(notch)
        check(housing.contains(rest) && rest.width > 0, "geometry: rest at the notch lies inside the housing")
        check(IslandGeometry.rest(pill).height == 0, "geometry: rest below the menu bar has no height")

        // Wings.
        let wing = IslandGeometry.compact(notch, leading: 120, trailing: 60)
        check(wing.minX == housing.minX - 120 && wing.maxX == housing.maxX + 60 && wing.height == housing.height && wing.maxY == laptop.maxY,
              "geometry: wings reach left and right of the housing, as tall as it")
        let oneSided = IslandGeometry.compact(notch, leading: 80, trailing: 0)
        check(oneSided.maxX < housing.maxX && oneSided.maxX > housing.midX, "geometry: a side without a wing ends inside the housing")
        check(IslandGeometry.compact(notch, leading: 900, trailing: 0).minX == housing.minX - IslandGeometry.wingMax,
              "geometry: a wing never grows past its maximum")
        let narrow = CGRect(x: 0, y: 0, width: 400, height: 900)
        let narrowNotch = IslandPlacement.notch(housing: CGRect(x: 100, y: 868, width: 200, height: 32), screen: narrow)
        check(IslandGeometry.compact(narrowNotch, leading: 200, trailing: 200).minX >= narrow.minX + IslandGeometry.margin
              && IslandGeometry.compact(narrowNotch, leading: 200, trailing: 200).maxX <= narrow.maxX - IslandGeometry.margin,
              "geometry: wings stay inside the display's margins")

        // The pill hangs centred below the menu bar.
        let capsule = IslandGeometry.compact(pill, leading: 150, trailing: 80)
        check(abs(capsule.midX - external.midX) <= 1, "geometry: the pill is centred on the display")
        check(capsule.maxY == externalVisible.maxY - IslandGeometry.menuBarGap && capsule.height == IslandGeometry.capsuleHeight,
              "geometry: the pill hangs just below the menu bar")
        check(capsule.width == 230, "geometry: the pill is as wide as its two parts")
        let hiddenBar = IslandGeometry.placement(screen: external, visible: external, leftArea: nil, rightArea: nil, topInset: 0)
        check(IslandGeometry.compact(hiddenBar, leading: 100, trailing: 0).maxY == external.maxY - IslandGeometry.fallbackMenuBar - IslandGeometry.menuBarGap,
              "geometry: with a hidden menu bar the pill hangs where the bar would be")

        // Open card.
        let open = IslandGeometry.open(notch, contentHeight: 200)
        check(open.width == IslandGeometry.openWidth && abs(open.midX - housing.midX) <= 0.5 && open.maxY == laptop.maxY
              && open.height == 232, "geometry: the open card hangs centred from the housing, the row beside it included")
        check(IslandGeometry.open(notch, contentHeight: 5000).minY >= laptop.minY + IslandGeometry.margin, "geometry: a tall card stays on the display")
        let openPill = IslandGeometry.open(pill, contentHeight: 300)
        check(externalVisible.contains(openPill) && openPill.maxY == externalVisible.maxY - IslandGeometry.menuBarGap,
              "geometry: the open pill card stays below the menu bar")

        // Silhouette and window.
        let start = IslandGeometry.silhouette(notch, from: rest, to: open, progress: 0)
        let end = IslandGeometry.silhouette(notch, from: rest, to: open, progress: 1)
        check(start.rect == rest && end.rect == open, "geometry: the silhouette runs from one shape to the other")
        check(start.flare == 0 && end.flare == IslandGeometry.flare, "geometry: flares only once the shape reaches past the housing")
        check(end.contains(CGPoint(x: open.midX, y: open.midY)) && !end.contains(CGPoint(x: open.minX - 3, y: open.maxY - 1)),
              "geometry: the hit area is the shape, flares excluded")
        let frame = IslandGeometry.windowFrame(notch, covering: [CGRect(x: 10.3, y: 20.7, width: 100.2, height: 30.1)])
        check(frame.minX == frame.minX.rounded() && frame.width == frame.width.rounded() && frame.minX <= 10.3 - IslandGeometry.flare,
              "geometry: windows sit on whole points and leave room for the flares")

        // Other notch heights and widths (13" Air, 16" Pro): every shape follows the housing.
        for (width, height) in [(CGFloat(180), CGFloat(32)), (204, 37), (196, 38)] {
            let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)
            let h = CGRect(x: (screen.width - width) / 2, y: screen.maxY - height, width: width, height: height)
            let p = IslandPlacement.notch(housing: h, screen: screen)
            let c = IslandGeometry.compact(p, leading: 100, trailing: 40)
            let o = IslandGeometry.open(p, contentHeight: 120)
            check(c.height == height && c.maxY == screen.maxY && o.height == height + 120 && h.contains(IslandGeometry.rest(p)),
                  "geometry: \(Int(width))×\(Int(height)) pt housing")
        }
    }
}
