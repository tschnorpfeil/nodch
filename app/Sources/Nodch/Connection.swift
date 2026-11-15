import Foundation
import NodchCore

/// The running connection to Nod. It resolves where to connect (NOD_* environment, else nodch Settings, else
/// http://localhost:4310) and holds the session strongly: `IslandStore.actions` is weak. `connect()` again after
/// Settings changed tears the old session down first, so only one ever talks to Nod.
@MainActor final class NodConnection {
    let store: IslandStore
    let settings: ConnectionSettings
    private let environment: [String: String]
    private(set) var session: NodSession?
    private(set) var resolved: ResolvedConnection?

    init(store: IslandStore, settings: ConnectionSettings, environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.store = store
        self.settings = settings
        self.environment = environment
    }

    func connect() {
        if let session {
            session.disconnect()
            if store.actions === session { store.actions = nil }
            self.session = nil
        }
        let previous = resolved?.address
        do {
            let resolved = try settings.resolve(environment: environment)
            // Retry keeps the last answer; another server's answer does not belong here.
            if previous != resolved.address { store.answer = nil }
            self.resolved = resolved
            // The card's title says "Connecting to Nod…" meanwhile; the reason under it is where.
            store.state = .offline(reason: ConnectionCheck.display(resolved.address))
            let session = NodSession(client: NodClient(configuration: resolved.configuration), store: store)
            self.session = session
            session.start()
        } catch {
            resolved = nil
            store.answer = nil
            store.connecting = false
            store.state = .offline(reason: IslandModel.describe(error))
        }
    }
}
