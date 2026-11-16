import Foundation

/// When nodch starts its connection again by itself: after the Mac wakes, and when the network comes back while
/// offline. At most once per `debounce`. Reconnecting only opens the event stream and reads state again; it never
/// sends, approves or repeats anything the person did.
public struct ReconnectPolicy: Sendable {
    public enum Trigger: Sendable, Equatable {
        case wake
        case networkReturned
    }

    public let debounce: TimeInterval
    private var lastReconnect: Date?

    public init(debounce: TimeInterval = 2) { self.debounce = debounce }

    /// `offline`: the island shows Offline right now. Asking for a yes counts as the reconnect.
    public mutating func shouldReconnect(_ trigger: Trigger, offline: Bool, now: Date = Date()) -> Bool {
        if trigger == .networkReturned && !offline { return false }
        if let lastReconnect, now.timeIntervalSince(lastReconnect) < debounce { return false }
        lastReconnect = now
        return true
    }

    /// The network path went from unsatisfied to satisfied. The first report (nothing before it) is not a return.
    public static func networkReturned(wasSatisfied: Bool?, isSatisfied: Bool) -> Bool {
        wasSatisfied == false && isSatisfied
    }
}
