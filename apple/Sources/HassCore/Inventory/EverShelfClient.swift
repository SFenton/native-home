import Foundation

/// EverShelf's Home Assistant services, as the inventory pages, item editor and Scan Item use them.
///
/// Every mutation goes through Home Assistant (`evershelf.*`); the client never talks to EverShelf directly.
/// Service names and data mirror the web (`EverShelfInventoryPanel.tsx`, `ScanItemCameraSheet.tsx`).
@MainActor
public final class EverShelfClient {
    /// The grocery to-do list a shopping add also lands on (`HASS_GROCERY_LIST_ENTITY_ID`).
    public static var groceryListEntityId: String { ChoresConfig.groceryEntityId }

    /// A `list_inventory` answer.
    public struct ListResponse: Sendable, Equatable {
        public var items: [InventoryItem]
        /// The search the server says it ran.
        public var search: String?
        /// e.g. `ha_sensor_product_search` when the taxonomy search ran.
        public var source: String?
    }

    /// Error for a service that answered `success: false` or nothing at all.
    public struct Failure: LocalizedError, Equatable {
        public var message: String
        public var errorDescription: String? { message }
        public init(_ message: String) { self.message = message }
    }

    private let caller: any EverShelfCalling

    /// Creates a client over a connection (or a fixture server).
    public init(caller: any EverShelfCalling) {
        self.caller = caller
    }

    // MARK: - Inventory

    /// Lists rows, optionally in one location and through EverShelf's taxonomy search.
    public func listInventory(location: StorageLocation?, query: String = "") async throws -> ListResponse {
        var data: [String: any Sendable] = [:]
        if let location { data["location"] = location.rawValue }
        if !query.isEmpty { data["q"] = query }
        let payload = Self.payload(try await caller.callServiceForResponse("evershelf", "list_inventory", data: data))
        return ListResponse(
            items: payload["inventory"]?.array?.compactMap(InventoryItem.init(json:)) ?? [],
            search: payload["search"]?.string,
            source: payload["source"]?.string
        )
    }

    /// The rows a page shows for `query`: the server's search when it confirms it ran that search, else a
    /// local filter (`inventoryItemsFromSearchResponse`), with aggregated search hits expanded into rows.
    public func pageItems(location: StorageLocation?, query: String) async throws -> [InventoryItem] {
        let response = try await listInventory(location: location, query: query)
        let confirmed = query.isEmpty || (response.source == "ha_sensor_product_search" && response.search?.trimmingCharacters(in: .whitespaces) == query)
        let items = confirmed ? response.items : InventoryCatalog.locallySearched(response.items, query: query)
        return await expandingAggregates(items, location: location)
    }

    /// EverShelf's taxonomy search collapses a product's rows into one entry with `inventory_ids`; the row
    /// actions need the real rows, so those are read back from an unfiltered list (`resolvedInventoryItems`).
    /// Unresolvable entries stay as they are (their controls disable).
    public func expandingAggregates(_ items: [InventoryItem], location: StorageLocation?) async -> [InventoryItem] {
        guard items.contains(where: { $0.inventoryId == nil && !$0.inventoryIds.isEmpty }) else { return items }
        guard let all = try? await listInventory(location: location) else { return items }
        let byId = Dictionary(all.items.compactMap { item in item.inventoryId.map { ($0, item) } }, uniquingKeysWith: { first, _ in first })
        return items.flatMap { item -> [InventoryItem] in
            guard item.inventoryId == nil else { return [item] }
            let rows = item.inventoryIds.compactMap { byId[$0] }
            return rows.isEmpty ? [item] : rows
        }
    }

    /// Removes a row, or `quantity` of it.
    public func delete(_ step: InventoryDeleteStep) async throws {
        var data: [String: any Sendable] = ["inventory_id": step.inventoryId]
        if let quantity = step.quantity { data["quantity"] = Self.number(quantity) }
        try await caller.callService("evershelf", "delete_inventory", data: data)
    }

