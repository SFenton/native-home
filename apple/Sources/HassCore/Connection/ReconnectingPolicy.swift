import Foundation

/// When the quiet reconnecting sign shows (owner, 2026-10-17; `.agents/platforms/apple/connection-lifecycle.md`). The sign is a
/// white arc spinner left of Quick Links (``ReconnectingIndicator``; owner, 2026-10-23, replacing the "Reconnecting…" chip).
///
/// A socket that is down for a moment (a Wi-Fi to cellular hand-off, the app coming back from the background) is not worth
/// mentioning: the arc waits until the connection has been down for ``delay``, and fades out as soon as it is live again. The
/// values on screen stay either way; the arc is the only sign.
public enum ReconnectingPolicy {
    /// How long the connection must have been down before the arc shows.
    public static let delay: Duration = .seconds(2)

    /// How long the arc takes to fade in or out; the UI's fade (`MotionTokens.crossFadeDuration`) is this long too.
    public static let fade: Duration = .milliseconds(350)

    /// How long the arc sits in the header, unlit, before it fades up: the bar needs a turn to place a new item, and an item
    /// that is inserted already lit would pop rather than fade.
    public static let insertLead: Duration = .milliseconds(50)

    /// Whether `status` is a connection that is not live and is not being refused: starting, waiting to retry, or closed.
    /// A refused token ends the session instead (the sign-in screen), so it never shows the arc.
    public static func isDown(_ status: HassConnection.Status) -> Bool {
        switch status {
        case .connected, .rejected: false
        case .disconnected, .connecting, .waitingToReconnect: true
        }
    }

    /// Whether the connection is retrying: it is down but a network path exists. With no path the app is offline, which is
    /// its own state (``HassConnection/isOffline``, shown by the offline chip) and never a retry, so it never shows the arc.
    public static func showsReconnecting(_ status: HassConnection.Status, isOffline: Bool) -> Bool {
        !isOffline && isDown(status)
    }

    /// Whether the header arc shows: the connection is retrying (``showsReconnecting(_:isOffline:)``), or nothing has been
    /// heard from Home Assistant yet (``EntityStore/hasReceivedFirstState`` is false: a first sign-in with no snapshot) and a
    /// refused token is not ending the session. Offline stays the offline chip's business.
    public static func showsArc(_ status: HassConnection.Status, isOffline: Bool, hasReceivedFirstState: Bool) -> Bool {
        guard !isOffline, status != .rejected else { return false }
        return isDown(status) || !hasReceivedFirstState
    }
}
