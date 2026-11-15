import AppIntents
import FentonActivityModel

/// Answers the system's questions about pages from the saved route catalog.
///
/// It reads the small account-scoped file (``RouteCatalogStore``): no connection, no publication decode, so a Siri or Shortcuts
/// query in a headless launch stays cheap. Every route resolves by id or by name; only routes the author flagged `siri` are
/// suggested, capped at ``RouteCatalog/suggestionLimit``.
struct RouteQuery: EntityQuery, EntityStringQuery {
    /// Where the catalog comes from; tests replace it with a fake.
    nonisolated(unsafe) static var catalogSource: @Sendable () -> RouteCatalog? = { RouteCatalogStore.shared?.read() }

    func entities(for identifiers: [String]) async throws -> [RouteEntity] {
        (Self.catalogSource()?.entries(withIDs: identifiers) ?? []).map(RouteEntity.init)
    }

    func entities(matching string: String) async throws -> [RouteEntity] {
        (Self.catalogSource()?.matching(string) ?? []).map(RouteEntity.init)
    }

    func suggestedEntities() async throws -> [RouteEntity] {
        (Self.catalogSource()?.suggested ?? []).map(RouteEntity.init)
    }
}
