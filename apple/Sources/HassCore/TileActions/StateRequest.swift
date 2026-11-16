import Foundation

/// The request phase of a ``StateStyle``: client timings and the words shown while a call is sent
/// (`.agents/design/state-styles.md`, Request phase).
public struct StateRequest: Equatable, Sendable {
    /// What happens when ``settleTimeout`` ends without the state arriving.
    public enum OnTimeout: String, Equatable, Sendable, CaseIterable {
        /// The tile shows the error look.
        case error
        /// The tile shows the live state again.
        case revert
    }

    /// Taps are ignored this long after one, and until Home Assistant acknowledges the call.
    public var lockout: Duration
    /// The call fails when it is not acknowledged within this.
    public var ackTimeout: Duration
    /// The request fails when the state has not moved within this.
    public var settleTimeout: Duration
    /// How long the error look is held.
    public var errorHold: Duration
    /// What a timeout does.
    public var onTimeout: OnTimeout
    /// The state text while a call is being sent, by service: `open_cover` reads "Sending Open…".
    public var pendingWords: [String: String]
    /// The state the entity is shown in once a call is on its way, by service, until Home Assistant's own state arrives:
    /// `open_cover` shows `opening`. Feedback only, never authored (the library shape carries none), so a built-in style names it.
    public var pendingStates: [String: String]
    /// The state text of a failed request: "Error", "Didn't Respond".
    public var errorWords: String
    /// The Home Assistant script an authored lifecycle reads (`script.*`); nil when the style has none. The app does not run it.
    public var script: String?
    /// The error timer that goes with ``script`` (`timer.*`).
    public var errorTimer: String?

    /// Creates the settings.
    public init(lockout: Duration, ackTimeout: Duration, settleTimeout: Duration, errorHold: Duration, onTimeout: OnTimeout = .error,
                pendingWords: [String: String] = [:], pendingStates: [String: String] = [:], errorWords: String = "Error",
                script: String? = nil, errorTimer: String? = nil) {
        self.lockout = lockout
        self.ackTimeout = ackTimeout
        self.settleTimeout = settleTimeout
        self.errorHold = errorHold
        self.onTimeout = onTimeout
        self.pendingWords = pendingWords
        self.pendingStates = pendingStates
        self.errorWords = errorWords
        self.script = script
        self.errorTimer = errorTimer
    }
}
