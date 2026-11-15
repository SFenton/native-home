import Foundation

/// A route path as the publication authors it: a plain, lower-case token such as `master-bedroom`.
///
/// The app knows no route names. A path means something only because a published route (or one of its aliases) carries it.
public enum RoutePath {
    /// What a path may look like, the same rule the publication enforces on `extensions.routes[].path`.
    public static let pattern = "^[a-z][a-z0-9-]{0,79}$"

    /// Whether `value` is a well-formed path.
    public static func isValid(_ value: String) -> Bool {
        value.range(of: pattern, options: .regularExpression) == value.startIndex..<value.endIndex
    }
}

/// A request from outside the page graph to open a page of the app: a push link, a Live Activity tap, a Spotlight result, an
/// App Shortcut or a Siri phrase. The one value all four hand to the shell.
///
/// The request carries no page ids. It is resolved against the accepted publication
/// (``ServerUICompositionDocument/target(for:)``): a path opens its route, no path opens the publication's initial page,
/// and a path no route carries opens the app and navigates nowhere.
public struct RouteRequest: Equatable, Sendable {
    /// The route path (or an alias of it); nil opens the publication's initial page.
    public var path: String?
    /// The `#anchor`: the route's sheet to open on the page. An anchor the route does not author is dropped.
    public var anchor: String?

    /// Creates a request.
    public init(path: String? = nil, anchor: String? = nil) {
        self.path = path
        self.anchor = anchor
    }
}
