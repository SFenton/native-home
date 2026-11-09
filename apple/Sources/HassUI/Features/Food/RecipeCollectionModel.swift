import Foundation
import HassCore
import Observation

/// The Recipes grid: criteria, paging and remote-catalog hydration (web `useRecipeControls` + `useRecipeCollection`).
@MainActor
@Observable
final class RecipeCollectionModel {
    enum Phase: Equatable { case idle, loading, loaded, failed }

    // MARK: Controls

    /// The search field. Changes reload after ``debounce``.
    var searchText = "" {
        didSet { if searchText != oldValue { scheduleSearch() } }
    }
    private(set) var sort: RecipeSort = .availability
    private(set) var filters = RecipeFilters.defaults
    private(set) var appliedQuery = ""

    var sortActive: Bool { sort != .availability }
    var filterActive: Bool { filters != .defaults }

    /// The query sent to the server.
    var criteria: RecipeBrowseCriteria {
        RecipeBrowseCriteria(
            query: appliedQuery, sort: sort, availabilityWeight: filters.availabilityWeight,
            expiryWeight: filters.expiryWeight, minimumCoverage: filters.minimumCoverage,
            expiringWithinDays: filters.expiringOnly ? filters.expiringWithinDays : nil
        )
    }

    // MARK: Results

    private(set) var phase: Phase = .idle
    private(set) var items: [RecipeCard] = []
    private(set) var hasMore = false
    private(set) var nextPageLoading = false
    private(set) var nextPageFailed = false
    private(set) var hydrating = false
    /// Polite announcement for VoiceOver (web live region).
    private(set) var announcement = ""

    // MARK: Plumbing

    @ObservationIgnored var service: (any RecipeServing)?
    @ObservationIgnored var debounce: Duration = .milliseconds(250)
    @ObservationIgnored var hydrationSettle: Duration = .milliseconds(600)
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var cursor: String?
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var pageTask: Task<Void, Never>?
    @ObservationIgnored private var hydrationTask: Task<Void, Never>?

    /// Hydration starts for queries this long or longer (web `query.length < 3`).
    static let hydrationMinimumQuery = 3
    /// Items from the end that trigger the next page.
    static let prefetchDistance = 8

    // MARK: Intents

    /// First appearance loads; later appearances keep what is on screen.
    func appear() {
        if phase == .idle { reload() }
    }

    /// Applies a sort from the Sort sheet.
    func apply(sort newSort: RecipeSort) {
        guard newSort != sort else { return }
        sort = newSort
        reload()
    }

    /// Applies filters from the Filter sheet.
    func apply(filters newFilters: RecipeFilters) {
        guard newFilters != filters else { return }
        filters = newFilters
        reload()
    }

    /// Loads the first page for the current criteria, replacing the results.
    func reload() {
        generation += 1
        let current = generation
        [loadTask, pageTask, hydrationTask].forEach { $0?.cancel() }
        cursor = nil
        hasMore = false
        nextPageLoading = false
        nextPageFailed = false
        hydrating = false
        phase = .loading
        guard let service else { return }
        let criteria = criteria
        loadTask = Task { [weak self] in
            do {
                let page = try await service.browse(criteria, cursor: nil)
                guard let self, self.generation == current else { return }
                self.items = page.items
                self.cursor = page.nextCursor
                self.hasMore = page.hasMore && page.nextCursor != nil
                self.phase = .loaded
                self.announce(page.items.isEmpty ? "No recipes found." : "\(page.total) recipes.")
                self.startHydration(criteria, generation: current)
            } catch {
                guard let self, self.generation == current, !Task.isCancelled else { return }
                self.items = []
                self.phase = .failed
                self.announce("Unable to load recipes.")
            }
        }
    }

    /// Call as each card appears; near the end it loads the next page (web infinite scroll).
    func itemAppeared(_ item: RecipeCard) {
        // Only the last few cards matter, so look at those instead of searching the whole (growing) list for every
        // card that scrolls into view.
        guard items.suffix(Self.prefetchDistance).contains(where: { $0.dedupeKey == item.dedupeKey }) else { return }
        loadNextPage()
    }

    /// Loads the next page unless one is loading, failed, or there is none.
    func loadNextPage() {
        guard phase == .loaded, hasMore, !nextPageLoading, !nextPageFailed, let cursor, let service else { return }
        let current = generation
        let criteria = criteria
        nextPageLoading = true
        pageTask = Task { [weak self] in
            do {
                let page = try await service.browse(criteria, cursor: cursor)
                guard let self, self.generation == current else { return }
                let added = self.append(page.items)
                self.cursor = page.nextCursor
                self.hasMore = page.hasMore && page.nextCursor != nil
                self.nextPageLoading = false
                if added > 0 { self.announce("\(added) more recipes loaded; \(self.items.count) total.") }
            } catch {
                guard let self, self.generation == current, !Task.isCancelled else { return }
                self.nextPageLoading = false
                self.nextPageFailed = true
            }
        }
    }

    /// Retries a failed next page.
    func retryNextPage() {
        nextPageFailed = false
        loadNextPage()
    }

    /// Waits for in-flight work (tests).
    func settle() async {
        await searchTask?.value
        await loadTask?.value
        await pageTask?.value
        await hydrationTask?.value
    }

    // MARK: Private

    private func scheduleSearch() {
        searchTask?.cancel()
        let delay = debounce
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            let normalized = RecipeBrowseCriteria(query: self.searchText).normalizedQuery
            guard normalized != self.appliedQuery else { return }
            self.appliedQuery = normalized
            self.reload()
        }
    }

    /// Imports remote results for a search and appends those that pass the filters (web hydration effect).
    private func startHydration(_ criteria: RecipeBrowseCriteria, generation current: Int) {
        guard criteria.normalizedQuery.count >= Self.hydrationMinimumQuery, let service else { return }
        let settleDelay = hydrationSettle
        hydrationTask = Task { [weak self] in
            try? await Task.sleep(for: settleDelay)
            var searchId: String?
            while !Task.isCancelled {
                guard let self, self.generation == current else { return }
                // Observation republishes equal values; setting it each poll redrew the whole grid.
                if !self.hydrating { self.hydrating = true }
                let poll: RecipeHydration
                do {
                    poll = try await service.hydrate(criteria, searchId: searchId)
                } catch {
                    if self.generation == current { self.hydrating = false }
                    return
                }
                guard self.generation == current else { return }
                let added = self.append(poll.newItems.filter(criteria.matchesFilters))
                if added > 0 { self.announce("\(added) more recipes hydrated; \(self.items.count) total.") }
                if poll.isFailed || poll.isComplete {
                    self.hydrating = false
                    return
                }
                searchId = poll.searchId
                let wait = min(30_000, max(0, poll.nextPollMilliseconds ?? 1_000))
                try? await Task.sleep(for: .milliseconds(wait))
            }
        }
    }

    /// Appends cards not already shown; returns how many were added (web `appendUniqueRecipes`).
    @discardableResult
    private func append(_ incoming: [RecipeCard]) -> Int {
        var keys = Set(items.map(\.dedupeKey))
        let additions = incoming.filter { keys.insert($0.dedupeKey).inserted }
        if !additions.isEmpty { items += additions }
        return additions.count
    }

    private func announce(_ text: String) { announcement = text }
}
