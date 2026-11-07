import Foundation
import Observation

/// One inventory page's state: rows, search, sort, filter and the row actions
/// (web `EverShelfInventoryPanel` + `useEverShelfInventoryControls`).
///
/// Models are kept per page for the session (``InventoryModels``), so going back to a page shows its last
/// rows at once and refreshes them in place instead of blanking to a spinner.
@MainActor
@Observable
public final class InventoryListModel {
    // MARK: - Types

    /// Whether the first load has finished.
    public enum Phase: Equatable, Sendable { case loading, content }

    /// A row's cart button (`PantryRowShoppingState`).
    public enum ShoppingState: Equatable, Sendable { case idle, adding, added }

    // MARK: - State

    /// The page.
    public let space: InventorySpace
    /// `loading` until the first answer (or failure) arrives.
    public private(set) var phase: Phase = .loading
    /// Rows from the last answer for ``settledQuery``.
    public private(set) var items: [InventoryItem] = []
    /// The last load's error, shown instead of rows.
    public private(set) var loadError: String?
    /// The query the current rows answer.
    public private(set) var settledQuery = ""
    /// A search is pending (typing, debouncing or waiting on the server).
    public private(set) var isSearching = false

    /// Search text; changes are debounced by ``searchDebounce``.
    public var searchQuery = "" {
        didSet { if searchQuery != oldValue { scheduleSearch() } }
    }

    /// Sort field.
    public var sortMode: InventorySortMode = .title
    /// Sort direction.
    public var sortDirection: InventorySortDirection = .ascending
    /// Expiry filter.
    public var filterMode: InventoryFilterMode = .all

    /// Per-card cart button state, by card id.
    public private(set) var shopping: [String: ShoppingState] = [:]
    /// Cards with a delete in flight.
    public private(set) var deleting: Set<String> = []
    /// Per-card action errors, by card id.
    public private(set) var rowErrors: [String: String] = [:]

    /// Calendar used for expiry rules.
    @ObservationIgnored public var calendar: InventoryCalendar
    /// Search debounce (`INVENTORY_SEARCH_DEBOUNCE_MS`).
    @ObservationIgnored public var searchDebounce: Duration = .milliseconds(250)
    /// How long the cart shows its check mark (`SHOPPING_ADDED_VISIBLE_MS`).
    @ObservationIgnored public var addedVisibleFor: Duration = .seconds(3)

    @ObservationIgnored let client: EverShelfClient
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var addedResetTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var isLoading = false

    // MARK: - Init

    /// Creates a page model.
    public init(space: InventorySpace, client: EverShelfClient, calendar: InventoryCalendar = .current) {
        self.space = space
        self.client = client
        self.calendar = calendar
    }

    // MARK: - Derived

    /// Cards, one per item name.
    public var displayItems: [InventoryDisplayItem] { InventoryCatalog.displayItems(items) }

    /// Cards after filter and sort.
    public var visibleItems: [InventoryDisplayItem] {
        InventoryCatalog.visible(displayItems, sort: sortMode, direction: sortDirection, filter: filterMode, calendar: calendar)
    }

    /// A non-default sort is applied.
    public var sortActive: Bool { sortMode != .title || sortDirection != .ascending }
    /// A filter is applied.
    public var filterActive: Bool { filterMode != .all }
    /// The search box has text.
    public var searchActive: Bool { !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty }

    /// The empty or error state to show, if any.
    public var emptyState: (title: String, description: String)? {
        guard phase == .content else { return nil }
        let visible = visibleItems.count
        return InventoryCatalog.emptyState(
            title: space.title, error: loadError, loadedCount: items.count, visibleCount: visible,
            query: settledQuery, filterActive: filterActive
        )
    }

    /// The card with `id`, from the current rows.
    public func displayItem(id: String) -> InventoryDisplayItem? { displayItems.first { $0.id == id } }

    /// The editor's batches for a card.
    public func batches(for item: InventoryDisplayItem) -> [InventoryBatch] {
        InventoryCatalog.batches(item, fallbackPhrase: space.phrase, calendar: calendar)
    }

    /// Row ids behind a card, or `nil` when any row lacks one (its delete is disabled).
    public func deletableRows(of item: InventoryDisplayItem) -> [InventoryBatch.Row]? {
        let rows = item.rows.compactMap { row in row.inventoryId.map { InventoryBatch.Row(inventoryId: $0, quantity: row.quantity) } }
        return rows.isEmpty || rows.count != item.rows.count ? nil : rows
    }

    // MARK: - Loading

    /// Loads the page: the first time with a loading state, afterwards refreshing in place.
    public func load() async {
        if phase == .content {
            _ = try? await refresh()
            return
        }
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let query = trimmedQuery
        let current = bumpGeneration()
        do {
            let next = try await client.pageItems(location: space.location, query: query)
            guard current == generation else { return }
            apply(next, query: query, error: nil)
        } catch {
            guard current == generation else { return }
            apply([], query: query, error: ServiceErrorText.message(for: error, fallback: "Unable to load inventory"))
        }
        // Typed while the first load was out: search for it now.
        if trimmedQuery != query { scheduleSearch() }
    }

