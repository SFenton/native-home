import Foundation
@testable import HassCore
import Testing

/// The inventory pages' pure rules: grouping, batches, filter/sort, copy and stock-change projections.
/// "Today" is 2026-10-11 (UTC).
struct InventoryCatalogTests {
    let calendar = InventoryFixtures.calendar()

    private func item(
        _ id: Int?, _ name: String, quantity: Double = 1, location: StorageLocation? = .fridge,
        expiry: String? = nil, prepared: Bool = false, productId: Int? = nil
    ) -> InventoryItem {
        InventoryFixtures.item(id, name, quantity: quantity, location: location, expiry: expiry, prepared: prepared, productId: productId)
    }

    private func card(_ rows: InventoryItem...) -> InventoryDisplayItem { InventoryDisplayItem(rows: rows) }

    private func row(_ id: Int, _ quantity: Double) -> InventoryBatch.Row { InventoryBatch.Row(inventoryId: id, quantity: quantity) }

    // MARK: Grouping

    @Test func groupsRowsByLowercasedNameInFirstSeenOrder() {
        let items = [item(1, "Milk"), item(2, "Eggs", quantity: 12), item(3, "milk", quantity: 2)]
        let cards = InventoryCatalog.displayItems(items)
        #expect(cards.map(\.id) == ["milk", "eggs"])
        #expect(cards[0].name == "Milk")
        #expect(cards[0].rows.map(\.inventoryId) == [1, 3])
        #expect(cards[0].quantity == 3)
        #expect(cards[0].shownQuantity == 3)
        #expect(cards[1].shownQuantity == 12)
        #expect(InventoryCatalog.displayItems([item(1, "Solo")])[0].shownQuantity == nil)
        #expect(InventoryCatalog.displayItems([]).isEmpty)
    }

    @Test func soonestExpirySkipsUnparseableDates() {
        let milk = card(
            item(1, "Milk", expiry: "2026-12-01"), item(2, "Milk", expiry: "2026-10-20T08:00:00"),
            item(3, "Milk"), item(4, "Milk", expiry: "bad")
        )
        #expect(milk.soonestExpiry(calendar) == "2026-10-20T08:00:00")
        #expect(card(item(1, "Milk"), item(2, "Milk", expiry: "nope")).soonestExpiry(calendar) == nil)
    }

    // MARK: Batches

    @Test func batchKey() {
        #expect(InventoryBatch.key(for: item(1, "Milk", expiry: "2026-10-20")) == "frigo\u{0}2026-10-20\u{0}0")
        #expect(InventoryBatch.key(for: item(1, "Milk", location: nil, prepared: true)) == "\u{0}\u{0}1")
    }

    @Test func noCardNoBatches() {
        #expect(InventoryCatalog.batches(nil, fallbackPhrase: "fridge", calendar: calendar).isEmpty)
    }

    @Test func batchesMergeAndSortSoonestFirstThenLocationUndatedLast() {
        let milk = card(
            item(1, "Milk", quantity: 1, expiry: "2026-10-20"),
            item(2, "Milk", quantity: 2, expiry: "2026-10-20"),
            item(3, "Milk", location: .pantry),
            item(nil, "Milk", expiry: "2026-10-15"),
            item(5, "Milk", location: .pantry, expiry: "2026-10-20"),
            item(6, "Milk", location: nil, expiry: "2026-10-20"),
            item(7, "Milk", expiry: "2026-10-20", prepared: true),
            item(8, "Milk")
        )
        let batches = InventoryCatalog.batches(milk, fallbackPhrase: "library", calendar: calendar)
        #expect(batches.map(\.locationPhrase) == ["fridge", "fridge", "fridge", "library", "pantry", "fridge", "pantry"])
        #expect(batches.map(\.expiryDate) == ["2026-10-15", "2026-10-20", "2026-10-20", "2026-10-20", "2026-10-20", "", ""])
        #expect(batches.map(\.preparedFood) == [false, false, true, false, false, false, false])

        let unaddressable = batches[0]
        #expect(!unaddressable.addressable)
        #expect(unaddressable.rows.isEmpty)

        let merged = batches[1]
        #expect(merged.addressable)
        #expect(merged.quantity == 3)
        #expect(merged.rows == [row(1, 1), row(2, 2)])
        #expect(merged.sample.inventoryId == 1)
        #expect(merged.id == merged.key)
    }

