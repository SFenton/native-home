#if os(iOS)
import HassCore

// MARK: - A todo collection the publication does not define

/// Stands in for a todo collection the document names but no `todo-collection@1` source defines.
///
/// It lists nothing, loads nothing and offers no empty state, so the part of the page that depended on house configuration's
/// old page list is simply blank. House configuration is never consulted for it.
@MainActor
final class UKServerUIAbsentTodoCollection: UKServerUICollectionSource {
    let template = ServerUICompositionDocument.Collection.Template.todo
    var records: [UKServerUIRecord] { [] }
    var loading: Bool { false }
    var error: String? { nil }
    var hasPendingIntent: Bool { false }
    var hasMore: Bool { false }
    var showsSearch: Bool { false }
    var searchText = ""
    /// Empty, not nil: a tile that takes its title from the collection falls back to its own title.
    var navigationTitle: String? { "" }
    func load() async throws {}
    func loadMore() async throws {}
    func select(_ record: UKServerUIRecord) throws { throw ServerUIRecordFailure.staleSelection }
}
#endif
