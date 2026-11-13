import NodchCore

/// Checks for the island: geometry, motion, state presentation, hotkey parsing, the quick prompt.
@MainActor enum IslandChecks {
    static func run() async {
        geometry()
        motion()
        presentation()
        hotkey()
        prompt()
    }
}
