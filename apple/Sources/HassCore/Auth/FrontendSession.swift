import Foundation

/// Hands the app's sign-in to Home Assistant's own web frontend, so the settings web view opens
/// signed in instead of showing the web login page.
///
/// The frontend keeps its session in `localStorage["hassTokens"]` and refreshes it with the same
/// `client_id` that issued the refresh token, so the app's ``HassServer/clientID`` is passed along.
/// The web view uses a non-persistent data store, so these tokens never reach disk.
public struct FrontendSession: Equatable, Sendable {
    /// The server the frontend runs on.
    public var server: HassServer
    /// Current tokens.
    public var tokens: AuthTokens

    /// Creates a session hand-off.
    public init(server: HassServer, tokens: AuthTokens) {
        self.server = server
        self.tokens = tokens
    }

    /// The server origin, e.g. `https://homeassistant.example.com` (no trailing slash).
    public var origin: String {
        var value = server.baseURL.absoluteString
        while value.hasSuffix("/") { value.removeLast() }
        return value
    }

    /// The `hassTokens` value in the shape the frontend stores itself.
    /// - Parameter now: Current time, for `expires_in`.
    public func tokensJSON(now: Date = Date()) throws -> String {
        let expiresIn = max(0, tokens.expiresAt.timeIntervalSince(now))
        // `.distantFuture` (long-lived debug tokens) would overflow JavaScript's safe integers.
        let expiresMillis = min(tokens.expiresAt.timeIntervalSince1970, 253_402_300_799) * 1000
        let payload = Payload(
            access_token: tokens.accessToken,
            refresh_token: tokens.refreshToken,
            token_type: "Bearer",
            expires_in: Int(min(expiresIn, 31_536_000)),
            expires: Int64(expiresMillis),
            hassUrl: origin,
            clientId: HassServer.clientID
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(payload), as: UTF8.self)
    }

    /// JavaScript that stores the tokens before the frontend boots, only on the server's own origin.
    /// - Parameter now: Current time, for `expires_in`.
    public func bootstrapScript(now: Date = Date()) throws -> String {
        let tokens = try tokensJSON(now: now)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        let origin = try String(decoding: encoder.encode(origin), as: UTF8.self)
        return """
        (function () {
          if (window.location.origin !== \(origin)) { return; }
          try { window.localStorage.setItem("hassTokens", JSON.stringify(\(tokens))); } catch (error) {}
        })();
        """
    }

    /// Whether a navigation stays inside the web view (same origin as the server) rather than opening
    /// in the system browser.
    public func isInternal(_ url: URL) -> Bool {
        if url.scheme == "about" { return true }
        return url.scheme == server.baseURL.scheme
            && url.host()?.lowercased() == server.baseURL.host()?.lowercased()
            && url.port == server.baseURL.port
    }

    private struct Payload: Encodable {
        var access_token: String
        var refresh_token: String
        var token_type: String
        var expires_in: Int
        var expires: Int64
        var hassUrl: String
        var clientId: String
    }
}
