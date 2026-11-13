import Foundation
import NodchCore

/// Connection settings: precedence, where the token goes, error words and the first-run decision. Dictionaries stand in
/// for the Keychain and for UserDefaults (a real suite would leave a plist in ~/Library/Preferences); nothing reaches
/// a real Nod.
@MainActor enum SettingsChecks {
    final class FakeTokens: TokenStore {
        var items: [String: String] = [:]
        func token(account: String) -> String? { items[account] }
        func setToken(_ token: String, account: String) throws { items[account] = token }
        func removeToken(account: String) throws { items[account] = nil }
    }

    /// Records every key written, as UserDefaults would hold it.
    final class FakeDefaults: SettingsDefaults {
        var values: [String: Any] = [:]
        func string(forKey key: String) -> String? { values[key] as? String }
        func set(_ value: Any?, forKey key: String) { values[key] = value }
    }

    static func run() async {
        do {
            try precedenceChecks(defaults: FakeDefaults())
            normalizeChecks()
            firstRunChecks()
            try await errorChecks()
        } catch { check(false, "settings checks: \(error)") }
    }

    static func precedenceChecks(defaults: FakeDefaults) throws {
        let tokens = FakeTokens()
        let settings = ConnectionSettings(defaults: defaults, tokens: tokens)
        let fresh = try settings.resolve(environment: [:])
        if case .none = fresh.configuration.credential {
            check(fresh.source == .defaults && fresh.address.absoluteString == "http://localhost:4310",
                  "settings: nothing set or saved resolves to http://localhost:4310 without a token")
        } else { check(false, "settings: default has no token") }
        check(try settings.resolve(environment: ["NOD_URL": ""]).source == .defaults, "settings: an empty env var does not count")

        let secret = "nodch-check-secret-\(UUID().uuidString)"
        let saved = try settings.save(server: " HTTPS://Nod.Example.com/ ", token: .replace(secret))
        check(saved.absoluteString == "https://nod.example.com", "settings: saved address is a normalized origin")
        let resolved = try settings.resolve(environment: [:])
        let request = try resolved.configuration.request(path: "/api/state")
        check(resolved.source == .saved && resolved.address.host == "nod.example.com"
              && request.value(forHTTPHeaderField: "Authorization") == "Bearer \(secret)",
              "settings: saved address and Keychain token win over the default")

        let fromEnvironment = try settings.resolve(environment: ["NOD_URL": "http://localhost:5432", "NOD_AUTH_TOKEN": "env-token"])
        let envRequest = try fromEnvironment.configuration.request(path: "/api/state")
        check(fromEnvironment.source == .environment && fromEnvironment.address.port == 5432
              && envRequest.value(forHTTPHeaderField: "Authorization") == "Bearer env-token",
              "settings: environment wins over saved settings")
        let dataRoot = try settings.resolve(environment: ["NOD_DATA_ROOT": "/unavailable"])
        if case .accessKeyFile = dataRoot.configuration.credential {
            check(dataRoot.source == .environment && dataRoot.address.host != "nod.example.com",
                  "settings: NOD_DATA_ROOT alone also selects the environment")
        } else { check(false, "settings: NOD_DATA_ROOT alone selects the environment") }
        check(ConnectionSettings.environmentInEffect(["NOD_URL": "x", "NOD_DATA_ROOT": "", "HOME": "/"]) == ["NOD_URL"],
              "settings: names only the NOD_* variables that are set")

        // The token is only in the token store, under the origin; defaults hold the address and nothing else.
        check(Set(defaults.values.keys) == [ConnectionSettings.serverKey], "settings: defaults hold only \(ConnectionSettings.serverKey)")
        check(!defaults.values.values.contains { "\($0)".contains(secret) }, "settings: the token never reaches UserDefaults")
        check(tokens.items == ["https://nod.example.com:443": secret], "settings: token stored under the normalized origin")

        try settings.save(server: "https://nod.example.com", token: .keep)
        check(tokens.items.count == 1, "settings: saving without a new token keeps the stored one")
        do { try settings.save(server: "http://localhost:4310", token: .replace("two words")); check(false, "settings: token with a space") }
        catch { check(settings.savedServer?.host == "nod.example.com" && tokens.items.count == 1, "settings: a bad token writes nothing") }
        do { try settings.save(server: "ftp://nod.example.com", token: .replace("other")); check(false, "settings: bad address") }
        catch { check(tokens.items.values.allSatisfy { $0 == secret }, "settings: a bad address writes nothing") }
        try settings.save(server: "https://nod.example.com", token: .remove)
        let removed = try settings.resolve(environment: [:])
        if case .none = removed.configuration.credential {
            check(tokens.items.isEmpty && removed.source == .saved, "settings: Remove deletes the token and keeps the address")
        } else { check(false, "settings: Remove deletes the token") }
    }

