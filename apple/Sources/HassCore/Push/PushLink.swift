import Foundation

/// Where a notification's `url` (or a button's `uri`) points, read the way the web dashboard reads it
/// (`ha-sfenton-react-dash@9ac2a46:src/constants/routes.ts`, `routePathFromUrl`).
///
/// Automations link to the React dashboard, e.g. `/sfenton-react-dash/home?path=security#security-system`. The
/// app hands the route path to the publication's routes (``RouteRequest``) instead of opening the web page; it knows
/// no route names, so a path means whatever the published routes and their aliases say.
public enum PushLink: Equatable, Sendable {
    /// A dashboard route: its path (`security`, `master-bedroom`; nil when the link names none) and optional anchor.
    case dashboard(RouteRequest)
    /// A Home Assistant page outside the dashboard (`/config/automation/trace/...`).
    case homeAssistant(path: String)
    /// A web address on another host.
    case external(URL)

    /// Query keys the dashboard reads a route from, in order (web `ROUTE_QUERY_KEYS`).
    static let routeQueryKeys = ["path", "route", "view"]
    /// The slugs the integration has always sent as a link's first segment (web `dashboardHosts.ts`). They apply only
    /// while the publication authors no `extensions.linkPrefixes` (migration default; remove once the Studio publishes them).
    public static let migrationPrefixes = ["sfenton-react-dash", "ha-sfenton-react-dash", "at-a-glance"]

    /// Reads a link; nil for an empty or unparseable value.
    /// - Parameters:
    ///   - value: The `url` or `uri`.
    ///   - server: The signed-in server: absolute links to it are read like relative ones.
    ///   - prefixes: The first path segments that mark a dashboard link (the publication's `extensions.linkPrefixes`);
    ///     nil reads ``migrationPrefixes``.
    public init?(_ value: String, server: HassServer? = nil, prefixes: [String]? = nil) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.lowercased() != "noaction",
              let components = URLComponents(string: trimmed) else { return nil }
        guard let scheme = components.scheme?.lowercased() else {
            self.init(relative: components, prefixes: prefixes ?? Self.migrationPrefixes)
            return
        }
        // Companion-only forms (`entityId:`, `noAction`) and other schemes have no page here.
        guard scheme == "http" || scheme == "https", let url = components.url else { return nil }
        if let server, url.host?.lowercased() == server.baseURL.host?.lowercased() {
            self.init(relative: components, prefixes: prefixes ?? Self.migrationPrefixes)
        } else {
            self = .external(url)
        }
    }

    private init(relative components: URLComponents, prefixes: [String]) {
        let parts = components.path.split(separator: "/").map(String.init)
        let anchor = components.fragment.flatMap { $0.isEmpty ? nil : $0 }
        let isDashboard = parts.first.map(prefixes.contains) ?? false
        if isDashboard {
            let queried = Self.routeQueryKeys.lazy.compactMap { key in
                components.queryItems?.first { $0.name == key }?.value.flatMap(Self.routePath(fromValue:))
            }.first
            let segment = parts.dropFirst().first.flatMap { $0 == "home" || $0 == "index.html" ? nil : $0 }
            self = .dashboard(RouteRequest(path: queried ?? segment, anchor: anchor))
        } else if parts.isEmpty {
            self = .dashboard(RouteRequest(path: nil, anchor: anchor))
        } else {
            self = .homeAssistant(path: "/" + parts.joined(separator: "/"))
        }
    }

    /// A route path from a query value, which may itself carry a query or anchor.
    private static func routePath(fromValue value: String) -> String? {
        let decoded = value.removingPercentEncoding ?? value
        let path = decoded.split(separator: "#", maxSplits: 1).first.map(String.init) ?? ""
        let route = path.split(separator: "?", maxSplits: 1).first.map(String.init) ?? ""
        let trimmed = route.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard !trimmed.isEmpty else { return nil }
        return trimmed.split(separator: "/").last.map(String.init)
    }
}
