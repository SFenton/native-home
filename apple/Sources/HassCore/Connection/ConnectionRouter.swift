import Foundation

/// Decides where the websocket connects and when: the reconnect policy as a pure value.
///
/// No HAKit, no tasks, no clocks: every event is one mutating method that returns the ``Action``s to perform, and
/// `HassConnection` is the adapter that feeds it events and runs them. It is the single place the policy lives
/// (`.agents/platforms/apple/connection-lifecycle.md`).
///
/// ## Rules (owner, 2026-10-27: no churn on a network change; the socket dropping reconnects. Refined 2026-10-28: a home socket cannot survive leaving home)
///
/// | Event | Result |
/// |---|---|
/// | ``networkChanged()``, socket on the public URL | `.forgetHome`, `.checkRoute`; no reconnect (no churn on cellular or public Wi-Fi). The home address is forgotten so a later connect on another network never sends the token to whatever answers at the old home address |
/// | ``networkChanged()``, socket on a home address | `.forgetHome`, `.reconnect(to: public)`, `.checkRoute`: a home socket is dead the moment the phone leaves the house (Wi-Fi to cellular keeps the path satisfied, so nothing else would notice for a minute or two), so it moves to the public URL now and the check finds home again if it is still reachable |
/// | ``connectRequested()`` | `.connect` when the URL would not change; otherwise a working socket is left alone (a pending switch stays pending) and a socket that is not ready reconnects on the right URL. Never a URL change in place |
/// | ``socketBecameReady()`` after a failover to public | `.checkRoute`, once per failover |
/// | ``homeFound(url:)``, socket already on that URL | nothing |
/// | ``homeFound(url:)``, socket not ready | `.reconnect(to: home)` at once (no reason to wait out HAKit's backoff) |
/// | ``homeFound(url:)``, public socket ready | `.scheduleSwitchCheck`; ``tick(idle:)`` reconnects once nothing has scrolled for ``quietPeriod``, else reschedules, re-checking everything each time |
/// | ``socketFailed()`` while on a non-public URL | `.forgetHome`, `.reconnect(to: public)` once; a second failure does nothing (the recorded URL is public) |
/// | Public socket working, home found | never moved on purpose while the home socket works; only a drop moves it to public |
///
/// A future make-before-break "warm up, then swap" plugs in here: `.reconnect` becomes `.warmUp` plus `.swap`.
public struct ConnectionRouter: Sendable, Equatable {
    // MARK: - Types

    /// What the adapter must do.
    public enum Action: Equatable, Sendable {
        /// Drop the home address (`LocalServerRoute.reset()`).
        case forgetHome
        /// Look for the home address again, in the background.
        case checkRoute
        /// Replace the socket so it opens on this URL.
        case reconnect(to: URL)
        /// Call ``ConnectionRouter/tick(idle:)`` after this long.
        case scheduleSwitchCheck(after: Duration)
        /// Drop a scheduled switch check.
        case cancelSwitch
        /// Call HAKit's `connect()`: it opens the socket on, or keeps it at, the URL the router expects.
        case connect
    }

    // MARK: - State

    /// The server's public URL.
    public let publicURL: URL
    /// How long nothing may have scrolled before a working public socket moves home.
    public var quietPeriod: Duration = .seconds(1)

    private(set) var socketURL: URL?
    private(set) var isReady = false
    private(set) var wants = false
    private(set) var isOffline = false
    private(set) var homeURL: URL?
    private(set) var hasPendingSwitch = false
    /// A home socket failed over to the public URL and home has not been checked since.
    private(set) var needsRecheck = false

    public init(publicURL: URL) { self.publicURL = publicURL }

    // MARK: - Inputs

    /// The app wants the socket open, or not.
    public mutating func wantsConnection(_ wants: Bool) -> [Action] {
        self.wants = wants
        return wants ? [] : dropPendingSwitch()
    }

    /// The network path is up or down.
    public mutating func online(_ online: Bool) -> [Action] {
        isOffline = !online
        return online ? [] : dropPendingSwitch()
    }

    /// The URL the current socket was opened with (the connection-info record).
    public mutating func socketOpened(url: URL?) { socketURL = url }

    /// The route's current home address, nil when it is not using one.
    public mutating func routeIs(_ url: URL?) { homeURL = url }

    /// The socket is ready for commands.
    public mutating func socketReady() { isReady = true }

    /// The socket is closed or still connecting (not failed: see ``socketFailed()``).
    public mutating func socketNotReady() { isReady = false }

    /// A new network. A socket on a home address is replaced by one on the public URL at once (it cannot work any
    /// more, and nothing else would notice for a minute or two); a public socket stays.
    public mutating func networkChanged() -> [Action] {
        homeURL = nil
        var actions = dropPendingSwitch() + [.forgetHome]
        if wants, !isOffline, let url = socketURL, url != publicURL {
            actions += reconnect(to: publicURL)
        }
        return actions + [.checkRoute]
    }

    /// The app asks to connect (foreground, a retry button). HAKit swaps a live socket for a new URL in place and the
    /// old socket keeps its delegate, so the URL never changes under an open socket: a working socket is left as it
    /// is (a pending switch stays pending), and one that is not ready reconnects on the right URL the safe way.
    public mutating func connectRequested() -> [Action] {
        guard wants, !isOffline else { return [] }
        let target = homeURL ?? publicURL
        guard let current = socketURL, current != target else { return [.connect] }
        return isReady ? [] : reconnect(to: target)
    }

    /// The socket became ready. After a failover from a home address, home is checked once.
    public mutating func socketBecameReady() -> [Action] {
        isReady = true
        guard needsRecheck, socketURL == publicURL else { return [] }
        needsRecheck = false
        return [.checkRoute]
    }

    /// The route check found home Assistant at `url`.
    public mutating func homeFound(url: URL) -> [Action] {
        homeURL = url
        guard canSwitch(to: url) else { return [] }
        guard isReady else { return reconnect(to: url) }
        hasPendingSwitch = true
        return [.scheduleSwitchCheck(after: .zero)]
    }

    /// The deferred switch is due; `idle` is how long nothing has scrolled.
    public mutating func tick(idle: Duration) -> [Action] {
        guard hasPendingSwitch else { return [] }
        guard let url = homeURL, isReady, canSwitch(to: url) else {
            hasPendingSwitch = false
            return []
        }
        guard idle >= quietPeriod else { return [.scheduleSwitchCheck(after: quietPeriod - idle)] }
        return reconnect(to: url)
    }

    /// The socket failed and HAKit is waiting to retry. A socket on the home address goes to the public URL now, once.
    public mutating func socketFailed() -> [Action] {
        isReady = false
        guard wants, !isOffline, let url = socketURL, url != publicURL else { return [] }
        homeURL = nil
        needsRecheck = true
        return dropPendingSwitch() + [.forgetHome] + reconnect(to: publicURL)
    }

    // MARK: - Private

    private func canSwitch(to url: URL) -> Bool { wants && !isOffline && socketURL != url }

    private mutating func reconnect(to url: URL) -> [Action] {
        hasPendingSwitch = false
        socketURL = url
        isReady = false
        return [.reconnect(to: url)]
    }

    private mutating func dropPendingSwitch() -> [Action] {
        guard hasPendingSwitch else { return [] }
        hasPendingSwitch = false
        return [.cancelSwitch]
    }
}