    @Test func aRowWithoutIdMakesTheBatchUnaddressable() {
        let milk = card(item(1, "Milk", quantity: 2), item(nil, "Milk", quantity: 1))
        let batches = InventoryCatalog.batches(milk, fallbackPhrase: "fridge", calendar: calendar)
        #expect(batches.count == 1)
        #expect(!batches[0].addressable)
        #expect(batches[0].quantity == 3)
        #expect(batches[0].rows == [row(1, 2)])
    }

    @Test func tokenIsSortedKeysAndStock() {
        let milk = card(item(1, "Milk", quantity: 1.5, expiry: "2026-10-20"), item(2, "Milk", quantity: 2))
        let batches = InventoryCatalog.batches(milk, fallbackPhrase: "fridge", calendar: calendar)
        #expect(InventoryCatalog.token(batches) == "frigo\u{0}\u{0}0=2|frigo\u{0}2026-10-20\u{0}0=1.5")
        #expect(InventoryCatalog.token(Array(batches.reversed())) == InventoryCatalog.token(batches))
        #expect(InventoryCatalog.token([]) == "")
    }

    // MARK: Filter and sort

    /// Days from 2026-10-11: Date -10, Apple 1, Fig 1, banana 2, Grape 14, éclair 233, cherry/Zucchini undated.
    private var shelf: [InventoryDisplayItem] {
        InventoryCatalog.displayItems([
            item(1, "banana", expiry: "2026-10-13"),
            item(2, "Apple", expiry: "2026-10-12"),
            item(3, "cherry"),
            item(4, "Date", expiry: "2026-10-01"),
            item(5, "éclair", expiry: "2027-06-01"),
            item(6, "Fig", expiry: "2026-10-12"),
            item(7, "Grape", expiry: "2026-10-25"),
            item(8, "Zucchini"),
        ])
    }

    private func names(_ sort: InventorySortMode, _ direction: InventorySortDirection, _ filter: InventoryFilterMode = .all) -> [String] {
        InventoryCatalog.visible(shelf, sort: sort, direction: direction, filter: filter, calendar: calendar).map(\.name)
    }

    @Test func sortsByTitleIgnoringCaseAndDiacritics() {
        #expect(names(.title, .ascending) == ["Apple", "banana", "cherry", "Date", "éclair", "Fig", "Grape", "Zucchini"])
        #expect(names(.title, .descending) == ["Zucchini", "Grape", "Fig", "éclair", "Date", "cherry", "banana", "Apple"])
    }

    @Test func sortsByExpiryWithUndatedLastInBothDirections() {
        #expect(names(.expiry, .ascending) == ["Date", "Apple", "Fig", "banana", "Grape", "éclair", "cherry", "Zucchini"])
        #expect(names(.expiry, .descending) == ["éclair", "Grape", "banana", "Fig", "Apple", "Date", "cherry", "Zucchini"])
    }

    static let filterCases: [(InventoryFilterMode, [String])] = [
        (.all, ["Apple", "banana", "cherry", "Date", "éclair", "Fig", "Grape", "Zucchini"]),
        (.expired, ["Date"]),
        (.week, ["Apple", "banana", "Fig"]),
        (.month, ["Apple", "banana", "Fig", "Grape"]),
        (.sixMonths, ["Apple", "banana", "Fig", "Grape"]),
        (.year, ["Apple", "banana", "éclair", "Fig", "Grape"]),
        (.noExpiration, ["cherry", "Zucchini"]),
    ]

    @Test(arguments: InventoryCatalogTests.filterCases)
    func filters(filter: InventoryFilterMode, expected: [String]) {
        #expect(names(.title, .ascending, filter) == expected)
    }

