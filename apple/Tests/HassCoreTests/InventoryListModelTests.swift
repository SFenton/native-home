import Foundation
@testable import HassCore
import HassTestSupport
import Testing

/// One inventory page against the fixture server: loading, search, sort/filter and the row actions.
/// "Today" is 2026-10-11 (UTC).
@MainActor
@Suite(.demoHouse)
struct InventoryListModelTests {
    typealias Row = EverShelfFixtureServer.Row

    let calendar = InventoryFixtures.calendar()

    private func makeServer() -> EverShelfFixtureServer {
        EverShelfFixtureServer(rows: [
            Row(id: 1, name: "Whole Milk", quantity: 1, location: .fridge, expiryDate: "2026-10-14", brand: "Acme"),
            Row(id: 2, name: "Eggs", quantity: 12, location: .fridge, expiryDate: "2026-10-29"),
            Row(id: 3, name: "Butter", quantity: 1, location: .fridge, expiryDate: "2026-10-05"),
            Row(id: 4, name: "Black Beans", quantity: 2, location: .pantry, expiryDate: nil),
        ])
    }

    private func makeModel(_ space: InventorySpace = .fridge, server: EverShelfFixtureServer? = nil) -> (InventoryListModel, EverShelfFixtureServer) {
        let server = server ?? makeServer()
        return (InventoryListModel(space: space, client: EverShelfClient(caller: server), calendar: calendar), server)
    }

    private func loaded(_ space: InventorySpace = .fridge) async -> (InventoryListModel, EverShelfFixtureServer) {
        let (model, server) = makeModel(space)
        await model.load()
        return (model, server)
    }

    private func names(_ model: InventoryListModel) -> [String] { model.visibleItems.map(\.name) }

    private func empty(_ model: InventoryListModel) -> [String]? { model.emptyState.map { [$0.title, $0.description] } }

    private func sleep(_ milliseconds: Int) async { try? await Task.sleep(for: .milliseconds(milliseconds)) }

    // MARK: Loading

    @Test func startsLoading() {
        let (model, server) = makeModel()
        #expect(model.space == .fridge)
        #expect(model.phase == .loading)
        #expect(model.items.isEmpty)
        #expect(model.emptyState == nil)
        #expect(!model.sortActive && !model.filterActive && !model.searchActive)
        #expect(!model.isSearching)
        #expect(model.searchDebounce == .milliseconds(250))
        #expect(model.addedVisibleFor == .seconds(3))
        #expect(server.calls.isEmpty)
    }

    @Test func loadShowsTheLocationsRows() async {
        let (model, server) = await loaded()
        #expect(model.phase == .content)
        #expect(model.items.map(\.inventoryId) == [1, 2, 3])
        #expect(model.displayItems.count == 3)
        #expect(names(model) == ["Butter", "Eggs", "Whole Milk"])
        #expect(model.settledQuery == "")
        #expect(model.loadError == nil)
        #expect(model.emptyState == nil)
        #expect(server.calls == ["evershelf.list_inventory location=frigo"])
    }

    @Test func loadingAgainRefreshesInPlace() async {
        let (model, server) = await loaded()
        server.rows.removeAll { $0.name == "Eggs" }
        await model.load()
        #expect(model.phase == .content)
        #expect(names(model) == ["Butter", "Whole Milk"])
        #expect(server.calls.count == 2)
    }

    @Test func concurrentFirstLoadsMakeOneCall() async {
        let (model, server) = makeModel()
        server.latency = .milliseconds(50)
        let first = Task { await model.load() }
        let second = Task { await model.load() }
        await first.value
        await second.value
        #expect(server.calls.count == 1)
        #expect(model.phase == .content)
    }

    @Test func loadFailureShowsTheServersMessage() async {
        let (model, server) = makeModel()
        server.failing = ["evershelf.list_inventory"]
        await model.load()
        #expect(model.phase == .content)
        #expect(model.items.isEmpty)
        #expect(model.loadError == "EverShelf is unavailable")
        #expect(empty(model) == ["Unable to Load Fridge", "Fridge is unavailable"])
    }

    @Test func loadFailureWithoutAMessageUsesTheFallback() async {
        let stub = InventoryStubCaller()
        stub.errors["list_inventory"] = InventoryStubError()
        let model = InventoryListModel(space: .pantry, client: EverShelfClient(caller: stub), calendar: calendar)
        await model.load()
        #expect(model.loadError == "Unable to load inventory")
        #expect(empty(model) == ["Unable to Load Pantry", "Try again in a moment, or scan an item while pantry is unavailable."])
    }

