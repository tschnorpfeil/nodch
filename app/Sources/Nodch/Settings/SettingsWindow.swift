import AppKit
import SwiftUI

/// The Settings window. nodch has no menu bar of its own, so the window handles the edit shortcuts (`EditShortcuts`)
/// and ⌘W itself; a token is usually pasted.
final class SettingsWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if EditShortcuts.perform(event, from: self) { return true }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, event.charactersIgnoringModifiers == "w" { performClose(nil); return true }
        return super.performKeyEquivalent(with: event)
    }
}

/// Opens the one Settings window and brings nodch to the front while it is open.
@MainActor final class SettingsWindowController {
    private let model: SettingsModel
    private var window: SettingsWindow?

    init(model: SettingsModel) { self.model = model }

    func show() {
        model.commands.refreshLoginStatus()
        let window = self.window ?? makeWindow()
        self.window = window
        if !window.isVisible { window.center() }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> SettingsWindow {
        let host = NSHostingController(rootView: SettingsView(model: model))
        host.sizingOptions = [.preferredContentSize]
        let window = SettingsWindow(contentViewController: host)
        window.styleMask = [.titled, .closable]
        window.title = "nodch Settings"
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        return window
    }
}
