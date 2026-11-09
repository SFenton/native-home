import Foundation

/// A silent command a background push carries (contract v1, rule 3).
public enum PushCommand: Equatable, Sendable {
    /// The name Home Assistant's `notify` message uses to ask the phone for its location.
    public static let requestLocationUpdateName = "request_location_update"

    /// Remove delivered notifications with this tag.
    case clearNotification(tag: String)
    /// Home Assistant asked for a location update (`message: request_location_update`): take a fix and send it with
    /// the Push Notification trigger (`.agents/platforms/apple/location.md`).
    case requestLocationUpdate
    /// A command this version ignores (`update_widgets`, `clear_badge`, ...).
    case unsupported(String)
}
