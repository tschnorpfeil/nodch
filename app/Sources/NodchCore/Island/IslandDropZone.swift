import CoreGraphics

/// Files being dragged toward the island. `near`: a file drag is close to the top of the island's display, so the
/// island shows where to drop; `over`: the pointer is on the island and a drop would land.
public enum IslandDropZone: Equatable, Sendable {
    case none, near, over

    /// How far below the top of the display a drag counts as heading for the island.
    public static let reach: CGFloat = 160

    /// The pointer is near the top of the display the island is on (not of a neighbour whose top lines up with it).
    public static func isNear(pointer: CGPoint, placement: IslandPlacement, screens: [CGRect]) -> Bool {
        let island: CGPoint
        switch placement {
        case .notch(let housing, _): island = CGPoint(x: housing.midX, y: housing.midY)
        case .menuBar(let anchor, _): island = CGPoint(x: anchor.midX, y: anchor.midY)
        }
        guard let screen = screens.first(where: { $0.contains(pointer) }) else { return false }
        return screen.contains(island) && pointer.y >= screen.maxY - reach
    }
}
