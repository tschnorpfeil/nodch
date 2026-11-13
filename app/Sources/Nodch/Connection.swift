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
            store.answer = nil
        }
        do {
            let resolved = try settings.resolve(environment: environment)
            self.resolved = resolved
            store.state = .offline(reason: "Connecting to \(ConnectionCheck.display(resolved.address))…")
            let session = NodSession(client: NodClient(configuration: resolved.configuration), store: store)
            self.session = session
            session.start()
        } catch {
            resolved = nil
            store.state = .offline(reason: IslandModel.describe(error))
        }
    }
}
