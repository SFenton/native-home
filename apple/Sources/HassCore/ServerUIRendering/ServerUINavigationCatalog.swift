import Foundation

/// Destination identities extracted from a validated document, without reconstructing another UI tree.
///
/// The renderer retains the typed document's symbols and presentation policies. This catalog carries
/// only the metadata needed to preserve navigation instances through compatible publications.
public struct ServerUINavigationCatalog: Equatable, Sendable {
    // MARK: - Destinations

    /// One configured tab and the page that roots its stack.
    public struct Tab: Equatable, Sendable {
        /// The tab's published id.
        public let id: String
        /// The visible label.
        public let label: String
        /// The symbol name the label pairs with.
        public let icon: String
        /// The page at the root of the tab's stack.
        public let pageId: String
    }

    /// The document these destinations belong to; a catalog for another document is never applied.
    public let documentID: String
    /// The page the initial stack starts on.
    public let initialPageID: String
    /// The tab selected first, or `nil` when the initial page is not a tab.
    public let initialTabID: String?
    /// The configured tabs, in published order.
    public let tabs: [Tab]
    /// Every page id a stack may hold.
    public let pageIDs: [String]
    /// Every modal id that may be presented.
    public let modalIDs: [String]

    // MARK: - Creation

    /// Creates a catalog from already-extracted identities. Internal so tests can describe destinations without a document.
    init(documentID: String, initialPageID: String, initialTabID: String?, tabs: [Tab], pageIDs: [String], modalIDs: [String]) {
        self.documentID = documentID
        self.initialPageID = initialPageID
        self.initialTabID = initialTabID
        self.tabs = tabs
        self.pageIDs = pageIDs
        self.modalIDs = modalIDs
    }

    /// Schema 2 preserves the explicit initial tab, including an independent initial-page stack.
    public init(composition: ServerUICompositionDocument) {
        self.init(
            documentID: composition.id, initialPageID: composition.navigation.initialPageId,
            initialTabID: composition.navigation.initialTabId,
            tabs: composition.navigation.tabs.map { Tab(id: $0.id, label: $0.label, icon: $0.icon.name, pageId: $0.pageId) },
            pageIDs: composition.pages.map(\.id), modalIDs: composition.modals.map(\.id))
    }
}
