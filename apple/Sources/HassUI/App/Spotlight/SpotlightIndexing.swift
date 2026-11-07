import HassCore

/// Puts the app's pages in system search and takes them out (`SpotlightCatalog`).
@MainActor
public protocol SpotlightIndexing: AnyObject {
    /// Replaces the app's items with the catalog's.
    func indexPages(_ entries: [SpotlightEntry])
    /// Removes every item the app indexed.
    func removeAll()
}
