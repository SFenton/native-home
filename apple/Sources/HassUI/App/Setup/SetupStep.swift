import Foundation

/// One step of the after-sign-in Setup flow, in the order the sheet shows them
/// (`.agents/platforms/apple/push.md`, `.agents/platforms/apple/location.md`; owner, 2026-10-27).
public enum SetupStep: String, CaseIterable, Sendable, Comparable {
    /// Explains door and camera alerts, then shows the iOS notification alert.
    case notifications
    /// Explains that urgent alerts break through a Focus and reports the switch. There is no alert for it.
    case timeSensitive
    /// Explains arrivals and departures, then walks the location alerts.
    case location

    /// The sheet's navigation bar title while this step is on screen (owner, 2026-10-27): the bar names the step, not
    /// the flow. Every stage of the Location step keeps "Location Settings".
    public var barTitle: String {
        switch self {
        case .notifications: "Notification Settings"
        case .timeSensitive: "Time Sensitive Notification Settings"
        case .location: "Location Settings"
        }
    }

    public static func < (lhs: SetupStep, rhs: SetupStep) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}
