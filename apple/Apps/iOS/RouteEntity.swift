import AppIntents
import CoreSpotlight
import FentonActivityModel
import HassCore

/// One page of the app that Siri, Shortcuts and Spotlight can name: a route the publication authors.
///
/// The app knows no page names. Everything here comes from the accepted route catalog (``RouteCatalogStore``): the title the
/// person says, the symbol, and the authored keywords that become spoken synonyms. `id` is the route's stable id, never its
/// path, so renaming a path keeps saved Shortcuts working.
struct RouteEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Page")
    static let defaultQuery = RouteQuery()

    let id: String
    /// The path the app opens (``RouteRequest``).
    let path: String
    let title: String
    let summary: String
    /// An SF Symbol name.
    let symbol: String
    let keywords: [String]

    init(_ entry: RouteCatalogEntry) {
        id = entry.id
        path = entry.path
        title = entry.title
        summary = entry.summary
        symbol = entry.icon
        keywords = entry.keywords
    }

    /// The entity for a Spotlight item, for the iOS 18 association (the item's own words stay on the item).
    init(_ entry: SpotlightEntry) {
        id = entry.routeID
        path = entry.request.path ?? ""
        title = entry.title
        summary = entry.summary
        symbol = entry.symbol
        keywords = []
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(summary)", image: .init(systemName: symbol),
                              synonyms: keywords.map { "\($0)" })
    }
}

/// On iOS 18 and later the entity joins the Spotlight item of the same route, so there is one result per route and a tap runs
/// ``OpenRouteIntent`` (`SpotlightCatalog` indexes the item; ``associate(_:with:)`` links the two).
@available(iOS 18.0, *)
extension RouteEntity: IndexedEntity {
    /// Links `entity` to the item whose attributes these are.
    static func associate(_ attributes: CSSearchableItemAttributeSet, with entity: RouteEntity) {
        attributes.associateAppEntity(entity, priority: 1)
    }
}
