import AppKit
import Foundation
import Network
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
    private var policy = ReconnectPolicy()
    private var wakeObserver: NSObjectProtocol?
    private var pathMonitor: NWPathMonitor?
    private var networkSatisfied: Bool?

    init(store: IslandStore, settings: ConnectionSettings, environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.store = store
        self.settings = settings
        self.environment = environment
    }

    /// Starts the event stream again after the Mac wakes and when the network comes back while offline, instead of
    /// waiting for the backoff. Only reconnects; nothing the person sent or approved is repeated.
    func watchSystem() {
        guard wakeObserver == nil else { return }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                // The network needs a moment after waking.
                try? await Task.sleep(for: .seconds(1.5))
                self?.reconnect(for: .wake)
            }
        }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            Task { @MainActor in
                guard let self else { return }
                let returned = ReconnectPolicy.networkReturned(wasSatisfied: self.networkSatisfied, isSatisfied: satisfied)
                self.networkSatisfied = satisfied
                if returned { self.reconnect(for: .networkReturned) }
            }
        }
        monitor.start(queue: .main)
        pathMonitor = monitor
    }

    private func reconnect(for trigger: ReconnectPolicy.Trigger) {
        var offline = false
        if case .offline = store.state { offline = true }
        if policy.shouldReconnect(trigger, offline: offline) { connect() }
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
