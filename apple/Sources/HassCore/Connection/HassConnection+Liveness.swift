import Foundation
@preconcurrency import HAKit
import HassTelemetry

// MARK: - Waiting for a usable socket

extension HassConnection {
    /// Waits until the socket is connected and authenticated.
    ///
    /// Commands sent while it is not (after the app was suspended, or while HAKit reconnects) can be dropped
    /// silently, so callers that cannot tolerate that wait here first.
    /// - Parameter timeout: How long to wait before giving up.
    /// - Returns: `true` once connected; `false` on timeout, cancellation or a rejected token.
    public func awaitConnected(timeout: Duration = .seconds(10)) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while true {
            switch status {
            case .connected: return true
            case .rejected: return false
            default: break
            }
            guard ContinuousClock.now < deadline, !Task.isCancelled else { return false }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    /// Makes sure the socket really answers, replacing it if it does not.
    ///
    /// After iOS suspends the app its socket can be dead while HAKit still reports it connected (HAKit pings only
    /// once a minute), and a command sent on it is dropped. This waits for a connection, sends a ping, and
    /// reconnects (keeping the subscription, the store and every view as they are) when the ping goes unanswered.
    /// - Parameters:
    ///   - timeout: Total time to spend.
    ///   - pingTimeout: How long the ping may go unanswered before the socket counts as dead.
    /// - Returns: `true` when a live socket is ready for commands.
    public func ensureLive(timeout: Duration = .seconds(12), pingTimeout: Duration = .seconds(3)) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        guard await awaitConnected(timeout: timeout) else { return false }
        if await isAnswering(within: pingTimeout) { return true }
        PushTrace.shared.record("connection: ping unanswered, reconnecting")
        Telemetry.count("connection.pingReconnects")
        reconnect()
        return await awaitConnected(timeout: max(.zero, ContinuousClock.now.duration(to: deadline)))
    }

    /// Whether the server answers a `ping` within a few seconds.
    func isAnswering(within timeout: Duration = .seconds(3)) async -> Bool {
        (try? await sendCommand("ping", data: [:], timeout: timeout)) != nil
    }

    /// Replaces the socket without touching the subscription, the store or any view.
    ///
    /// Disconnects first rather than letting `connect()` swap sockets, as ``refreshRoute()`` does
    /// (`.agents/platforms/apple/connection-lifecycle.md`).
    func reconnect() {
        guard wantsConnection, !isOffline else { return }
        connection.disconnect()
        connection.connect()
        refreshStatus()
    }
}

#if DEBUG
extension HassConnection {
    /// A network blip for the scroll cost probe's reconnect run (`FENTON_SCROLLCOST_RECONNECT=1`): the socket closes as when the
    /// path drops, then reopens `after` later as when it returns, through the same ``setOnline(_:)`` the reachability monitor calls.
    public func debugBlip(after delay: Duration = .seconds(1)) async {
        setOnline(false)
        try? await Task.sleep(for: delay)
        setOnline(true)
    }
}
#endif
