import Foundation

/// The words on the Setup flow's Time Sensitive step and the Settings rows that report the same switch
/// (owner decisions 2026-10-27; `.agents/design/mockups/proposals/setup-flow-time-sensitive`). The two states follow
/// ``TimeSensitiveSetting``: the switch is on, or the person turned it off.
struct TimeSensitiveCopy: Equatable {
    /// What the primary button does.
    enum Action: Equatable {
        /// Got It: the step is seen and the next one, if any, swaps in.
        case acknowledge
        /// Open Settings: the app's notification page in iOS Settings.
        case openSettings
    }

    var title: String
    var message: String
    /// The status row's value: "On" or "Off".
    var status: String
    var footnote: String
    var action: Action
    var actionTitle: String
    /// The secondary text button's title; nil when On.
    var secondaryTitle: String?

    /// The step's copy.
    /// - Parameter isOn: Whether Time Sensitive Notifications is on for S+H.
    init(isOn: Bool) {
        if isOn {
            title = "Let Urgent Alerts Through"
            message = "S+H marks urgent door and camera alerts Time Sensitive, so they reach you through Focus and Do Not Disturb."
            status = "On"
            footnote = "Already on. Nothing to change."
            action = .acknowledge
            actionTitle = "Got It"
            secondaryTitle = nil
        } else {
            title = "Urgent Alerts Are Held Back"
            message = "Time Sensitive Notifications are off for S+H, so a door left open waits until your Focus ends."
            status = "Off"
            footnote = "Turn on Time Sensitive Notifications, then come back."
            action = .openSettings
            actionTitle = "Open Settings"
            secondaryTitle = "Not Now"
        }
    }

    /// The status row's label.
    static let statusLabel = "Time Sensitive Notifications"

    /// The three points, the same in both states.
    static let points = [
        SetupPoint(symbol: SetupPoint.bullet, title: "Only urgent door and camera alerts", key: "urgent"),
        SetupPoint(symbol: SetupPoint.bullet, title: "Everything else still waits for Focus to end", key: "focus"),
        SetupPoint(symbol: SetupPoint.bullet, title: "Change it any time in Settings, Notifications, S+H", key: "settings"),
    ]

    // MARK: - Settings rows

    /// The Settings → Notifications row for the permission itself, once notifications are allowed.
    static let notificationsRowStatus = "On. Door and camera alerts reach you."

    /// The Settings → Notifications row for the switch.
    /// - Parameter isOn: Whether Time Sensitive Notifications is on.
    static func rowStatus(isOn: Bool) -> String {
        isOn ? "On. Urgent alerts can break through a Focus." : "Off. Urgent alerts wait until your Focus ends."
    }
}
