import NodchCore

/// Connects `store` to the Nod named by NOD_URL (with NOD_AUTH_TOKEN or NOD_DATA_ROOT/access-key) and returns the
/// session. The caller holds it strongly: `IslandStore.actions` is weak.
@MainActor
func makeNodSession(store: IslandStore) -> NodActions? {
    do {
        let session = NodSession(client: NodClient(configuration: try NodConfiguration.fromEnvironment()), store: store)
        session.start()
        return session
    } catch {
        store.state = .offline(reason: error.localizedDescription)
        return nil
    }
}
