import Foundation
import HassCore
import Observation

/// What the person did with a notification.
public enum NotificationResponse: Equatable, Sendable {
    /// Tapped the notification.
    case open
    /// Dismissed it.
    case dismiss
    /// Pressed a button, with the typed reply for a text-input button.
    case action(String, replyText: String?)
}
