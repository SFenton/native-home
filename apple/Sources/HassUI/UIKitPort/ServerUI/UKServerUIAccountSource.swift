#if os(iOS)
import HassCore

// MARK: - Private account provider

/// Session-owned data, never encoded in a composition or sent to Studio.
@MainActor
enum UKServerUIAccountValue {
    case loading
    case unavailable
    case ready(name: String?, server: String, avatar: AvatarBox?)
}

/// The bootstrap host supplies an observable account snapshot. Cached values remain ready during reconnect.
@MainActor
protocol UKServerUIAccountProvider: AnyObject {
    var account: UKServerUIAccountValue { get }
}

/// Bridges existing session-owned values without exposing credentials or introducing a state channel.
@MainActor
final class UKServerUIAccountAdapter: UKServerUIAccountProvider {
    private let read: @MainActor () -> UKServerUIAccountValue

    init(read: @escaping @MainActor () -> UKServerUIAccountValue) { self.read = read }
    var account: UKServerUIAccountValue { read() }
}
#endif
