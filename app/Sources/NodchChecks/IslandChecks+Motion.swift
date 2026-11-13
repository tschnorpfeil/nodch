import Foundation
import NodchCore

extension IslandChecks {
    static func motion() {
        // Opening settles without overshoot, monotonic, within half a second.
        var spring = IslandSpring()
        spring.retarget(1, IslandSpring.opening)
        var previous = spring.value, monotonic = true, inBounds = true, time = 0.0
        while !spring.isSettled && time < 2 {
            spring.advance(by: 1.0 / 120)
            time += 1.0 / 120
            if spring.value < previous { monotonic = false }
            if spring.value > 1 || spring.value < 0 { inBounds = false }
            previous = spring.value
        }
        check(spring.isSettled && spring.value == 1, "motion: opening settles on its target")
        check(time < 0.6, "motion: opening settles within 0.6 s (took \(String(format: "%.2f", time)) s)")
        check(monotonic && inBounds, "motion: no overshoot, never out of bounds")

        // Closing is quicker than opening.
        var closing = IslandSpring(value: 1)
        closing.retarget(0, IslandSpring.closing)
        var closeTime = 0.0
        while !closing.isSettled && closeTime < 2 { closing.advance(by: 1.0 / 120); closeTime += 1.0 / 120 }
        check(closing.value == 0 && closeTime < time, "motion: closing settles faster than opening")

        // A reversal mid-flight continues from where the shape is.
        var reversal = IslandSpring()
        reversal.retarget(1, IslandSpring.opening)
        for _ in 0..<12 { reversal.advance(by: 1.0 / 120) }
        let mid = reversal.value
        reversal.retarget(0, IslandSpring.closing)
        reversal.advance(by: 1.0 / 240)
        check(mid > 0.05 && mid < 0.95 && abs(reversal.value - mid) < 0.05, "motion: a reversal keeps the value instead of jumping")

        // A stalled frame does not jump.
        var stalled = IslandSpring()
        stalled.retarget(1, IslandSpring.opening)
        stalled.advance(by: 2)
        check(stalled.value < 0.9, "motion: a stalled frame slows the motion down instead of skipping it")

        // Reduce Motion jumps.
        var reduced = IslandSpring()
        reduced.move(to: 1, IslandSpring.opening, reduceMotion: true)
        check(reduced.isSettled && reduced.value == 1, "motion: Reduce Motion snaps to the target")

        // Height springs in points stay in their bounds.
        var height = IslandSpring(value: 180, bounds: 0...10_000, tolerance: 0.25)
        height.retarget(420, IslandSpring.opening)
        for _ in 0..<240 { height.advance(by: 1.0 / 120) }
        check(height.isSettled && height.value == 420, "motion: the card's height settles on its new size")

        // Choreography: the black is there before the content fades in; width leads height.
        check(IslandChoreography.contentAlpha(0) == 0 && IslandChoreography.contentAlpha(1) == 1, "motion: content fades from 0 to 1")
        check(IslandChoreography.backgroundAlpha(0.55) == 1 && IslandChoreography.contentAlpha(0.55) == 0,
              "motion: the background is complete before the content starts")
        check(IslandChoreography.widthProgress(0.5) > 0.5 && IslandChoreography.widthProgress(0.8) == 1, "motion: width leads height")
        check(IslandChoreography.contentDrop(1) == 0 && IslandChoreography.contentDrop(0) > 0, "motion: content settles into place")
    }
}
