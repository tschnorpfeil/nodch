import Foundation

/// Where "Open Nod" (and ⌘↩) goes. The Nod desktop app keeps its own server setting, so it may not show the Nod
/// nodch talks to; the browser opens the exact address nodch uses.
public enum OpenTarget: String, CaseIterable, Sendable {
    case automatic, app, browser

    public static let defaultsKey = "nodch.openNodIn"

    /// The saved choice; anything unknown or missing is Automatic.
    public static func saved(_ defaults: SettingsDefaults) -> OpenTarget {
        defaults.string(forKey: defaultsKey).flatMap(OpenTarget.init(rawValue:)) ?? .automatic
    }

    public static func save(_ target: OpenTarget, defaults: SettingsDefaults) {
        defaults.set(target == .automatic ? nil : target.rawValue, forKey: defaultsKey)
    }

    /// Automatic: the Nod app only for a Nod on this Mac (localhost, 127.0.0.1, ::1); the browser otherwise.
    public func usesApp(address: URL, appInstalled: Bool) -> Bool {
        switch self {
        case .app: appInstalled
        case .browser: false
        case .automatic: appInstalled && Self.isLoopback(address)
        }
    }

    public static func isLoopback(_ address: URL) -> Bool {
        guard let host = address.host?.lowercased() else { return false }
        return ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host)
    }

    /// How an "Open Nod" goes out.
    public enum Plan: Equatable, Sendable {
        /// This address in the default browser.
        case browser(URL)
        /// The Nod app; the browser address if it cannot be launched.
        case app(fallback: URL)
    }

    /// `path` nil: a plain "Open Nod", as this choice says. A path (the page for what the card shows) is a link into the
    /// server nodch uses, so it always opens in the browser at that address: the Nod app may have another server
    /// set. The path cannot leave the configured origin (`browserURL`).
    public func plan(path: String?, configuration: NodConfiguration, appInstalled: Bool) -> Plan {
        let address = configuration.baseURL
        guard let path else {
            let home = configuration.browserURL(path: "/")
            return usesApp(address: address, appInstalled: appInstalled) ? .app(fallback: home) : .browser(home)
        }
        return .browser(configuration.browserURL(path: path))
    }

    public var title: String {
        switch self {
        case .automatic: "Automatic"
        case .app: "Nod app"
        case .browser: "Browser"
        }
    }
}
