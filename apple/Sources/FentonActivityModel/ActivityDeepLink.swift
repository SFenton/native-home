import Foundation

/// The URL a tap on the Home activity opens (`widgetURL`): the app's own scheme carrying the focused job's dashboard
/// path, which the app reads like a notification's `url` (`PushLink`).
///
/// `fentonhome://liveactivity?url=%2Fsfenton-react-dash%2Fhome%3Fpath%3Dkitchen`
public enum ActivityDeepLink {
    /// The scheme the app registers (`CFBundleURLTypes`). The widget extension and the app draw and read the same one.
    public static let scheme = "fentonhome"

    /// The host that marks a Live Activity tap.
    public static let host = "liveactivity"

    /// The link for a state: its `url`, or nil when it has none (a tap then just opens the app).
    public static func url(for state: HomeActivityState) -> URL? {
        guard let link = state.url, !link.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.queryItems = [URLQueryItem(name: "url", value: link)]
        return components.url
    }

    /// The dashboard link inside a Live Activity URL, or nil for any other URL.
    public static func link(from url: URL) -> String? {
        guard url.scheme == scheme, url.host == host,
              let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "url" })?.value,
              !value.isEmpty else { return nil }
        return value
    }
}
