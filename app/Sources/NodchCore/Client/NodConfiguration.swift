import Foundation

public struct NodConfiguration: Sendable {
    public enum Credential: Sendable {
        case none
        case bearer(String)
        case accessKeyFile(URL)
    }

    public static let defaultURL = URL(string: "http://127.0.0.1:4310")!
    public var baseURL: URL
    public var credential: Credential

    public init(baseURL: URL = Self.defaultURL, credential: Credential = .none) {
        self.baseURL = baseURL
        self.credential = credential
    }

    /// Nod's source server defaults to `.local` relative to its working directory.
    /// Set NOD_DATA_ROOT to that server directory when launching nodch elsewhere.
    public static func fromEnvironment(_ environment: [String: String] = ProcessInfo.processInfo.environment) throws -> Self {
        guard let url = URL(string: environment["NOD_URL"] ?? defaultURL.absoluteString),
              ["http", "https"].contains(url.scheme), url.host != nil,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/" else {
            throw NodClientError.configuration("NOD_URL must be an HTTP or HTTPS server origin.")
        }
        let credential: Credential
        if let token = environment["NOD_AUTH_TOKEN"], !token.isEmpty {
            credential = .bearer(token)
        } else {
            let root = URL(fileURLWithPath: environment["NOD_DATA_ROOT"] ?? ".local", isDirectory: true)
            credential = .accessKeyFile(root.appendingPathComponent("access-key"))
        }
        return Self(baseURL: url, credential: credential)
    }

    public func request(path: String, method: String = "GET") throws -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))))
        request.httpMethod = method
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        switch credential {
        case .none: break
        case .bearer(let token):
            guard !token.isEmpty, !token.contains(where: { $0.isWhitespace }) else {
                throw NodClientError.credentials
            }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        case .accessKeyFile(let file):
            guard let key = try? String(contentsOf: file, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
                  key.count == 43, key.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }) else {
                throw NodClientError.credentials
            }
            let port = baseURL.port ?? (baseURL.scheme == "https" ? 443 : 80)
            request.setValue("nod-access-\(port)=\(key)", forHTTPHeaderField: "Cookie")
        }
        return request
    }

    public func browserURL(path: String) -> URL {
        // A path cannot change the configured origin or invoke another URL scheme.
        let parts = URLComponents(string: path)
        var url = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        let requestedPath = parts?.path ?? "/"
        url.path = requestedPath.hasPrefix("/") ? requestedPath : "/" + requestedPath
        url.query = parts?.query
        url.fragment = parts?.fragment
        return url.url ?? baseURL
    }
}
