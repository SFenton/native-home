import HassCore
import Observation

/// Keeps the app's Spotlight rooms in step with the house document.
///
/// The room entries come from the server's document (``SpotlightCatalog/entries(in:)``), which can arrive or change
/// after sign-in: from the disk copy, then from the server. The reindexer indexes once when it starts, then watches
/// the source and indexes again when the entries differ, so a room added, renamed or removed on the server reaches
/// system search without a new session. A change that leaves the entries as they were (a chip, a light) indexes nothing,
/// and a burst of changes (the cache copy, then the server's, then an edit) indexes once, ``debounce`` after the last.
@MainActor
public final class SpotlightReindexer {
    /// How long the entries must stay unchanged before they are indexed again.
    public static let debounce: Duration = .seconds(1)

    private let source: HouseConfigSource
    private let indexer: any SpotlightIndexing
    private let debounce: Duration
    private let sleeper: @MainActor (Duration) async throws -> Void
    private var indexed: [SpotlightEntry]?
    private var pending: Task<Void, Never>?
    /// Bumped by ``start()`` and ``stop()`` so an observation armed earlier cannot index afterwards.
    private var generation = 0

    /// Creates a reindexer.
    /// - Parameters:
    ///   - source: The source whose document names the rooms (the app passes `HouseConfigSource.shared`).
    ///   - indexer: Where the entries go.
    ///   - debounce: How long changed entries wait for a further change before they are indexed.
    ///   - sleeper: Waits out the debounce; tests pass one they finish by hand.
    public init(source: HouseConfigSource, indexer: any SpotlightIndexing, debounce: Duration = SpotlightReindexer.debounce,
                sleeper: @escaping @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.source = source
        self.indexer = indexer
        self.debounce = debounce
        self.sleeper = sleeper
    }

    /// Indexes the current entries and starts watching the source.
    public func start() {
        generation += 1
        cancelPending()
        indexed = nil
        observe()
    }

    /// Stops watching. Call before the document is cleared at sign-out, so the empty house is not indexed.
    public func stop() {
        generation += 1
        cancelPending()
    }

    private func cancelPending() {
        pending?.cancel()
        pending = nil
    }

    private func observe() {
        let armed = generation
        let entries = withObservationTracking {
            SpotlightCatalog.entries(in: source)
        } onChange: { [weak self] in
            // `onChange` runs before the new value lands; the main-actor hop runs after the writer (main actor) is done.
            Task { @MainActor [weak self] in
                guard let self, armed == self.generation else { return }
                self.observe()
            }
        }
        // Back to what is indexed: a change still waiting out its delay is stale.
        guard entries != indexed else { return cancelPending() }
        guard indexed != nil else { return index(entries) }
        cancelPending()
        let wait = debounce, sleeper = sleeper
        pending = Task { [weak self] in
            try? await sleeper(wait)
            guard !Task.isCancelled, let self, armed == self.generation else { return }
            self.pending = nil
            self.index(entries)
        }
    }

    private func index(_ entries: [SpotlightEntry]) {
        indexed = entries
        indexer.indexPages(entries)
    }
}
