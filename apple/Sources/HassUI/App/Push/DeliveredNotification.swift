import Foundation
import HassCore
import Observation

/// A notification the system shows now, as the coordinator needs it.
public struct DeliveredNotification: Sendable {
    /// `UNNotificationRequest.identifier`.
    public var identifier: String
    /// The notification's `fenton` tag, if any.
    public var tag: String?

    /// Creates a delivered notification.
    public init(identifier: String, tag: String?) {
        self.identifier = identifier
        self.tag = tag
    }
}
