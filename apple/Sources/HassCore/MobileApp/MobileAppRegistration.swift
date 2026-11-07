import Foundation

/// One `mobile_app` registration: the webhook Home Assistant issued to this phone for one user on one server.
/// Push, location and sensors all send through it (``MobileAppRegistrar``).
public struct MobileAppRegistration: Codable, Equatable, Sendable {
    /// The server registered with.
    public var server: HassServer
    /// The Home Assistant user the registration belongs to.
    public var userID: String
    /// The webhook id; it addresses the registration, so it is kept in the Keychain like a credential.
    public var webhookID: String

    /// Creates a registration.
    public init(server: HassServer, userID: String, webhookID: String) {
        self.server = server
        self.userID = userID
        self.webhookID = webhookID
    }

    /// `POST` target for webhook commands.
    public var webhookURL: URL { webhook.url }

    /// The webhook location and sensor commands go to.
    public var webhook: MobileAppWebhook { MobileAppWebhook(server: server, webhookID: webhookID) }
}