    @Test func emptyLocation() async {
        let (model, _) = await loaded(.freezer)
        #expect(empty(model) == ["No Items Found", "Scan an item to add it to your freezer."])
    }

    @Test func refreshReturnsRowsAndKeepsThemOnFailure() async throws {
        let (model, server) = await loaded()
        let rows = try await model.refresh()
        #expect(rows.count == 3)

        server.failing = ["evershelf.list_inventory"]
        await #expect(throws: (any Error).self) { try await model.refresh() }
        #expect(model.loadError == "EverShelf is unavailable")
        #expect(model.items.count == 3, "Rows stay while the error shows")
        #expect(model.phase == .content)
        #expect(!model.isSearching)

        server.failing = []
        try await model.refresh()
        #expect(model.loadError == nil)
    }

    // MARK: Search

    @Test func searchIsDebounced() async {
        let (model, server) = await loaded()
        model.searchQuery = "milk"
        #expect(model.isSearching)
        #expect(model.searchActive)
        #expect(server.calls.count == 1, "Nothing is sent before the debounce")
        #expect(await eventually { server.calls.count == 2 && !model.isSearching })
        #expect(server.calls.count == 2)
        #expect(server.calls.last == "evershelf.list_inventory location=frigo q=milk")
        #expect(names(model) == ["Whole Milk"])
        #expect(model.settledQuery == "milk")
        #expect(!model.isSearching)
    }

    @Test func fastTypingSendsOneSearch() async {
        let (model, server) = await loaded()
        model.searchDebounce = .milliseconds(50)
        model.searchQuery = "m"
        model.searchQuery = "mi"
        model.searchQuery = " milk "
        #expect(await eventually { model.settledQuery == "milk" })
        await sleep(100) // Nothing else follows the settled search.
        #expect(server.calls == ["evershelf.list_inventory location=frigo", "evershelf.list_inventory location=frigo q=milk"])
        #expect(model.settledQuery == "milk")
    }

    @Test func returningToTheSettledQueryCancelsTheSearch() async {
        let (model, server) = await loaded()
        model.searchDebounce = .milliseconds(50)
        model.searchQuery = "milk"
        model.searchQuery = ""
        #expect(!model.isSearching)
        model.searchQuery = "   "
        #expect(!model.isSearching)
        #expect(!model.searchActive)
        await sleep(200)
        #expect(server.calls.count == 1)
    }

    @Test func searchWithNoMatches() async {
        let (model, _) = await loaded()
        model.searchDebounce = .milliseconds(10)
        model.searchQuery = "zzz"
        #expect(await eventually { model.settledQuery == "zzz" && !model.isSearching })
        #expect(model.items.isEmpty)
        #expect(empty(model) == ["No Matching Items", "Try a different search or clear the search to show all items."])
        model.filterMode = .expired
        #expect(empty(model) == ["No Matching Items", "Try a different search, clear the selected filter, or clear the search to show all items."])
    }

    @Test func searchFailureShowsTheError() async {
        let (model, server) = await loaded()
        model.searchDebounce = .milliseconds(10)
        server.failing = ["evershelf.list_inventory"]
        model.searchQuery = "milk"
        #expect(await eventually { model.loadError != nil })
        #expect(model.loadError == "EverShelf is unavailable")
        #expect(model.items.isEmpty)
        #expect(model.settledQuery == "milk")
        #expect(!model.isSearching)
    }

    @Test func typingDuringTheFirstLoadSearchesAfterIt() async {
        let (model, server) = makeModel()
        model.searchDebounce = .milliseconds(20)
        server.latency = .milliseconds(1500) // The first load must still be in flight when the query is typed, however busy the host is.
        let load = Task { await model.load() }
        #expect(await eventually { !server.calls.isEmpty }, "The first load is in flight")
        model.searchQuery = "milk"
        #expect(!model.isSearching, "No search is scheduled before the first load")
        await load.value
        #expect(model.settledQuery == "")
        #expect(model.isSearching)
        #expect(await eventually(timeout: .seconds(15)) { model.settledQuery == "milk" && !model.isSearching })
        #expect(model.settledQuery == "milk")
        #expect(names(model) == ["Whole Milk"])
        #expect(!model.isSearching)
    }

    // MARK: Sort and filter

