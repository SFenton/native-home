import Foundation

/// Tokens returned by `/auth/token`.
public struct AuthTokens: Sendable, Equatable {
    /// Short-lived bearer token; memory only.
    public var accessToken: String
    /// When ``accessToken`` stops working.
    public var expiresAt: Date
    /// Long-lived refresh token; persisted in the Keychain.
    public var refreshToken: String

    /// Creates a token set.
    public init(accessToken: String, expiresAt: Date, refreshToken: String) {
        self.accessToken = accessToken
        self.expiresAt = expiresAt
        self.refreshToken = refreshToken
    }

    /// Whether the access token should be refreshed now.
    /// - Parameters:
    ///   - now: The current time.
    ///   - leeway: Refresh this long before the real expiry.
    public func needsRefresh(now: Date = Date(), leeway: TimeInterval = 60) -> Bool {
        now.addingTimeInterval(leeway) >= expiresAt
    }
}

/// Wire shape of a successful `/auth/token` response.
struct TokenResponse: Decodable {
    var access_token: String
    var expires_in: Double
    var refresh_token: String?
    var token_type: String
}
