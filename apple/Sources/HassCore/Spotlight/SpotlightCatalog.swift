import FentonActivityModel
import Foundation

/// The pages the app puts in Spotlight (`CSSearchableItem`), one per authored route, and the way back from a tapped result.
///
/// Core Spotlight gives an installed app's own pages, not the app icon, extra search words. Every entry carries
/// ``AppBranding/searchTerms`` so "Home Assistant", "HASS", "Fenton" or "Smart Home" lists the app's pages, each of
/// which opens S+H on that page. The app compiles no pages of its own: the entries are the accepted route catalog.
public enum SpotlightCatalog {
    /// Groups the app's items so they can all be removed at once (sign-out, and the one-time clearing of an older build's items).
    public static let domainIdentifier = "com.sfenton.home.pages"

    /// What an item's identifier starts with; the rest is the route's id.
    public static let identifierPrefix = "route."

    /// One entry per route the person is offered.
    /// - Parameter catalog: The accepted route catalog.
    public static func entries(for catalog: RouteCatalog) -> [SpotlightEntry] {
        catalog.routes.map(entry(for:))
    }

    /// The entry for one route.
    public static func entry(for route: RouteCatalogEntry) -> SpotlightEntry {
        SpotlightEntry(id: identifierPrefix + route.id, routeID: route.id, title: route.title, summary: route.summary,
                       keywords: [route.title] + route.keywords + AppBranding.searchTerms, symbol: route.icon,
                       request: RouteRequest(path: route.path))
    }

    /// The route id a tapped result stands for.
    /// - Parameter identifier: The tapped item's unique identifier.
    /// - Returns: The id, or nil for an identifier from an older build (`section.*`, `room.*`, `authored.*`).
    public static func routeID(forIdentifier identifier: String) -> String? {
        guard identifier.hasPrefix(identifierPrefix), identifier.count > identifierPrefix.count else { return nil }
        return String(identifier.dropFirst(identifierPrefix.count))
    }
}
