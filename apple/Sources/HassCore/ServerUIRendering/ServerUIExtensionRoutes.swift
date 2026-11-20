import Foundation
import FentonActivityModel

// MARK: - Authored system navigation

/// Where a ``RouteRequest`` lands once it is resolved against an accepted publication.
public struct RouteTarget: Equatable, Sendable {
    /// The page to show.
    public let pageId: String
    /// The tab to select first, when the route names one.
    public let tabId: String?
    /// The modal the request's anchor names, or nil (no anchor, or one the route does not author).
    public let modalId: String?
}

public extension ServerUICompositionDocument {
    /// The authored route a path names: its `path` first, then its `aliases`.
    /// - Parameter path: The path from a link, a Spotlight result or a shortcut.
    func route(matching path: String) -> NativeExtensionPresentation.Route? {
        let routes = extensions?.routes ?? []
        return routes.first { $0.path == path } ?? routes.first { $0.aliases.contains(path) }
    }

    /// The route authored with this id (a Spotlight result's identifier names the id).
    func route(withID id: String) -> NativeExtensionPresentation.Route? {
        extensions?.routes.first { $0.id == id }
    }

    /// Resolves a request into accepted authored page identities, or nil when no route carries the path.
    ///
    /// No path opens the publication's `navigation.initialPageId`. An unknown anchor opens the page and drops the anchor.
    /// An unknown path resolves to nothing: the caller opens the app and navigates nowhere, and no compiled controller or
    /// placeholder is substituted.
    func target(for request: RouteRequest) -> RouteTarget? {
        guard let path = request.path else { return RouteTarget(pageId: navigation.initialPageId, tabId: nil, modalId: nil) }
        guard let route = route(matching: path) else { return nil }
        let modalId = request.anchor.flatMap { anchor in route.anchors?.first { $0.fragment == anchor }?.modalId }
        return RouteTarget(pageId: route.pageId, tabId: route.tabId, modalId: modalId)
    }

    /// The tab a page belongs to, read from the authored routes that name it (`extensions.routes[].tabId`).
    ///
    /// A page link opened from another tab lands on this tab's stack, as the previous app opened a room under Home. A route with no
    /// `tabId` says nothing. The page is not homed (nil) when no route names a tab for it, when its routes name different tabs,
    /// or when the named tab is not one of the publication's tabs.
    /// - Parameter pageId: The destination page.
    /// - Returns: The home tab's id, or nil.
    func homeTab(of pageId: String) -> String? {
        let named = Set((extensions?.routes ?? []).filter { $0.pageId == pageId }.compactMap(\.tabId))
        guard named.count == 1, let tab = named.first, navigation.tabs.contains(where: { $0.id == tab }) else { return nil }
        return tab
    }
}
