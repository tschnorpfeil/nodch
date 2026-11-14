import AppKit
import NodchCore

/// nodch is an accessory app: no Dock icon, no menu bar of its own, only the island. Settings, Start at login and Quit
/// are in the island's right-click menu, and ⌘, and ⌘Q work while the island or Settings has the keyboard.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store: IslandStore
    private let demo: Bool
    private var controller: IslandController?
    /// Held strongly: the store keeps its actions weakly.
    private var actions: NodActions?
    private var demoScript: DemoScript?
    private var connection: NodConnection?
    private let commands = AppCommands(loginItem: MainAppLoginItem())
    private var settingsWindow: SettingsWindowController?
    private var keyMonitor: Any?

    init(store: IslandStore = IslandStore(), demo: Bool) {
        self.store = store
        self.demo = demo
    }

    /// Back from System Settings, Start at login may have been approved or turned off there.
    func applicationDidBecomeActive(_ notification: Notification) {
        commands.refreshLoginStatus()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        PromiseDrops.clearAll()
        let settings = ConnectionSettings(tokens: KeychainTokenStore())
        if demo {
            let script = DemoScript(store: store)
            demoScript = script
            actions = script.actions
            store.actions = actions
        } else {
            let connection = NodConnection(store: store, settings: settings)
            self.connection = connection
            connection.connect()
        }
        let model = SettingsModel(settings: settings, commands: commands)
        // In the demo nothing reconnects: it never talks to Nod.
        model.onSaved = { [weak self] in self?.connection?.connect() }
        let settingsWindow = SettingsWindowController(model: model)
        self.settingsWindow = settingsWindow
        commands.openSettings = { [weak settingsWindow] in settingsWindow?.show() }
        commands.reconnect = { [weak self] in self?.connection?.connect() }
        installKeyMonitor()

        let controller = IslandController(store: store)
        controller.model.commands = commands
        self.controller = controller
        controller.start()
        demoScript?.start()
        if let resolved = connection?.resolved, resolved.source == .defaults { openSettingsOnFirstRun(resolved) }
    }

    /// First run: nothing set or saved, and nothing answers at the default address (or it wants a token). One GET.
    private func openSettingsOnFirstRun(_ resolved: ResolvedConnection) {
        Task { [weak self] in
            let check = await ConnectionCheck.run(resolved.configuration)
            guard ConnectionSettings.opensSettingsAtLaunch(source: resolved.source, check: check) else { return }
            self?.settingsWindow?.show()
        }
    }

    /// ⌘, opens Settings and ⌘Q quits while the island's card or Settings is the key window.
    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                  let window = event.window, window.isKeyWindow, window is IslandPanel || window is SettingsWindow else { return event }
            switch event.charactersIgnoringModifiers {
            case ",": MainActor.assumeIsolated { self?.commands.openSettings() }; return nil
            case "q": MainActor.assumeIsolated { self?.commands.quit() }; return nil
            default: return event
            }
        }
    }
}