    /// Runs deletes one after another (EverShelf consolidates between them).
    public func delete(_ steps: [InventoryDeleteStep]) async throws {
        for step in steps { try await delete(step) }
    }

    /// Moves one unit of a row to a new expiry date (EverShelf applies date moves one item at a time).
    public func updateExpiry(inventoryId: Int, expiryDate: String) async throws {
        try await caller.callService("evershelf", "update_inventory_item", data: ["expiry_date": expiryDate, "inventory_id": inventoryId])
    }

    /// Adds stock to an existing batch (``InventoryCatalog/restockData(_:quantity:expiryDate:)``).
    public func restock(_ data: [String: JSONValue]) async throws {
        try await caller.callService("evershelf", "add_scanned_item", data: data.mapValues(\.foundationValue))
    }

    /// Marks `quantity` of a row as prepared food, or back.
    public func setPreparedFood(inventoryId: Int, prepared: Bool, quantity: Double) async throws {
        try await caller.callService("evershelf", "set_inventory_prepared_food", data: [
            "inventory_id": inventoryId, "prepared_food": prepared, "quantity": Self.number(quantity),
        ])
    }

    /// Adds an item to EverShelf's shopping list and Home Assistant's grocery list together.
    public func addToShoppingList(name: String, quantity: Double) async throws {
        try await caller.callService("evershelf", "add_to_shopping", data: ["name": name, "quantity": Self.number(quantity)])
        try await caller.callService("todo", "add_item", data: ["entity_id": Self.groceryListEntityId, "item": name])
    }

    // MARK: - Scan Item

    /// Looks a barcode up (`resolve_barcode`).
    public func resolveBarcode(_ barcode: String) async throws -> JSONValue {
        try await responding("resolve_barcode", ["barcode": .string(barcode)], empty: "Barcode lookup did not return a response.")
    }

    /// Commits the product being added before inventory is (`prepare_scanned_product`).
    public func prepareScannedProduct(_ data: [String: JSONValue]) async throws -> JSONValue {
        try await responding("prepare_scanned_product", data, empty: "The product could not be prepared.")
    }

    /// Asks EverShelf where a product is usually stored (`suggest_location`).
    public func suggestLocation(_ data: [String: JSONValue]) async throws -> JSONValue {
        try await responding("suggest_location", data, empty: "Storage suggestion did not return a response.")
    }

    /// Reads a printed expiry date from a JPEG data URL (`read_expiry_image`).
    public func readExpiryImage(dataURL: String) async throws -> JSONValue {
        try await responding("read_expiry_image", ["image": .string(dataURL)], empty: "Expiration reader did not return a response.")
    }

    /// Adds a scanned or typed item (`add_scanned_item`); throws when EverShelf says it failed.
    public func addScannedItem(_ data: [String: JSONValue], location: StorageLocation) async throws {
        let payload = try await responding("add_scanned_item", data, empty: "Could not add this item to \(location.title).")
        if payload["success"]?.bool == false {
            throw Failure(payload["message"]?.string ?? payload["error"]?.string ?? "Could not add this item to \(location.title).")
        }
    }

    // MARK: - Private

    private func responding(_ service: String, _ data: [String: JSONValue], empty: String) async throws -> JSONValue {
        let payload = Self.payload(try await caller.callServiceForResponse("evershelf", service, data: data.mapValues(\.foundationValue)))
        guard case .object = payload else { throw Failure(empty) }
        return payload
    }

    /// Unwraps EverShelf's optional `service_response` envelope (`serviceResponsePayload`).
    static func payload(_ response: JSONValue) -> JSONValue {
        if let inner = response["service_response"], case .object = inner { return inner }
        return response
    }

    /// Whole numbers go as `Int` so the service schema's integer fields accept them.
    static func number(_ value: Double) -> any Sendable {
        value == value.rounded() && abs(value) < 1e15 ? Int(value) : value
    }
}
