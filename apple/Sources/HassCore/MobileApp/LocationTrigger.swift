import Foundation

/// Why a location update was sent. The raw values are the official Home Assistant app's "Last Update Trigger"
/// states (`home-assistant/iOS` `LocationUpdateTrigger`), so automations that read that sensor port unchanged.
public enum LocationTrigger: String, CaseIterable, Sendable {
    /// The app opened.
    case launch = "Launch"
    /// The phone entered a monitored zone.
    case regionEntered = "Geographic Region Entered"
    /// The phone left a monitored zone.
    case regionExited = "Geographic Region Exited"
    /// iOS reported a significant location change (about 500 m).
    case significantLocationChange = "Significant Location Change"
    /// A background app refresh.
    case backgroundFetch = "Background Fetch"
    /// Home Assistant asked for a fix through push (`request_location_update`).
    case pushNotification = "Push Notification"
    /// The person asked for an update in the app.
    case manual = "Manual"

    /// Whether a zone boundary crossing caused the update; such updates are always sent.
    public var isZoneEvent: Bool { self == .regionEntered || self == .regionExited }
}