    @Test func sortAndFilterFlags() async {
        let (model, _) = await loaded()
        model.sortMode = .expiry
        #expect(model.sortActive)
        #expect(names(model) == ["Butter", "Whole Milk", "Eggs"])
        model.sortDirection = .descending
        #expect(names(model) == ["Eggs", "Whole Milk", "Butter"])
        model.sortMode = .title
        #expect(model.sortActive)
        #expect(names(model) == ["Whole Milk", "Eggs", "Butter"])
        model.sortDirection = .ascending
        #expect(!model.sortActive)

        model.filterMode = .expired
        #expect(model.filterActive)
        #expect(names(model) == ["Butter"])
        model.filterMode = .week
        #expect(names(model) == ["Whole Milk"])
        model.filterMode = .noExpiration
        #expect(names(model).isEmpty)
        #expect(empty(model) == ["No Matching Items", "Try a different filter, or clear it to show all items."])
        model.filterMode = .all
        #expect(!model.filterActive)
        #expect(model.emptyState == nil)
    }

    // MARK: Cards

    @Test func cardsAndBatches() async throws {
        let (model, _) = await loaded()
        let eggs = try #require(model.displayItem(id: "eggs"))
        #expect(eggs.name == "Eggs")
        #expect(model.displayItem(id: "nope") == nil)
        let batches = model.batches(for: eggs)
        #expect(batches.count == 1)
        #expect(batches[0].locationPhrase == "fridge")
        #expect(model.deletableRows(of: eggs) == [InventoryBatch.Row(inventoryId: 2, quantity: 12)])
    }

    @Test func batchesFallBackToThePagePhrase() {
        let (model, _) = makeModel(.allFood)
        let card = InventoryDisplayItem(rows: [InventoryFixtures.item(1, "Jam", location: nil)])
        #expect(model.batches(for: card).map(\.locationPhrase) == ["library"])
    }

    @Test func cardsWithAnUnaddressableRowCannotBeDeleted() {
        let (model, _) = makeModel()
        let mixed = InventoryDisplayItem(rows: [InventoryFixtures.item(1, "Jam"), InventoryFixtures.item(nil, "Jam")])
        let none = InventoryDisplayItem(rows: [InventoryFixtures.item(nil, "Jam")])
        #expect(model.deletableRows(of: mixed) == nil)
        #expect(model.deletableRows(of: none) == nil)
    }

    // MARK: Shopping

    @Test func addToShoppingGoesIdleAddingAddedIdle() async throws {
        let (model, server) = await loaded()
        let eggs = try #require(model.displayItem(id: "eggs"))
        // Windows no stalled main actor can outlast between two statements (1 s and 600 ms failed under load): the
        // check shows for 4 s, and the add stays in flight for 1.5 s.
        model.addedVisibleFor = .seconds(4)
        server.latency = .milliseconds(1500)
        #expect(model.shopping["eggs"] == nil)

        let add = Task { await model.addToShopping(eggs, quantity: 2) }
        #expect(await eventually { model.shopping["eggs"] == .adding })
        #expect(model.shopping["eggs"] == .adding)
        await model.addToShopping(eggs, quantity: 2)
        await add.value
        #expect(model.shopping["eggs"] == .added)
        #expect(server.calls.suffix(2) == ["evershelf.add_to_shopping name=Eggs quantity=2", "todo.add_item entity_id=todo.demo_todo_2 item=Eggs"])
        #expect(server.calls.count == 3, "The tap while adding was ignored")

        await model.addToShopping(eggs, quantity: 2)
        #expect(server.calls.count == 3, "The tap while the check shows was ignored")

        #expect(await eventually(timeout: .seconds(15)) { model.shopping["eggs"] == .idle })
        #expect(model.rowErrors["eggs"] == nil)
    }

    @Test func addToShoppingFailureShowsARowError() async throws {
        let (model, server) = await loaded()
        let eggs = try #require(model.displayItem(id: "eggs"))
        server.failing = ["evershelf.add_to_shopping"]
        await model.addToShopping(eggs, quantity: 1)
        #expect(model.shopping["eggs"] == .idle)
        #expect(model.rowErrors["eggs"] == "EverShelf is unavailable")

        server.failing = []
        await model.addToShopping(eggs, quantity: 1)
        #expect(model.shopping["eggs"] == .added)
        #expect(model.rowErrors["eggs"] == nil)
    }

    // MARK: Delete