    @Test func filterBoundaries() {
        #expect(InventoryFilterMode.all.includes(days: nil))
        #expect(InventoryFilterMode.all.includes(days: -5))
        #expect(!InventoryFilterMode.expired.includes(days: nil))
        #expect(InventoryFilterMode.expired.includes(days: -1))
        #expect(!InventoryFilterMode.expired.includes(days: 0))
        #expect(InventoryFilterMode.week.includes(days: 0))
        #expect(InventoryFilterMode.week.includes(days: 7))
        #expect(!InventoryFilterMode.week.includes(days: 8))
        #expect(!InventoryFilterMode.week.includes(days: -1))
        #expect(InventoryFilterMode.month.includes(days: 30))
        #expect(!InventoryFilterMode.month.includes(days: 31))
        #expect(InventoryFilterMode.sixMonths.includes(days: 183))
        #expect(!InventoryFilterMode.sixMonths.includes(days: 184))
        #expect(InventoryFilterMode.year.includes(days: 365))
        #expect(!InventoryFilterMode.year.includes(days: 366))
        #expect(InventoryFilterMode.noExpiration.includes(days: nil))
        #expect(!InventoryFilterMode.noExpiration.includes(days: 3))
    }

    @Test func modeCopy() {
        #expect(InventorySortMode.allCases.map(\.title) == ["Title", "Expiration Date"])
        #expect(InventorySortMode.title.subtitle == "Sort alphabetically by item name.")
        #expect(InventorySortMode.expiry.subtitle == "Sort by the item expiration date.")
        #expect(InventorySortMode.expiry.id == "expiry")
        #expect(InventorySortDirection.allCases.map(\.title) == ["Ascending", "Descending"])
        #expect(InventorySortDirection.ascending.hint == "A–Z, soonest first")
        #expect(InventorySortDirection.descending.hint == "Z–A, latest first")
        #expect(InventorySortDirection.descending.id == "descending")
        #expect(InventoryFilterMode.allCases.map(\.title) == [
            "All Items", "Expired", "Expiring Within a Week", "Expiring Within a Month", "Expiring Within 6 Months",
            "Expiring Within a Year", "No Expiration Date",
        ])
        #expect(InventoryFilterMode.allCases.map(\.subtitle) == [
            "Show everything in this location.", "Only items past their expiration date.", "Items expiring in the next 7 days.",
            "Items expiring in the next 30 days.", "Items expiring in the next 6 months.", "Items expiring in the next year.",
            "Items without a usable expiration date.",
        ])
        #expect(InventoryFilterMode.sixMonths.id == "six-months")
        #expect(InventoryFilterMode.noExpiration.rawValue == "no-expiration")
    }

    // MARK: Copy

    @Test func expiryInfoLabelsAndTones() {
        #expect(InventoryCatalog.expiryInfo(nil, calendar: calendar) == ExpiryInfo(label: "No Expiration Date", tone: nil))
        #expect(InventoryCatalog.expiryInfo("soon", calendar: calendar) == ExpiryInfo(label: "No Expiration Date", tone: nil))
        #expect(InventoryCatalog.expiryInfo("2026-10-10", calendar: calendar) == ExpiryInfo(label: "Expired Oct 10, 2026", tone: .expired))
        #expect(InventoryCatalog.expiryInfo("2026-10-11", calendar: calendar) == ExpiryInfo(label: "Expires Oct 11, 2026", tone: .soon))
        #expect(InventoryCatalog.expiryInfo("2026-10-17", calendar: calendar) == ExpiryInfo(label: "Expires Oct 17, 2026", tone: .soon))
        #expect(InventoryCatalog.expiryInfo("2026-10-18", calendar: calendar) == ExpiryInfo(label: "Expires Oct 18, 2026", tone: nil))
    }

    @Test func rowSubtitle() {
        let expiry = ExpiryInfo(label: "Expires Oct 20, 2026", tone: nil)
        #expect(InventoryCatalog.rowSubtitle(expiry, quantity: 3, batchCount: 1) == "Quantity 3 · Expires Oct 20, 2026")
        #expect(InventoryCatalog.rowSubtitle(expiry, quantity: nil, batchCount: 1) == "Expires Oct 20, 2026")
        #expect(InventoryCatalog.rowSubtitle(expiry, quantity: 2.5, batchCount: 2) == "Quantity 2.5 · Multiple Expiration Dates")
        #expect(InventoryCatalog.multipleDatesLabel == "Multiple Expiration Dates")
    }

    private func batch(expiry: String = "", prepared: Bool = false) -> InventoryBatch {
        let sample = item(1, "Milk", expiry: expiry.isEmpty ? nil : expiry, prepared: prepared)
        return InventoryBatch(
            key: InventoryBatch.key(for: sample), expiryDate: expiry, locationPhrase: "fridge", preparedFood: prepared,
            quantity: 1, rows: [row(1, 1)], sample: sample, addressable: true
        )
    }

    @Test func batchQualifier() {
        #expect(InventoryCatalog.batchQualifier(batch(expiry: "2026-10-20"), multipleBatches: false, calendar: calendar) == "")
        #expect(InventoryCatalog.batchQualifier(batch(prepared: true), multipleBatches: false, calendar: calendar) == " prepared")
        #expect(InventoryCatalog.batchQualifier(batch(expiry: "2026-10-20"), multipleBatches: true, calendar: calendar) == " expiring Oct 20, 2026")
        #expect(InventoryCatalog.batchQualifier(batch(expiry: "2026-10-20", prepared: true), multipleBatches: true, calendar: calendar)
            == " expiring Oct 20, 2026 prepared")
        #expect(InventoryCatalog.batchQualifier(batch(), multipleBatches: true, calendar: calendar) == " without an expiration date")
        #expect(InventoryCatalog.batchQualifier(batch(prepared: true), multipleBatches: true, calendar: calendar)
            == " without an expiration date prepared")
    }

    @Test func quantityChangeHint() {
        #expect(InventoryCatalog.quantityChangeHint(delta: 2, phrase: "fridge") == "Saving adds 2 items to the fridge.")
        #expect(InventoryCatalog.quantityChangeHint(delta: 1, phrase: "fridge") == "Saving adds 1 item to the fridge.")
        #expect(InventoryCatalog.quantityChangeHint(delta: -1, phrase: "pantry") == "Saving removes 1 item from the pantry.")
        #expect(InventoryCatalog.quantityChangeHint(delta: -2.5, phrase: "spice rack") == "Saving removes 2.5 items from the spice rack.")
    }

    // MARK: Empty state

    private func empty(error: String? = nil, loaded: Int = 0, visible: Int = 0, query: String = "", filter: Bool = false) -> [String]? {
        InventoryCatalog.emptyState(title: "Fridge", error: error, loadedCount: loaded, visibleCount: visible, query: query, filterActive: filter)
            .map { [$0.title, $0.description] }
    }

    @Test func emptyStateVariants() {
        #expect(empty(error: "Unable to load inventory", loaded: 3, visible: 3)
            == ["Unable to Load Fridge", "Try again in a moment, or scan an item while fridge is unavailable."])
        #expect(empty(error: "EverShelf is unavailable") == ["Unable to Load Fridge", "Fridge is unavailable"])
        #expect(empty(error: "Something else") == ["Unable to Load Fridge", "Something else"])
        #expect(empty() == ["No Items Found", "Scan an item to add it to your fridge."])
        #expect(empty(query: "milk") == ["No Matching Items", "Try a different search or clear the search to show all items."])
        #expect(empty(query: "milk", filter: true)
            == ["No Matching Items", "Try a different search, clear the selected filter, or clear the search to show all items."])
        #expect(empty(loaded: 3, visible: 2) == nil)
        #expect(empty(loaded: 3, visible: 0, filter: true) == ["No Matching Items", "Try a different filter, or clear it to show all items."])
        #expect(empty(loaded: 3, visible: 0, query: "milk")
            == ["No Matching Items", "Try a different search or clear the search to show all items."])
    }

    // MARK: Stock changes

    @Test func decreaseStepsTakeWholeSmallRowsFirst() {
        let rows = [row(1, 3), row(2, 1), row(3, 2)]
        let result = InventoryCatalog.decreaseSteps(rows, amount: 4)
        #expect(result.steps == [
            InventoryDeleteStep(inventoryId: 2), InventoryDeleteStep(inventoryId: 3), InventoryDeleteStep(inventoryId: 1, quantity: 1),
        ])
        #expect(result.remaining == [row(1, 2)])

        let none = InventoryCatalog.decreaseSteps(rows, amount: 0)
        #expect(none.steps.isEmpty)
        #expect(none.remaining == [row(2, 1), row(3, 2), row(1, 3)])

        let all = InventoryCatalog.decreaseSteps(rows, amount: 10)
        #expect(all.steps.map(\.inventoryId) == [2, 3, 1])
        #expect(all.steps.allSatisfy { $0.quantity == nil })
        #expect(all.remaining.isEmpty)

        let exact = InventoryCatalog.decreaseSteps(rows, amount: 1)
        #expect(exact.steps == [InventoryDeleteStep(inventoryId: 2)])
        #expect(exact.remaining == [row(3, 2), row(1, 3)])
    }

    @Test func preparedStepsTakeSmallestRowsFirst() {
        let rows = [row(1, 3), row(2, 1), row(3, 2)]
        #expect(InventoryCatalog.preparedSteps(rows, amount: 4) == [row(2, 1), row(3, 2), row(1, 1)])
        #expect(InventoryCatalog.preparedSteps(rows, amount: 0.5) == [row(2, 0.5)])
        #expect(InventoryCatalog.preparedSteps(rows, amount: 0).isEmpty)
        #expect(InventoryCatalog.preparedSteps(rows, amount: 100) == [row(2, 1), row(3, 2), row(1, 3)])
    }

    @Test func batchesAfterDelete() {
        let milk = card(item(1, "Milk", expiry: "2026-10-20"), item(2, "Milk", quantity: 2, expiry: "2026-10-20"), item(3, "Milk"))
        let batches = InventoryCatalog.batches(milk, fallbackPhrase: "fridge", calendar: calendar)
        let after = InventoryCatalog.batches(batches, after: [
            InventoryDeleteStep(inventoryId: 1), InventoryDeleteStep(inventoryId: 2, quantity: 0.5), InventoryDeleteStep(inventoryId: 3, quantity: 1),
        ])
        #expect(after.count == 1)
        #expect(after[0].rows == [row(2, 1.5)])
        #expect(after[0].quantity == 1.5)

        let duplicate = InventoryCatalog.batches(batches, after: [InventoryDeleteStep(inventoryId: 2, quantity: 1), InventoryDeleteStep(inventoryId: 2)])
        #expect(duplicate.map(\.quantity) == [2, 1], "The first step for an id wins")
        #expect(InventoryCatalog.batches(batches, after: []) == batches)
    }

    @Test func itemsAfterDelete() {
        let items = [item(1, "Milk", quantity: 2), item(2, "Eggs"), item(nil, "Bread"), item(4, "Jam", quantity: 3)]
        let after = InventoryCatalog.items(items, after: [
            InventoryDeleteStep(inventoryId: 1, quantity: 1), InventoryDeleteStep(inventoryId: 2), InventoryDeleteStep(inventoryId: 4, quantity: 3),
        ])
        #expect(after.map(\.name) == ["Milk", "Bread"])
        #expect(after[0].quantity == 1)
    }

    @Test func preparingIntoANewBatchSplitsInPlace() throws {
        let milk = card(item(1, "Milk", expiry: "2026-10-20"), item(2, "Milk", quantity: 2, expiry: "2026-10-20"), item(3, "Milk", location: .pantry))
        let batches = InventoryCatalog.batches(milk, fallbackPhrase: "fridge", calendar: calendar)
        let source = batches[0]
        let steps = InventoryCatalog.preparedSteps(source.rows, amount: 1)
        let after = InventoryCatalog.batches(batches, preparing: source, steps: steps, to: true)
        #expect(after.count == 3)
        #expect(after.map(\.preparedFood) == [false, true, false])
        #expect(after.map(\.quantity) == [2, 1, 1])
        #expect(!after[0].addressable && after[0].rows.isEmpty)
        #expect(!after[1].addressable && after[1].rows.isEmpty)
        #expect(after[1].key == "frigo\u{0}2026-10-20\u{0}1")
        #expect(after[1].sample.preparedFood)
        #expect(after[1].locationPhrase == "fridge")
        #expect(after[1].expiryDate == "2026-10-20")
        #expect(after[2] == batches[1])
    }

    @Test func preparingEverythingIntoAnExistingBatchMerges() {
        let milk = card(
            item(1, "Milk", quantity: 3, expiry: "2026-10-20"),
            item(2, "Milk", quantity: 2, expiry: "2026-10-20", prepared: true)
        )
        let batches = InventoryCatalog.batches(milk, fallbackPhrase: "fridge", calendar: calendar)
        #expect(batches.map(\.preparedFood) == [false, true])
        let source = batches[0]
        let steps = InventoryCatalog.preparedSteps(source.rows, amount: 3)
        let after = InventoryCatalog.batches(batches, preparing: source, steps: steps, to: true)
        #expect(after.count == 1)
        #expect(after[0].quantity == 5)
        #expect(after[0].preparedFood)
        #expect(after[0].sample.inventoryId == 2, "The existing batch's sample is kept")
        #expect(!after[0].addressable)
    }

    @Test func restockDataCarriesTheBatchIdentity() {
        var sample = item(1, "Milk", location: .fridge, expiry: "2026-10-20", productId: 11)
        sample.unit = "pz"
        sample.vacuumSealed = true
        #expect(InventoryCatalog.restockData(sample, quantity: 2, expiryDate: "2026-10-20") == [
            "inventory_prepared_food": .bool(false), "name": .string("Milk"), "quantity": .number(2), "vacuum_sealed": .bool(true),
            "product_id": .number(11), "location": .string("frigo"), "expiry_date": .string("2026-10-20"), "unit": .string("pz"),
        ])
        let bare = item(nil, "Thing", location: nil, prepared: true)
        #expect(InventoryCatalog.restockData(bare, quantity: 1.5, expiryDate: "") == [
            "inventory_prepared_food": .bool(true), "name": .string("Thing"), "quantity": .number(1.5), "vacuum_sealed": .bool(false),
        ])
    }

    @Test func deleteStepDefaultsToTheWholeRow() {
        #expect(InventoryDeleteStep(inventoryId: 4).quantity == nil)
        #expect(InventoryCatalog.maxQuantity == 999)
    }

    // MARK: Search

    @Test func searchTokensAreLowercaseWordsOfTwoOrMore() {
        #expect(InventoryCatalog.searchTokens("  Black b BEANS ") == ["black", "beans"])
        #expect(InventoryCatalog.searchTokens("a b").isEmpty)
        #expect(InventoryCatalog.searchTokens("").isEmpty)
    }

    @Test func localSearchNeedsEveryToken() {
        let beans = InventoryItem(inventoryId: 1, name: "Black Beans", searchText: "black beans acme legumes")
        let rice = InventoryItem(inventoryId: 2, name: "Rice")
        let items = [beans, rice]
        #expect(InventoryCatalog.locallySearched(items, query: "bla bea") == [beans])
        #expect(InventoryCatalog.locallySearched(items, query: "ACME") == [beans])
        #expect(InventoryCatalog.locallySearched(items, query: "black rice").isEmpty)
        #expect(InventoryCatalog.locallySearched(items, query: "x") == items, "Only short tokens: no filter")
        #expect(InventoryCatalog.locallySearched(items, query: "") == items)
    }
}
