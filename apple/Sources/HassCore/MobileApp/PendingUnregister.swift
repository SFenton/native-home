import Foundation

/// A `mobile_app` registration this phone asked Home Assistant to remove at sign-out but could not confirm (offline).
/// Kept with the saved webhooks so it survives a relaunch and is retried (``PendingUnregisterRetrier``). The webhook id
/// is the proof the server accepts without a token, so it is never logged.
public struct PendingUnregister: Codable, Hashable, Sendable {
    /// The server the registration lives on.
    public var server: HassServer
    /// The webhook id of the registration to remove.
    public var webhookID: String

    /// Creates an entry.
    public init(server: HassServer, webhookID: String) {
        self.server = server
        self.webhookID = webhookID
    }
}
