import Foundation

/// Where nodch keeps the Nod token: the Keychain in the app, a dictionary in checks. Accounts are normalized origins
/// (`ConnectionSettings.origin`), so a token never follows an address it was not saved for.
@MainActor public protocol TokenStore: AnyObject {
    func token(account: String) -> String?
    func setToken(_ token: String, account: String) throws
    func removeToken(account: String) throws
}

/// Where the address is kept: `UserDefaults` in the app, a dictionary in checks and snapshots.
public protocol SettingsDefaults: AnyObject {
    func string(forKey key: String) -> String?
    func set(_ value: Any?, forKey key: String)
}

extension UserDefaults: SettingsDefaults {}

/// What a connection was resolved from, in order of precedence.
public enum ConnectionSource: Equatable, Sendable {
    /// NOD_URL, NOD_AUTH_TOKEN or NOD_DATA_ROOT is set: the environment decides, settings are ignored.
    case environment
    /// The address saved in nodch Settings, with its Keychain token if there is one.
    case saved
    /// Nothing set or saved: `ConnectionSettings.defaultURL` without a token.
    case defaults
}

public struct ResolvedConnection: Sendable {
    public var configuration: NodConfiguration
    public var source: ConnectionSource
    public var address: URL { configuration.baseURL }
}

/// The token field on save: leave the stored token as it is, replace it, or remove it.
public enum TokenChange: Equatable, Sendable {
    case keep
    case replace(String)
    case remove
}

/// Connection settings stored per user. The address lives in UserDefaults; the token only ever in `TokenStore`.
@MainActor public struct ConnectionSettings {
    nonisolated public static let serverKey = "nodch.serverURL"
    nonisolated public static let defaultURL = URL(string: "http://localhost:4310")!
    nonisolated public static let environmentKeys = ["NOD_URL", "NOD_AUTH_TOKEN", "NOD_DATA_ROOT"]

    public let defaults: SettingsDefaults
    public let tokens: TokenStore

    public init(defaults: SettingsDefaults = UserDefaults.standard, tokens: TokenStore) {
        self.defaults = defaults
        self.tokens = tokens
    }

    /// The NOD_* variables that are set (and not empty), in a fixed order.
    nonisolated public static func environmentInEffect(_ environment: [String: String]) -> [String] {
        environmentKeys.filter { !(environment[$0] ?? "").isEmpty }
    }

    /// Environment first (an existing LaunchAgent keeps working), then saved settings, then the default address.
    public func resolve(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> ResolvedConnection {
        if !Self.environmentInEffect(environment).isEmpty {
            return ResolvedConnection(configuration: try NodConfiguration.fromEnvironment(environment), source: .environment)
        }
        let saved = savedServer
        let url = saved ?? Self.defaultURL
        let credential: NodConfiguration.Credential = token(for: url).map { .bearer($0) } ?? .none
        return ResolvedConnection(configuration: NodConfiguration(baseURL: url, credential: credential),
                                  source: saved == nil ? .defaults : .saved)
    }

    /// The saved address, nil when none is saved or the saved text is no longer valid.
    public var savedServer: URL? {
        defaults.string(forKey: Self.serverKey).flatMap { try? Self.normalize($0) }
    }

    public var hasSavedSettings: Bool { savedServer != nil }

    public func token(for server: URL) -> String? {
        tokens.token(account: Self.origin(server)).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Stores `server` (empty text means the default address) and applies `token` to that address's Keychain item.
    /// Validates everything before writing anything. Returns the normalized address.
    @discardableResult
    public func save(server text: String, token: TokenChange) throws -> URL {
        let server = try Self.normalize(text)
        let account = Self.origin(server)
        if case .replace(let value) = token {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.contains(where: { $0.isWhitespace }) else {
                throw NodClientError.invalidInput("A token is one word without spaces. Paste it again.")
            }
            try tokens.setToken(trimmed, account: account)
        } else if token == .remove {
            try tokens.removeToken(account: account)
        }
        defaults.set(server.absoluteString, forKey: Self.serverKey)
        return server
    }

    /// An HTTP(S) origin from what the person typed: "localhost:4310" reads as http://localhost:4310, a trailing slash
    /// is dropped, and anything with a path, query, user or password is refused.
    nonisolated public static func normalize(_ text: String) throws -> URL {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return defaultURL }
        if !value.contains("://") { value = "http://" + value }
        guard var parts = URLComponents(string: value), let scheme = parts.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil, parts.query == nil,
              parts.fragment == nil, parts.path.isEmpty || parts.path == "/" else {
            throw NodClientError.configuration("Enter Nod’s address, for example http://localhost:4310.")
        }
        parts.scheme = scheme
        parts.host = host.lowercased()
        parts.path = ""
        guard let url = parts.url else {
            throw NodClientError.configuration("Enter Nod’s address, for example http://localhost:4310.")
        }
        return url
    }

    /// The Keychain account for a server: scheme, host and explicit port, e.g. "http://localhost:4310".
    nonisolated public static func origin(_ url: URL) -> String {
        let scheme = url.scheme?.lowercased() ?? "http"
        let port = url.port ?? (scheme == "https" ? 443 : 80)
        return "\(scheme)://\((url.host ?? "").lowercased()):\(port)"
    }

    /// First run: nothing in the environment, nothing saved, and the default address does not answer or wants a token.
    nonisolated public static func opensSettingsAtLaunch(source: ConnectionSource, check: ConnectionCheck) -> Bool {
        guard source == .defaults else { return false }
        switch check {
        case .unreachable, .unauthorized, .missingCredentials: return true
        case .connected, .hostNotPermitted, .other: return false
        }
    }
}
