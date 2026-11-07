import Foundation
@preconcurrency import HAKit
@preconcurrency import HAKit_Mocks
@testable import HassCore
import HassTestSupport
import Testing

/// EverShelfClient against the in-memory fixture server (EverShelf's batch rules) and a scriptable stub.
@MainActor
@Suite(.demoHouse)
struct EverShelfClientTests {
    typealias Row = EverShelfFixtureServer.Row

    private func makeServer() -> EverShelfFixtureServer {
        EverShelfFixtureServer(rows: [
            Row(id: 1, name: "Whole Milk", quantity: 1, location: .fridge, expiryDate: "2026-10-14", productId: 21, brand: "Acme"),
            Row(id: 2, name: "Eggs", quantity: 12, location: .fridge, expiryDate: "2026-10-29", productId: 22),
            Row(id: 3, name: "Black Beans", quantity: 2, location: .pantry, expiryDate: "2027-06-01", productId: 11),
            Row(id: 4, name: "Black Beans", quantity: 1, location: .pantry, expiryDate: "2027-12-01", productId: 11),
            Row(id: 5, name: "Spaghetti", quantity: 1, location: .pantry, expiryDate: nil),
        ])
    }

    // MARK: listInventory

    @Test func listsOneLocation() async throws {
        let server = makeServer()
        let response = try await EverShelfClient(caller: server).listInventory(location: .fridge)
        #expect(response.items.map(\.name) == ["Whole Milk", "Eggs"])
        #expect(response.search == nil)
        #expect(response.source == nil)
        #expect(server.calls == ["evershelf.list_inventory location=frigo"])

        let milk = response.items[0]
        #expect(milk.inventoryId == 1)
        #expect(milk.unit == "pz")
        #expect(milk.productId == 21)
        #expect(milk.location == .fridge)
        #expect(milk.expiryDate == "2026-10-14")
        #expect(!milk.preparedFood && !milk.vacuumSealed)
        #expect(milk.searchText == "whole milk acme")
    }

    @Test func listsEverythingThroughTheServerSearch() async throws {
        let server = makeServer()
        let response = try await EverShelfClient(caller: server).listInventory(location: nil, query: "beans")
        #expect(response.items.map(\.inventoryId) == [3, 4])
        #expect(response.search == "beans")
        #expect(response.source == "ha_sensor_product_search")
        #expect(server.calls == ["evershelf.list_inventory q=beans"])
    }

    @Test func nullListIsEmpty() async throws {
        let stub = InventoryStubCaller()
        let response = try await EverShelfClient(caller: stub).listInventory(location: nil)
        #expect(response == EverShelfClient.ListResponse(items: [], search: nil, source: nil))
        #expect(stub.calls.count == 1)
        #expect(stub.calls[0].name == "evershelf.list_inventory")
        #expect(stub.calls[0].data.isEmpty)
    }

