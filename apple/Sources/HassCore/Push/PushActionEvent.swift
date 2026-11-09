import Foundation

/// The `fire_event` webhook body for a button press (contract v1, rule 4).
public struct PushActionEvent: Equatable, Sendable {
    /// The pressed button's id.
    public var action: String
    /// The notification's tag.
    public var tag: String?
    /// The typed reply, for text-input buttons only.
    public var replyText: String?

    /// Creates an event.
    public init(action: String, tag: String?, replyText: String? = nil) {
        self.action = action
        self.tag = tag
        self.replyText = replyText
    }

    /// The webhook JSON.
    var webhookBody: [String: Any] {
        var eventData: [String: Any] = ["action": action]
        if let tag { eventData["tag"] = tag }
        if let replyText { eventData["reply_text"] = replyText }
        return [
            "type": "fire_event",
            "data": ["event_type": "mobile_app_notification_action", "event_data": eventData] as [String: Any],
        ]
    }
}
