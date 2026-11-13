import NodchCore

// MARK: - Integration point

/// INTEGRATOR: replace this function. It connects `store` to a running Nod (HTTP API and SSE from NodchCore/Client),
/// keeps `store.state` current, and returns the actions the island calls. The app holds the returned object strongly
/// (`IslandStore.actions` is weak). Until the client lands it returns nil: the island stays offline and every action
/// says that nodch is not connected yet.
@MainActor
func makeNodSession(store: IslandStore) -> NodActions? {
    nil
}
