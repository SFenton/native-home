import Foundation

/// The Home Assistant server the app talks to, plus the OAuth client identity it presents.
public struct HassServer: Codable, Hashable, Sendable {
    /// Base URL, e.g. `https://homeassistant.example.com`.
    public var baseURL: URL

    /// Creates a server value.
    /// - Parameter baseURL: The server origin. Any path, query or trailing slash is dropped.
    public init(baseURL: URL) {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) ?? URLComponents()
        components.path = ""
        components.query = nil
        components.fragment = nil
        self.baseURL = components.url ?? baseURL
    }

    /// The server this build ships with (Info.plist `HASS_DEFAULT_SERVER`, fed from a build setting), or nil when the
    /// build names none. It is only a starting point for the sign-in Server field: a signed-in install restores its
    /// server from the Keychain session, never from here.
    /// - Parameter info: The Info.plist values; tests pass their own.
    public static func buildDefault(info: [String: Any]? = Bundle.main.infoDictionary) -> HassServer? {
        guard let text = info?["HASS_DEFAULT_SERVER"] as? String,
              case let .success(server) = HassServerAddress.parse(text) else { return nil }
        return server
    }

    /// A placeholder server for galleries, previews and tests; nothing answers there.
    public static let example = HassServer(baseURL: URL(string: "https://home.example.com")!)

    /// OAuth `client_id` the app presents. Home Assistant requires a URL; it does not need to resolve
    /// because ``redirectURI`` shares its host (see `.agents/platforms/apple/auth.md`).
    public static let clientID = "https://home.sfenton.app/"

    /// OAuth `redirect_uri`, on the same host as ``clientID``.
    public static let redirectURI = "https://home.sfenton.app/auth-callback"

    /// Builds an absolute URL for an API path on this server.
    /// - Parameter path: A path such as `/auth/token`.
    /// - Returns: The absolute URL.
    public func url(_ path: String) -> URL {
        baseURL.appending(path: path.hasPrefix("/") ? String(path.dropFirst()) : path)
    }

    /// The websocket endpoint HAKit connects to is derived by HAKit from ``baseURL``.
    public var websocketDescription: String { baseURL.absoluteString + "/api/websocket" }
}
