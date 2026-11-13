import Foundation

/// The outcome of one GET /api/state, sorted into what the person can do about it.
public enum ConnectionCheck: Equatable, Sendable {
    case connected
    /// 401: Nod wants a token, or a different one.
    case unauthorized
    /// No token or access key could be read (an env-var setup whose access-key file is missing).
    case missingCredentials
    /// 403 "This host is not permitted": Nod only answers the host of its NOD_PUBLIC_URL.
    case hostNotPermitted
    /// Nothing answers at the address.
    case unreachable
    case other(String)

    public init(error: Error) {
        switch error as? NodClientError {
        case .unauthorized: self = .unauthorized
        case .credentials: self = .missingCredentials
        case .network: self = .unreachable
        case .http(403, let reason) where reason.isEmpty || reason.lowercased().contains("host"): self = .hostNotPermitted
        case .some(let error): self = .other(error.errorDescription ?? "Nod returned an unexpected answer.")
        case nil: self = .other((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// Plain words for the person, naming the address that was tried. No environment variable names.
    public func message(address: URL) -> String {
        let shown = ConnectionCheck.display(address)
        return switch self {
        case .connected: "Connected to Nod at \(shown)."
        case .unauthorized: "Nod rejected the token. Check it in nodch Settings."
        case .missingCredentials: "nodch has no token or access key for Nod at \(shown). Add the token in nodch Settings."
        case .hostNotPermitted:
            "Nod at \(shown) doesn’t accept this host name. Use the host from Nod’s NOD_PUBLIC_URL, for example localhost."
        case .unreachable: "Nothing answers at \(shown). Start Nod, or check the address in nodch Settings."
        case .other(let reason): reason
        }
    }

    /// The address as people type it: without a trailing slash.
    public static func display(_ address: URL) -> String {
        let text = address.absoluteString
        return text.hasSuffix("/") ? String(text.dropLast()) : text
    }

    /// Gives up after 10 seconds, so a wrong address does not leave Settings waiting for a minute.
    public static var testSession: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        return URLSession(configuration: configuration)
    }

    /// One GET /api/state with `configuration`. Nothing else is sent, and nothing is retried.
    public static func run(_ configuration: NodConfiguration, session: URLSession = testSession) async -> ConnectionCheck {
        do {
            _ = try await NodClient(configuration: configuration, session: session).state()
            return .connected
        } catch {
            return ConnectionCheck(error: error)
        }
    }
}
