import Foundation

/// Where `mobile_app` webhook commands go: the server and the webhook id Home Assistant issued when this phone
/// registered (`.agents/platforms/apple/location.md`).
///
/// The webhook id addresses the registration, so it is a credential: it is read from the registration store when a
/// command is sent and never logged.
public struct MobileAppWebhook: Equatable, Sendable {
    /// The server the phone registered with.
    public var server: HassServer
    /// The webhook id from the registration response.
    public var webhookID: String

    /// Creates a webhook target.
    public init(server: HassServer, webhookID: String) {
        self.server = server
        self.webhookID = webhookID
    }

    /// `POST` target for webhook commands.
    public var url: URL { server.url("/api/webhook/\(webhookID)") }
}

/// Supplies the current registration's webhook, or nil when this phone is not registered (signed out, or the
/// registration has not run yet).
///
/// The app's source is the registration store (``MobileAppRegistrationStore``), kept by ``MobileAppRegistrar``.
public protocol MobileAppWebhookSource: Sendable {
    /// The webhook to send to now, or nil.
    func currentWebhook() async -> MobileAppWebhook?
}

/// A webhook that never changes, for tests and the debug gallery.
public struct FixedMobileAppWebhookSource: MobileAppWebhookSource {
    private let webhook: MobileAppWebhook?

    /// Creates a source that always answers `webhook`.
    public init(_ webhook: MobileAppWebhook?) { self.webhook = webhook }

    public func currentWebhook() async -> MobileAppWebhook? { webhook }
}

/// Why a `mobile_app` webhook command failed.
public enum MobileAppWebhookError: Error, Equatable, Sendable {
    /// No registration to send to: signed out, or not registered yet.
    case notRegistered
    /// Home Assistant deleted the registration (the webhook answers 410); register again.
    case registrationGone
    /// Any other HTTP status.
    case status(Int)
    /// The body was not what the `mobile_app` API promises.
    case unexpectedResponse
    /// The request never completed.
    case network
}
