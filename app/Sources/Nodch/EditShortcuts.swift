import AppKit

/// nodch has no menu bar of its own, so nothing turns ⌘X, ⌘C, ⌘V, ⌘A, ⌘Z and ⇧⌘Z into edit actions. Its windows
/// (the island's prompt, Settings) send them to the text field themselves.
enum EditShortcuts {
    static func action(for event: NSEvent) -> Selector? {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        return switch (flags, event.charactersIgnoringModifiers?.lowercased()) {
        case (.command, "x"): #selector(NSText.cut(_:))
        case (.command, "c"): #selector(NSText.copy(_:))
        case (.command, "v"): #selector(NSText.paste(_:))
        case (.command, "a"): #selector(NSText.selectAll(_:))
        case (.command, "z"): Selector(("undo:"))
        case ([.command, .shift], "z"): Selector(("redo:"))
        default: nil
        }
    }

    /// Sends the shortcut's edit action along the responder chain; false when it is no edit shortcut or nothing took it.
    @MainActor static func perform(_ event: NSEvent, from sender: Any?) -> Bool {
        guard let action = action(for: event) else { return false }
        return NSApp.sendAction(action, to: nil, from: sender)
    }
}
