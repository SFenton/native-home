import HassCore

/// The `SpotlightIndexing` that does nothing, for tests and journeys that must not touch the system index.
@MainActor
public final class InertSpotlightIndexer: SpotlightIndexing {
    /// Creates an indexer that ignores every call.
    public init() {}
    public func indexPages(_ entries: [SpotlightEntry]) {}
    public func removeAll() {}
}