    static func normalizeChecks() {
        check((try? ConnectionSettings.normalize("localhost:4310"))?.absoluteString == "http://localhost:4310",
              "settings: an address without a scheme reads as http")
        check((try? ConnectionSettings.normalize(""))?.absoluteString == "http://localhost:4310", "settings: an empty address is the default")
        for bad in ["file:///etc/passwd", "http://localhost:4310/api", "http://user:pw@localhost:4310", "http://localhost:4310?x=1"] {
            check((try? ConnectionSettings.normalize(bad)) == nil, "settings: \(bad) is refused")
        }
        check(ConnectionSettings.origin(URL(string: "http://LOCALHOST")!) == "http://localhost:80", "settings: origin spells out the port")
    }

    static func firstRunChecks() {
        check(ConnectionSettings.opensSettingsAtLaunch(source: .defaults, check: .unreachable), "first run: nothing answers opens Settings")
        check(ConnectionSettings.opensSettingsAtLaunch(source: .defaults, check: .unauthorized), "first run: 401 opens Settings")
        check(!ConnectionSettings.opensSettingsAtLaunch(source: .defaults, check: .connected), "first run: a Nod that answers needs no Settings")
        check(!ConnectionSettings.opensSettingsAtLaunch(source: .saved, check: .unreachable), "first run: saved settings never open Settings by themselves")
        check(!ConnectionSettings.opensSettingsAtLaunch(source: .environment, check: .unauthorized), "first run: env var setups never open Settings")
    }

    static func errorChecks() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ClientStub.self]
        let transport = URLSession(configuration: configuration)
        defer { transport.invalidateAndCancel() }
        let address = ConnectionSettings.defaultURL
        let nod = NodConfiguration(baseURL: address, credential: .bearer("wrong"))

        ClientStub.configure { _ in .init(status: 401) }
        let rejected = await ConnectionCheck.run(nod, session: transport)
        check(rejected == .unauthorized && rejected.message(address: address) == "Nod rejected the token. Check it in nodch Settings.",
              "errors: 401 reads as a rejected token")
        check(ClientStub.requests.count == 1 && ClientStub.requests.first?.url?.path == "/api/state"
              && ClientStub.requests.first?.httpMethod == "GET", "errors: Test connection sends one GET /api/state")

        ClientStub.configure { _ in .init(status: 403, body: Data("{\"error\":\"This host is not permitted\"}".utf8)) }
        let host = await ConnectionCheck.run(NodConfiguration(baseURL: URL(string: "http://127.0.0.1:4310")!), session: transport)
        let hostText = host.message(address: URL(string: "http://127.0.0.1:4310")!)
        check(host == .hostNotPermitted && hostText.contains("NOD_PUBLIC_URL") && hostText.contains("localhost")
              && hostText.contains("http://127.0.0.1:4310"), "errors: 403 host not permitted says to use the host from NOD_PUBLIC_URL")
        ClientStub.configure { _ in .init(status: 403, mime: "text/plain", body: Data("This host is not permitted".utf8)) }
        check(await ConnectionCheck.run(nod, session: transport) == .hostNotPermitted, "errors: a plain-text 403 is host not permitted too")

        ClientStub.configure { _ in .init(error: URLError(.cannotConnectToHost)) }
        let away = await ConnectionCheck.run(nod, session: transport)
        check(away == .unreachable && away.message(address: address).hasPrefix("Nothing answers at http://localhost:4310."),
              "errors: unreachable names the address")

        let state = ClientChecks.fixture()
        ClientStub.configure { _ in .init(body: state) }
        check(await ConnectionCheck.run(nod, session: transport) == .connected, "errors: a valid state answer is Connected")

        let descriptions = [NodClientError.credentials, .unauthorized, .network("x")].compactMap(\.errorDescription)
            + [ConnectionCheck.unauthorized, .missingCredentials, .unreachable, .hostNotPermitted].map { $0.message(address: address) }
        check(!descriptions.contains { $0.contains("NOD_AUTH_TOKEN") || $0.contains("NOD_DATA_ROOT") || $0.contains("NOD_URL") },
              "errors: what the person reads names no nodch env var")

        // The live session's offline card names the address it tried.
        ClientStub.configure { _ in .init(error: URLError(.cannotConnectToHost)) }
        let session = NodSession(client: NodClient(configuration: nod, session: transport))
        _ = try? await session.refresh()
        if case .offline(let reason) = session.store.state {
            check(reason.contains("Nothing answers at http://localhost:4310"), "errors: offline card names the address")
        } else { check(false, "errors: unreachable session is offline") }
    }
}
