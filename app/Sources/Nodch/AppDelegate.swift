import AppKit
import NodchCore

/// nodch is an accessory app: no Dock icon, no menu bar of its own, only the island.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store: IslandStore
    private let demo: Bool
    private var controller: IslandController?
    /// Held strongly: the store keeps its actions weakly.
    private var actions: NodActions?
    private var demoScript: DemoScript?

    init(store: IslandStore = IslandStore(), demo: Bool) {
        self.store = store
        self.demo = demo
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if demo {
            let script = DemoScript(store: store)
            demoScript = script
            actions = script.actions
        } else {
            actions = makeNodSession(store: store)
        }
        store.actions = actions
        let controller = IslandController(store: store)
        self.controller = controller
        controller.start()
        demoScript?.start()
    }
}
