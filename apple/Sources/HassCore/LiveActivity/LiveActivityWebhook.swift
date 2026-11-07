import FentonActivityModel
import Foundation

/// The webhook commands the Live Activity feature sends to Home Assistant's `mobile_app` registration
/// (`.agents/platforms/apple/live-activities-per-job.md` §7; core `mobile_app/live_activity/webhook.py`).
public protocol LiveActivityWebhookSending: Sendable {
    /// `live_activity_token`: the activity's update token, which `mobile_app` stores per `tag` until `expiresAt`.
    func reportToken(tag: String, token: String, expiresAt: Date) async throws
    /// `live_activity_dismissed`: the activity ended on the device; `mobile_app` drops its token.
    func reportDismissed(tag: String) async throws
    /// `fire_event`: a press or a dismissal, for the `fenton_home` engine and the owner's automations.
    func fireEvent(_ type: String, data: [String: String]) async throws
}

/// Event types the app fires (`live-activities-per-job.md` §7). Home Assistant stamps each with the registration's user.
public enum LiveActivityEventType {
    /// A card's button: `{tag, job, control}`; `job` is the tag without its `job.` prefix.
    public static let action = "fenton_live_activity_action"
    /// The person swiped the activity away: `{tag}`.
    public static let dismissed = "fenton_live_activity_dismissed"
}

/// ``LiveActivityWebhookSending`` over the registration webhook (``MobileAppWebhookClient``).
public struct MobileAppLiveActivityWebhook: LiveActivityWebhookSending {
    private let client: MobileAppWebhookClient

    /// Creates the sender.
    /// - Parameter client: The webhook client on the signed-in registration's source.
    public init(client: MobileAppWebhookClient) {
        self.client = client
    }

    public func reportToken(tag: String, token: String, expiresAt: Date) async throws {
        try await client.send(command: "live_activity_token", data: [
            "tag": tag, "push_token": token, "expires_at": expiresAt.timeIntervalSince1970,
        ])
    }

    public func reportDismissed(tag: String) async throws {
        try await client.send(command: "live_activity_dismissed", data: ["tag": tag])
    }

    public func fireEvent(_ type: String, data: [String: String]) async throws {
        try await client.send(command: "fire_event", data: ["event_type": type, "event_data": data])
    }
}
