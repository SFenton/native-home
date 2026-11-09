import HassDesign
import SwiftUI

/// The words the notification permission prompts use (HIG Notifications: say what the alerts are for before the
/// system alert). Owner decision 2026-10-23, `.agents/design/mockups/proposals/widgets-push-siri-watch`.
enum NotificationPermissionCopy {
    static let title = "Get door and camera alerts"
    static let message = "S+H can tell you when a door is left open or someone rings."
    static let turnOn = "Turn On Notifications"
    static let notNow = "Not Now"
    /// The Setup flow's step is a pre-alert screen (HIG Privacy): one button, titled Continue, then the iOS alert.
    static let stepAction = "Continue"
    static let stepFootnote = "Next, iOS asks to send notifications. Choose Allow."
}