    @Test func listFailurePropagates() async {
        let server = makeServer()
        server.failing = ["evershelf.list_inventory"]
        let client = EverShelfClient(caller: server)
        await #expect(throws: EverShelfFixtureServer.Failure.self) {
            _ = try await client.listInventory(location: .fridge)
        }
    }

    // MARK: pageItems

    @Test func pageWithoutQueryIsTheWholeLocation() async throws {
        let server = makeServer()
        let items = try await EverShelfClient(caller: server).pageItems(location: .pantry, query: "")
        #expect(items.map(\.inventoryId) == [3, 4, 5])
    }

    @Test func confirmedSearchUsesTheServerRows() async throws {
        let server = makeServer()
        let items = try await EverShelfClient(caller: server).pageItems(location: .fridge, query: "acme")
        #expect(items.map(\.name) == ["Whole Milk"])
        #expect(server.calls == ["evershelf.list_inventory location=frigo q=acme"])
    }

    @Test func confirmedSearchIsTrustedEvenWhenTheLocalFilterWouldDisagree() async throws {
        let stub = InventoryStubCaller()
        let milk: JSONValue = .object(["inventory_id": .number(1), "name": .string("Milk")])
        stub.responses["list_inventory"] = .object([
            "inventory": .array([milk]), "source": .string("ha_sensor_product_search"), "search": .string(" dairy "),
        ])
        let client = EverShelfClient(caller: stub)
        #expect(try await client.pageItems(location: nil, query: "dairy").map(\.name) == ["Milk"])
        #expect(stub.calls.last?.data["q"] == .string("dairy"))

        // Without the source (or with another search) the client filters locally, and "dairy" isn't in "milk".
        stub.responses["list_inventory"] = .object(["inventory": .array([milk]), "search": .string("dairy")])
        #expect(try await client.pageItems(location: nil, query: "dairy").isEmpty)
        stub.responses["list_inventory"] = .object([
            "inventory": .array([milk]), "source": .string("ha_sensor_product_search"), "search": .string("other"),
        ])
        #expect(try await client.pageItems(location: nil, query: "dairy").isEmpty)
    }

    @Test func unconfirmedSearchFallsBackToTheLocalFilter() async throws {
        let server = makeServer()
        server.unconfirmedSearch = true
        let client = EverShelfClient(caller: server)
        let raw = try await client.listInventory(location: .fridge, query: "acme")
        #expect(raw.items.count == 2, "The server ignored the search")
        #expect(raw.source == nil)
        let items = try await client.pageItems(location: .fridge, query: "acme")
        #expect(items.map(\.name) == ["Whole Milk"])
    }

    @Test func aggregatedSearchHitsExpandIntoRows() async throws {
        let server = makeServer()
        server.aggregatedSearch = true
        let items = try await EverShelfClient(caller: server).pageItems(location: .pantry, query: "beans")
        #expect(items.map(\.inventoryId) == [3, 4])
        #expect(items.map(\.quantity) == [2, 1])
        #expect(server.calls == ["evershelf.list_inventory location=dispensa q=beans", "evershelf.list_inventory location=dispensa"])
    }

    @Test func unresolvableAggregatesStay() async {
        let stub = InventoryStubCaller()
        stub.responses["list_inventory"] = .object(["inventory": .array([.object(["inventory_id": .number(1), "name": .string("Milk")])])])
        let client = EverShelfClient(caller: stub)
        let ghost = InventoryItem(inventoryId: nil, inventoryIds: [99], name: "Ghost")
        let partial = InventoryItem(inventoryId: nil, inventoryIds: [1, 99], name: "Milk")
        let plain = InventoryItem(inventoryId: 7, name: "Eggs")

        let expanded = await client.expandingAggregates([ghost, partial, plain], location: .fridge)
        #expect(expanded.map(\.name) == ["Ghost", "Milk", "Eggs"])
        #expect(expanded.map(\.inventoryId) == [nil, 1, 7])
        #expect(stub.calls.last?.data["location"] == .string("frigo"))
    }

    @Test func aggregatesStayWhenTheUnfilteredReadFails() async {
        let stub = InventoryStubCaller()
        stub.errors["list_inventory"] = InventoryStubError()
        let ghost = InventoryItem(inventoryId: nil, inventoryIds: [1], name: "Ghost")
        #expect(await EverShelfClient(caller: stub).expandingAggregates([ghost], location: nil) == [ghost])
        #expect(stub.calls.count == 1)
    }

    @Test func nothingToExpandMakesNoCall() async {
        let stub = InventoryStubCaller()
        let items = [InventoryItem(inventoryId: 1, name: "Milk"), InventoryItem(inventoryId: nil, name: "No ids")]
        #expect(await EverShelfClient(caller: stub).expandingAggregates(items, location: nil) == items)
        #expect(stub.calls.isEmpty)
    }

    // MARK: Mutations

    @Test func deletesWholeRowsAndPartialQuantities() async throws {
        let server = makeServer()
        let client = EverShelfClient(caller: server)
        try await client.delete(InventoryDeleteStep(inventoryId: 2, quantity: 5))
        #expect(server.calls.last == "evershelf.delete_inventory inventory_id=2 quantity=5")
        #expect(server.rows.first { $0.id == 2 }?.quantity == 7)

        try await client.delete(InventoryDeleteStep(inventoryId: 2, quantity: 0.5))
        #expect(server.calls.last == "evershelf.delete_inventory inventory_id=2 quantity=0.5")
        #expect(server.rows.first { $0.id == 2 }?.quantity == 6.5)

        try await client.delete([InventoryDeleteStep(inventoryId: 1), InventoryDeleteStep(inventoryId: 5)])
        #expect(server.calls.suffix(2) == ["evershelf.delete_inventory inventory_id=1", "evershelf.delete_inventory inventory_id=5"])
        #expect(server.rows.map(\.id) == [2, 3, 4])

        try await client.delete(InventoryDeleteStep(inventoryId: 404))
        #expect(server.rows.map(\.id) == [2, 3, 4], "Unknown ids are ignored")
    }

    @Test func deleteStopsAtTheFirstFailure() async {
        let server = makeServer()
        server.failing = ["evershelf.delete_inventory"]
        let client = EverShelfClient(caller: server)
        await #expect(throws: (any Error).self) {
            try await client.delete([InventoryDeleteStep(inventoryId: 1), InventoryDeleteStep(inventoryId: 2)])
        }
        #expect(server.calls.count == 1)
        #expect(server.rows.count == 5)
    }

    @Test func updateExpiryMovesOneUnit() async throws {
        let server = makeServer()
        let client = EverShelfClient(caller: server)
        try await client.updateExpiry(inventoryId: 1, expiryDate: "2026-11-01")
        #expect(server.calls.last == "evershelf.update_inventory_item expiry_date=2026-11-01 inventory_id=1")
        #expect(server.rows.filter { $0.name == "Whole Milk" }.map(\.expiryDate) == ["2026-11-01"])
        #expect(server.rows.first { $0.id == 1 } == nil)

        try await client.updateExpiry(inventoryId: 2, expiryDate: "")
        let eggs = server.rows.filter { $0.name == "Eggs" }
        #expect(eggs.map(\.quantity) == [11, 1])
        #expect(eggs.map(\.expiryDate) == ["2026-10-29", nil])
    }

    @Test func restockSendsTheBatchIdentity() async throws {
        let server = makeServer()
        let client = EverShelfClient(caller: server)
        let eggs = try #require(try await client.listInventory(location: .fridge).items.first { $0.name == "Eggs" })
        try await client.restock(InventoryCatalog.restockData(eggs, quantity: 2, expiryDate: "2026-10-29"))
        #expect(server.calls.last
            == "evershelf.add_scanned_item expiry_date=2026-10-29 inventory_prepared_food=false location=frigo name=Eggs product_id=22 quantity=2 unit=pz vacuum_sealed=false")
        #expect(server.rows.first { $0.id == 2 }?.quantity == 14, "Merged into the matching batch")
    }

    @Test func setsPreparedFood() async throws {
        let server = makeServer()
        let client = EverShelfClient(caller: server)
        try await client.setPreparedFood(inventoryId: 2, prepared: true, quantity: 2)
        #expect(server.calls.last == "evershelf.set_inventory_prepared_food inventory_id=2 prepared_food=true quantity=2")
        let eggs = server.rows.filter { $0.name == "Eggs" }
        #expect(eggs.map(\.quantity) == [10, 2])
        #expect(eggs.map(\.preparedFood) == [false, true])

        try await client.setPreparedFood(inventoryId: 1, prepared: false, quantity: 1.5)
        #expect(server.calls.last == "evershelf.set_inventory_prepared_food inventory_id=1 prepared_food=false quantity=1.5")
    }

    @Test func addToShoppingListCallsBothListsInOrder() async throws {
        let server = makeServer()
        try await EverShelfClient(caller: server).addToShoppingList(name: "Eggs", quantity: 2)
        #expect(server.calls == ["evershelf.add_to_shopping name=Eggs quantity=2", "todo.add_item entity_id=todo.demo_todo_2 item=Eggs"])
        #expect(EverShelfClient.groceryListEntityId == "todo.demo_todo_2")
    }

    @Test func addToShoppingListStopsWhenEverShelfFails() async {
        let server = makeServer()
        server.failing = ["evershelf.add_to_shopping"]
        let client = EverShelfClient(caller: server)
        await #expect(throws: (any Error).self) { try await client.addToShoppingList(name: "Eggs", quantity: 1) }
        #expect(server.calls == ["evershelf.add_to_shopping name=Eggs quantity=1"])
    }

    // MARK: Scan Item services

    @Test func resolvesBarcodes() async throws {
        let server = makeServer()
        let client = EverShelfClient(caller: server)
        let found = try await client.resolveBarcode("0123456789012")
        #expect(found["found"] == .bool(true))
        #expect(found["product"]?["name"] == .string("Greek Yogurt"))
        #expect(server.calls.last == "evershelf.resolve_barcode barcode=0123456789012")

        let missing = try await client.resolveBarcode("999")
        #expect(missing["found"] == .bool(false))
        #expect(missing["barcode"] == .string("999"))
    }

    @Test func preparesScannedProducts() async throws {
        let server = makeServer()
        let client = EverShelfClient(caller: server)
        let fresh = try await client.prepareScannedProduct(["name": .string("Yogurt")])
        #expect(fresh["success"] == .bool(true))
        #expect(fresh["id"] == .number(901))
        #expect(fresh["product_fingerprint"] == .string(String(repeating: "a", count: 64)))
        #expect(server.calls.last == "evershelf.prepare_scanned_product name=Yogurt")

        let known = try await client.prepareScannedProduct(["name": .string("Yogurt"), "product_id": .number(501)])
        #expect(known["id"] == .number(501))
    }

    @Test func suggestsLocations() async throws {
        let server = makeServer()
        let payload = try await EverShelfClient(caller: server).suggestLocation(["name": .string("Milk"), "mode": .string("manual")])
        #expect(payload["location"] == .string("frigo"))
        #expect(payload["source"] == .string("history_barcode"))
        #expect(server.calls.last == "evershelf.suggest_location mode=manual name=Milk")
    }

    @Test func readsExpiryImagesAndShortensTheLoggedImage() async throws {
        let server = makeServer()
        let url = "data:image/jpeg;base64," + String(repeating: "A", count: 40)
        let payload = try await EverShelfClient(caller: server).readExpiryImage(dataURL: url)
        #expect(payload["expiry_date"] == .string("2030-01-15"))
        #expect(server.calls.last == "evershelf.read_expiry_image image=" + String(url.prefix(24)) + "…")
    }

    @Test func addsScannedItems() async throws {
        let server = makeServer()
        try await EverShelfClient(caller: server).addScannedItem(
            ["name": .string("Yogurt"), "location": .string("frigo"), "quantity": .number(2), "prepared_food": .bool(true)],
            location: .fridge
        )
        let yogurt = try #require(server.rows.last)
        #expect(yogurt.name == "Yogurt")
        #expect(yogurt.id == 6)
        #expect(yogurt.quantity == 2)
        #expect(yogurt.preparedFood)
        #expect(yogurt.expiryDate == nil)
    }

    @Test func addScannedItemThrowsTheServersMessage() async {
        let server = makeServer()
        let client = EverShelfClient(caller: server)
        await #expect(throws: EverShelfClient.Failure("Missing name or location")) {
            try await client.addScannedItem(["name": .string("Yogurt")], location: .fridge)
        }
        #expect(server.rows.count == 5)
    }

    @Test func addScannedItemFailureFallbacks() async throws {
        let stub = InventoryStubCaller()
        let client = EverShelfClient(caller: stub)
        stub.responses["add_scanned_item"] = .object(["success": .bool(false), "error": .string("duplicate")])
        await #expect(throws: EverShelfClient.Failure("duplicate")) { try await client.addScannedItem([:], location: .fridge) }
        stub.responses["add_scanned_item"] = .object(["success": .bool(false)])
        await #expect(throws: EverShelfClient.Failure("Could not add this item to Freezer.")) { try await client.addScannedItem([:], location: .freezer) }
        stub.responses["add_scanned_item"] = .object(["ok": .bool(true)])
        try await client.addScannedItem([:], location: .freezer)
    }

    @Test func emptyAnswersThrowTheServicesMessage() async {
        let client = EverShelfClient(caller: InventoryStubCaller())
        await #expect(throws: EverShelfClient.Failure("Barcode lookup did not return a response.")) { _ = try await client.resolveBarcode("1") }
        await #expect(throws: EverShelfClient.Failure("The product could not be prepared.")) { _ = try await client.prepareScannedProduct([:]) }
        await #expect(throws: EverShelfClient.Failure("Storage suggestion did not return a response.")) { _ = try await client.suggestLocation([:]) }
        await #expect(throws: EverShelfClient.Failure("Expiration reader did not return a response.")) { _ = try await client.readExpiryImage(dataURL: "x") }
        await #expect(throws: EverShelfClient.Failure("Could not add this item to Pantry.")) { try await client.addScannedItem([:], location: .pantry) }
    }

    @Test func serviceResponseEnvelopeIsUnwrapped() async throws {
        let stub = InventoryStubCaller()
        let client = EverShelfClient(caller: stub)
        stub.responses["resolve_barcode"] = .object(["service_response": .object(["found": .bool(true)])])
        #expect(try await client.resolveBarcode("1") == .object(["found": .bool(true)]))
        #expect(stub.calls.last?.name == "evershelf.resolve_barcode")
        #expect(stub.calls.last?.data["barcode"] == .string("1"))

        stub.responses["list_inventory"] = .object(["service_response": .object([
            "inventory": .array([.object(["inventory_id": .number(3), "name": .string("Jam")])]),
        ])])
        #expect(try await client.listInventory(location: nil).items.map(\.name) == ["Jam"])

        // A non-object envelope is not unwrapped.
        let outer: JSONValue = .object(["service_response": .string("x"), "found": .bool(false)])
        #expect(EverShelfClient.payload(outer) == outer)
        #expect(EverShelfClient.payload(.null) == .null)
    }

    @Test func helpers() {
        #expect(EverShelfClient.Failure("boom").errorDescription == "boom")
        #expect(EverShelfClient.Failure("boom") == EverShelfClient.Failure("boom"))
        #expect(EverShelfClient.number(2) as? Int == 2)
        #expect(EverShelfClient.number(1.5) as? Double == 1.5)
        #expect(EverShelfClient.number(1e16) as? Double == 1e16)
    }

    // MARK: Fixture server

    @Test func fixtureServerBookkeeping() async throws {
        let server = makeServer()
        #expect(server.lastCall == "None")
        #expect(try await server.callServiceForResponse("evershelf", "unknown_service", data: ["flag": true]) == .null)
        #expect(server.lastCall == "evershelf.unknown_service flag=true")

        // `search` is accepted as the query key too.
        let searched = try await server.callServiceForResponse("evershelf", "list_inventory", data: ["search": "eggs"])
        #expect(searched["search"] == .string("eggs"))
        #expect(searched["inventory"]?.array?.count == 1)

        server.latency = .milliseconds(1)
        try await server.callService("evershelf", "update_inventory_item", data: ["inventory_id": 404, "expiry_date": "2026-01-01"])
        try await server.callService("evershelf", "set_inventory_prepared_food", data: ["inventory_id": 404])
        #expect(server.rows.count == 5)

        let failure = EverShelfFixtureServer.Failure(errorDescription: "EverShelf is unavailable")
        #expect(ServiceErrorText.message(for: failure, fallback: "x") == "EverShelf is unavailable")
    }

    @Test func fixtureServerPreparesWholeRowsByDefault() async throws {
        let server = makeServer()
        try await server.callService("evershelf", "set_inventory_prepared_food", data: ["inventory_id": 5])
        #expect(server.rows.filter { $0.name == "Spaghetti" }.map(\.preparedFood) == [true])
    }

    @Test func fixtureDescribe() {
        #expect(EverShelfFixtureServer.describe(.array([.number(1), .string("a"), .bool(false)])) == "[1,a,false]")
        #expect(EverShelfFixtureServer.describe(.object(["a": .null])) == "{…}")
        #expect(EverShelfFixtureServer.describe(.null) == "null")
        #expect(EverShelfFixtureServer.describe(.number(2.5)) == "2.5")
        #expect(EverShelfFixtureServer.describe("todo", "add_item", ["b": .string("2"), "a": .string("1")]) == "todo.add_item a=1 b=2")
    }

    @Test func fixtureJSONRow() {
        let json = EverShelfFixtureServer.json(Row(id: 9, name: "Soup", quantity: 2, location: .freezer, expiryDate: nil, preparedFood: true))
        let item = InventoryItem(json: json)
        #expect(item?.inventoryId == 9)
        #expect(item?.preparedFood == true)
        #expect(item?.expiryDate == nil)
        #expect(item?.productId == nil)
        #expect(json["brand"] == nil)
    }

    @Test func sampleServerIsRelativeToToday() {
        let calendar = InventoryFixtures.calendar()
        let server = EverShelfFixtureServer.sample(calendar: calendar)
        #expect(server.rows.count == 11)
        let rice = server.rows.first { $0.name == "Jasmine Rice" }
        #expect(rice?.expiryDate == "2026-10-08")
        #expect(calendar.isExpired(rice?.expiryDate))
        #expect(server.rows.first { $0.name == "Honey" }?.expiryDate == nil)
        #expect(server.rows.first { $0.name == "Chicken Soup" }?.preparedFood == true)
        _ = EverShelfFixtureServer.sample()
    }

    // MARK: ServiceErrorText

    private struct Described: LocalizedError {
        var errorDescription: String?
    }

    private struct Plain: Error {}

    @Test func serviceErrorText() {
        let external = HAError.external(.init(code: "home_assistant_error", message: "EverShelf: inventory list failed"))
        #expect(ServiceErrorText.message(for: external, fallback: "f") == "EverShelf: inventory list failed")
        #expect(ServiceErrorText.message(for: HAError.external(.init(code: "x", message: "")), fallback: "f") == "f")
        #expect(ServiceErrorText.message(for: HAError.internal(debugDescription: "offline"), fallback: "f") == "offline")
        #expect(ServiceErrorText.message(for: HAError.internal(debugDescription: ""), fallback: "f") == "f")
        #expect(ServiceErrorText.message(for: HAError.underlying(NSError(domain: "d", code: 1)), fallback: "f") == "f")
        #expect(ServiceErrorText.message(for: Described(errorDescription: "described"), fallback: "f") == "described")
        #expect(ServiceErrorText.message(for: Described(errorDescription: ""), fallback: "f") == "f")
        #expect(ServiceErrorText.message(for: Described(errorDescription: nil), fallback: "f") == "f")
        #expect(ServiceErrorText.message(for: Plain(), fallback: "f") == "f")
    }

    // MARK: HassConnection

    private func makeConnection() -> (HassConnection, HAMockConnection) {
        let mock = HAMockConnection()
        let cache = EntitySnapshotCache(fileURL: FileManager.default.temporaryDirectory.appending(path: "evershelf-\(UUID()).json"))
        return (HassConnection(server: .example, store: EntityStore(), snapshotCache: cache, connection: mock), mock)
    }

    private func pendingRequest(_ mock: HAMockConnection) async throws -> HAMockConnection.PendingRequest {
        for _ in 0..<1_000 where mock.pendingRequests.isEmpty { try? await Task.sleep(for: .milliseconds(10)) }
        return try #require(mock.pendingRequests.first)
    }

    @Test func connectionSendsReturnResponseAndReadsTheResponse() async throws {
        let (connection, mock) = makeConnection()
        let call = Task { try await connection.callServiceForResponse("evershelf", "list_inventory", data: ["q": "milk"]) }
        let request = try await pendingRequest(mock)
        #expect(request.request.type == .webSocket("call_service"))
        #expect(request.request.data["domain"] as? String == "evershelf")
        #expect(request.request.data["service"] as? String == "list_inventory")
        #expect(request.request.data["return_response"] as? Bool == true)
        #expect((request.request.data["service_data"] as? [String: Any])?["q"] as? String == "milk")
        #expect(!request.request.shouldRetry)
        request.completion(.success(HAData(value: ["response": ["source": "x"]])))
        #expect(try await call.value == .object(["source": .string("x")]))
    }

    @Test func connectionWithoutResponseIsNull() async throws {
        let (connection, mock) = makeConnection()
        let call = Task { try await connection.callServiceForResponse("evershelf", "delete_inventory", data: [:]) }
        let request = try await pendingRequest(mock)
        request.completion(.success(.empty))
        #expect(try await call.value == .null)
    }

    @Test func connectionFailureThrows() async throws {
        let (connection, mock) = makeConnection()
        let call = Task { try await connection.callServiceForResponse("evershelf", "list_inventory", data: [:]) }
        let request = try await pendingRequest(mock)
        request.completion(.failure(.internal(debugDescription: "offline")))
        await #expect(throws: HAError.self) { _ = try await call.value }
    }
}