    @Test func deleteAQuantity() async throws {
        let (model, server) = await loaded()
        let eggs = try #require(model.displayItem(id: "eggs"))
        await model.delete(eggs, quantity: 5)
        #expect(server.calls.last == "evershelf.delete_inventory inventory_id=2 quantity=5")
        #expect(server.rows.first { $0.id == 2 }?.quantity == 7)
        #expect(model.displayItem(id: "eggs")?.quantity == 7)
        #expect(model.deleting.isEmpty)
        #expect(model.rowErrors["eggs"] == nil)
    }

    @Test func deleteAtLeastTheStockRemovesTheCard() async throws {
        let (model, server) = await loaded()
        let milk = try #require(model.displayItem(id: "whole milk"))
        await model.delete(milk, quantity: 3)
        #expect(server.calls.last == "evershelf.delete_inventory inventory_id=1")
        #expect(model.displayItem(id: "whole milk") == nil)

        let butter = try #require(model.displayItem(id: "butter"))
        await model.delete(butter)
        #expect(server.calls.last == "evershelf.delete_inventory inventory_id=3")
        #expect(names(model) == ["Eggs"])
    }

    @Test func deleteSpreadsOverRowsSmallestFirst() async throws {
        let server = makeServer()
        server.rows.append(Row(id: 5, name: "Eggs", quantity: 2, location: .fridge, expiryDate: "2026-11-05"))
        let (model, _) = makeModel(server: server)
        await model.load()
        let eggs = try #require(model.displayItem(id: "eggs"))
        #expect(eggs.quantity == 14)
        await model.delete(eggs, quantity: 3)
        #expect(server.calls.suffix(2) == ["evershelf.delete_inventory inventory_id=5", "evershelf.delete_inventory inventory_id=2 quantity=1"])
        #expect(model.displayItem(id: "eggs")?.rows.map(\.inventoryId) == [2])
        #expect(model.displayItem(id: "eggs")?.quantity == 11)
    }

    @Test func deleteInFlightBlocksASecondDelete() async throws {
        let (model, server) = await loaded()
        let eggs = try #require(model.displayItem(id: "eggs"))
        server.latency = .milliseconds(1500) // Long enough that the second delete is made while the first is in flight, however busy the host is.
        let first = Task { await model.delete(eggs, quantity: 1) }
        #expect(await eventually { !model.deleting.isEmpty })
        #expect(model.deleting == ["eggs"])
        await model.delete(eggs, quantity: 1)
        await first.value
        #expect(server.calls.count == 2)
        #expect(model.deleting.isEmpty)
    }

    @Test func deleteFailureShowsARowError() async throws {
        let (model, server) = await loaded()
        let eggs = try #require(model.displayItem(id: "eggs"))
        server.failing = ["evershelf.delete_inventory"]
        await model.delete(eggs)
        #expect(model.rowErrors["eggs"] == "EverShelf is unavailable")
        #expect(model.displayItem(id: "eggs")?.quantity == 12)
        #expect(model.deleting.isEmpty)
    }

    @Test func unaddressableCardsAreNotDeleted() async {
        let (model, server) = await loaded()
        await model.delete(InventoryDisplayItem(rows: [InventoryFixtures.item(nil, "Ghost")]))
        #expect(server.calls.count == 1)
    }

    @Test func setRowError() {
        let (model, _) = makeModel()
        model.setRowError("Enter a number from 1 to 3.", for: "eggs")
        #expect(model.rowErrors["eggs"] == "Enter a number from 1 to 3.")
        model.setRowError(nil, for: "eggs")
        #expect(model.rowErrors["eggs"] == nil)
    }

    // MARK: Registry

    @Test func registryKeepsOneModelPerPage() {
        let client = EverShelfClient(caller: makeServer())
        let models = InventoryModels(client: client, calendar: calendar)
        let fridge = models.model(for: .fridge)
        #expect(models.model(for: .fridge) === fridge)
        #expect(models.model(for: .pantry) !== fridge)
        #expect(models.everShelf === client)
        #expect(fridge.space == .fridge)
        #expect(fridge.calendar.today == calendar.today)
    }

    @Test func refreshLoadedOnlyRefreshesLoadedPages() async {
        let server = makeServer()
        let models = InventoryModels(client: EverShelfClient(caller: server), calendar: calendar)
        let fridge = models.model(for: .fridge)
        let pantry = models.model(for: .pantry)
        await fridge.load()
        server.rows.removeAll { $0.id == 1 }
        await models.refreshLoaded()
        #expect(server.calls == ["evershelf.list_inventory location=frigo", "evershelf.list_inventory location=frigo"])
        #expect(pantry.phase == .loading)
        #expect(fridge.items.count == 2)
    }
}
