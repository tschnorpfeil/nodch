import NodchCore

/// Checks for the island: geometry, motion, state presentation, hotkey parsing.
@MainActor enum IslandChecks {
    static func run() async {
        geometry()
        motion()
        presentation()
        hotkey()
    }
}
