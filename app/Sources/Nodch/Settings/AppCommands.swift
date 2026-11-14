import AppKit
import Observation
import ServiceManagement
import SwiftUI

/// Start at login, behind a protocol so snapshots show a status without registering anything.
@MainActor protocol LoginItem: AnyObject {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
    func openSystemSettings()
}

/// The real one: nodch itself as a login item (SMAppService.mainApp).
@MainActor final class MainAppLoginItem: LoginItem {
    var status: SMAppService.Status { SMAppService.mainApp.status }
    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
    func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}

/// A login item that only reports a status; for snapshots.
@MainActor final class FixedLoginItem: LoginItem {
    var status: SMAppService.Status
    init(_ status: SMAppService.Status) { self.status = status }
    func register() throws { status = .enabled }
    func unregister() throws { status = .notRegistered }
    func openSystemSettings() {}
}

/// What the island's right-click menu, ⌘, and ⌘Q do: open Settings, start at login, quit.
@MainActor @Observable final class AppCommands {
    /// Bumped after a change, so views read the login item's status again.
    private(set) var loginRevision = 0
    @ObservationIgnored let loginItem: LoginItem?
    @ObservationIgnored var openSettings: () -> Void
    /// Connects to Nod again now, from the offline card's Retry: it only re-reads Nod's state, never resends anything.
    @ObservationIgnored var reconnect: () -> Void = {}

    init(loginItem: LoginItem? = nil, openSettings: @escaping () -> Void = {}) {
        self.loginItem = loginItem
        self.openSettings = openSettings
    }

    var loginStatus: SMAppService.Status {
        _ = loginRevision
        return loginItem?.status ?? .notFound
    }

    /// On, or waiting for the person's approval in System Settings.
    var startsAtLogin: Bool { [.enabled, .requiresApproval].contains(loginStatus) }

    /// Registers or unregisters nodch as a login item, one explicit action. Returns why it failed, if it did.
    @discardableResult
    func setStartsAtLogin(_ on: Bool) -> String? {
        guard let loginItem else { return "Start at login isn’t available here." }
        defer { loginRevision += 1 }
        do {
            if on { try loginItem.register() } else { try loginItem.unregister() }
            return nil
        } catch {
            return (on ? "Couldn’t turn on Start at login: " : "Couldn’t turn off Start at login: ") + error.localizedDescription
        }
    }

    /// Reads the login item's status again: it can change in System Settings while nodch runs.
    func refreshLoginStatus() { loginRevision += 1 }

    func quit() { NSApp.terminate(nil) }
}

/// The island's right-click menu: Settings…, Start at login, Quit nodch.
struct IslandAppMenu: View {
    var commands: AppCommands

    var body: some View {
        Button("Settings…") { commands.openSettings() }
        Toggle("Start at login", isOn: Binding(get: { commands.startsAtLogin }, set: { on in
            // Settings explains a refusal or an approval that macOS still wants.
            if commands.setStartsAtLogin(on) != nil || commands.loginStatus == .requiresApproval { commands.openSettings() }
        }))
        Divider()
        Button("Quit nodch") { commands.quit() }
    }
}