    /// Reloads the current search; the editor awaits it after a change.
    /// - Returns: The new rows.
    @discardableResult
    public func refresh() async throws -> [InventoryItem] {
        let query = trimmedQuery
        let current = bumpGeneration()
        do {
            let next = try await client.pageItems(location: space.location, query: query)
            if current == generation { apply(next, query: query, error: nil) }
            return next
        } catch {
            if current == generation {
                loadError = ServiceErrorText.message(for: error, fallback: "Unable to load inventory")
                settledQuery = query
                isSearching = false
                phase = .content
            }
            throw error
        }
    }

    private var trimmedQuery: String { searchQuery.trimmingCharacters(in: .whitespaces) }

    private func bumpGeneration() -> Int {
        generation += 1
        return generation
    }

    private func apply(_ next: [InventoryItem], query: String, error: String?) {
        items = next
        loadError = error
        settledQuery = query
        isSearching = trimmedQuery != query
        phase = .content
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let query = trimmedQuery
        guard phase == .content else { return }
        isSearching = query != settledQuery
        guard isSearching else { return }
        searchTask = Task { [weak self, searchDebounce] in
            try? await Task.sleep(for: searchDebounce)
            guard !Task.isCancelled, let self else { return }
            await self.search(query)
        }
    }

    private func search(_ query: String) async {
        let current = bumpGeneration()
        do {
            let next = try await client.pageItems(location: space.location, query: query)
            // A newer keystroke supersedes this answer (`search-finish-superseded`).
            guard current == generation, trimmedQuery == query else { return }
            apply(next, query: query, error: nil)
        } catch {
            guard current == generation, trimmedQuery == query else { return }
            apply([], query: query, error: ServiceErrorText.message(for: error, fallback: "Unable to load inventory"))
        }
    }

    // MARK: - Row actions

    /// Adds a card to the shopping and grocery lists; the cart shows a check for a few seconds.
    public func addToShopping(_ item: InventoryDisplayItem, quantity: Double) async {
        guard shopping[item.id, default: .idle] == .idle else { return }
        addedResetTasks[item.id]?.cancel()
        shopping[item.id] = .adding
        rowErrors[item.id] = nil
        do {
            try await client.addToShoppingList(name: item.name, quantity: quantity)
            shopping[item.id] = .added
            addedResetTasks[item.id] = Task { [weak self, addedVisibleFor] in
                try? await Task.sleep(for: addedVisibleFor)
                guard !Task.isCancelled else { return }
                self?.shopping[item.id] = .idle
            }
        } catch {
            shopping[item.id] = .idle
            rowErrors[item.id] = ServiceErrorText.message(for: error, fallback: "Unable to add to shopping list")
        }
    }

    /// Deletes a card's stock: all of it, or `quantity` spread smallest row first.
    public func delete(_ item: InventoryDisplayItem, quantity: Double? = nil) async {
        guard let rows = deletableRows(of: item), !deleting.contains(item.id) else { return }
        let stocked = rows.reduce(0) { $0 + $1.quantity }
        let steps = quantity.flatMap { $0 < stocked ? InventoryCatalog.decreaseSteps(rows, amount: $0).steps : nil }
            ?? rows.map { InventoryDeleteStep(inventoryId: $0.inventoryId) }
        deleting.insert(item.id)
        rowErrors[item.id] = nil
        defer { deleting.remove(item.id) }
        do {
            try await client.delete(steps)
            items = InventoryCatalog.items(items, after: steps)
        } catch {
            rowErrors[item.id] = ServiceErrorText.message(for: error, fallback: "Unable to delete item")
        }
    }

    /// Shows an action's validation message on a card (e.g. an out-of-range quantity).
    public func setRowError(_ message: String?, for id: String) {
        rowErrors[id] = message
    }
}

// MARK: - Registry

/// Page models kept for the session, so each inventory page survives navigation and reopening.
@MainActor
public final class InventoryModels {
    private let client: EverShelfClient
    private let calendar: InventoryCalendar
    private var models: [InventorySpace: InventoryListModel] = [:]

    /// Creates a registry over one client.
    public init(client: EverShelfClient, calendar: InventoryCalendar = .current) {
        self.client = client
        self.calendar = calendar
    }

    /// The client the pages and Scan Item share.
    public var everShelf: EverShelfClient { client }

    /// The model for a page, created once.
    public func model(for space: InventorySpace) -> InventoryListModel {
        if let model = models[space] { return model }
        let model = InventoryListModel(space: space, client: client, calendar: calendar)
        models[space] = model
        return model
    }

    /// Refreshes every page that has loaded (after Scan Item adds stock).
    public func refreshLoaded() async {
        for model in models.values where model.phase == .content {
            _ = try? await model.refresh()
        }
    }
}
