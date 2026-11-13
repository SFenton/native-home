import Foundation

/// The two push tokens this install last held, kept so a `mobile_app` sync never drops one Home Assistant already has.
///
/// The tokens belong to the app install, not to a user: they survive sign-out and a different user's sign-in. Each is
/// lowercase hex. They live next to the registrations in the ``MobileAppRegistrationStore``
/// (`.agents/platforms/apple/mobile-app.md`).
public struct DeviceTokens: Codable, Equatable, Sendable {
    /// The last APNs device token the system issued; nil on a fresh install.
    public var push: String?
    /// The last push-to-start token for the Home activity the system issued; nil on a fresh install or before the
    /// first time Live Activities were on.
    public var startActivity: String?

    /// Creates the tokens.
    public init(push: String? = nil, startActivity: String? = nil) {
        self.push = push
        self.startActivity = startActivity
    }
}
