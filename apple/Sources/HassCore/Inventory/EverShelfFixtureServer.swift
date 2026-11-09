#if DEBUG
import Foundation
import Observation

/// An in-memory stand-in for Home Assistant's EverShelf services, for tests, the debug gallery and
/// screenshots. It answers the same services the inventory feature calls, with EverShelf's batch rules
/// (stock merges into a row only when product, location, expiry, prepared and sealed state match).
///
/// Debug builds only. Its data is synthetic, not a copy of the household's inventory.
@MainActor
@Observable
public final class EverShelfFixtureServer: EverShelfCalling {
    /// One stored row.
    public struct Row: Equatable, Sendable {
        public var id: Int
        public var name: String
        public var quantity: Double
        public var location: StorageLocation
        public var expiryDate: String?
        public var preparedFood = false
        public var productId: Int?
        public var brand: String?

        public init(id: Int, name: String, quantity: Double, location: StorageLocation, expiryDate: String?, preparedFood: Bool = false, productId: Int? = nil, brand: String? = nil) {
            self.id = id
            self.name = name
            self.quantity = quantity
            self.location = location
            self.expiryDate = expiryDate
            self.preparedFood = preparedFood
            self.productId = productId
            self.brand = brand
        }
    }

    /// Stored rows.
    public var rows: [Row]
    /// Every call, as `domain.service key=value …` (keys sorted).
    public private(set) var calls: [String] = []
    /// The last call, for the gallery's debug line.
    public var lastCall: String { calls.last ?? "None" }
    /// Services that throw (e.g. `evershelf.list_inventory`).
    public var failing: Set<String> = []
    /// Delay before each answer, like a real round trip.
    public var latency: Duration = .zero
    /// When set, `list_inventory` with `q` answers without confirming the search (exercises the local fallback).
    public var unconfirmedSearch = false
    /// When set, `list_inventory` with `q` answers with one aggregated entry per product (`inventory_ids`).
    public var aggregatedSearch = false
    /// Barcodes `resolve_barcode` knows.
    public var products: [String: [String: JSONValue]] = [
        "0123456789012": ["id": .number(501), "name": .string("Greek Yogurt"), "brand": .string("Fixture Dairy"), "category": .string("Dairy")],
    ]
    /// What `read_expiry_image` answers.
    public var expiryReading: JSONValue = .object(["success": .bool(true), "expiry_date": .string("2030-01-15")])
    /// What `suggest_location` answers.
    public var suggestion: JSONValue = .object(["success": .bool(true), "location": .string("frigo"), "source": .string("history_barcode")])

    private var nextId: Int

    /// Creates a server with rows.
    public init(rows: [Row]) {
        self.rows = rows
        nextId = (rows.map(\.id).max() ?? 0) + 1
    }

    /// A household-shaped sample with expired, soon, later, undated, multi-batch and prepared items;
    /// dates are relative to `calendar`'s today so screenshots look the same any day.
    public static func sample(calendar: InventoryCalendar = .current) -> EverShelfFixtureServer {
        func day(_ offset: Int) -> String {
            calendar.isoString(calendar.calendar.date(byAdding: .day, value: offset, to: calendar.today) ?? calendar.today)
        }
        return EverShelfFixtureServer(rows: [
            Row(id: 1, name: "Black Beans", quantity: 2, location: .pantry, expiryDate: day(240), productId: 11),
            Row(id: 2, name: "Black Beans", quantity: 1, location: .pantry, expiryDate: day(420), productId: 11),
            Row(id: 3, name: "Spaghetti", quantity: 1, location: .pantry, expiryDate: day(300), productId: 12),
            Row(id: 4, name: "Jasmine Rice", quantity: 1, location: .pantry, expiryDate: day(-3), productId: 13),
            Row(id: 5, name: "Honey", quantity: 1, location: .pantry, expiryDate: nil, productId: 14),
            Row(id: 6, name: "Whole Milk", quantity: 1, location: .fridge, expiryDate: day(3), productId: 21),
            Row(id: 7, name: "Eggs", quantity: 12, location: .fridge, expiryDate: day(18), productId: 22),
            Row(id: 8, name: "Chicken Soup", quantity: 2, location: .fridge, expiryDate: day(4), preparedFood: true, productId: 23),
            Row(id: 9, name: "Frozen Peas", quantity: 1, location: .freezer, expiryDate: day(150), productId: 31),
            Row(id: 10, name: "Smoked Paprika", quantity: 1, location: .spiceRack, expiryDate: day(500), productId: 41),
            Row(id: 11, name: "Peanut Butter", quantity: 1, location: .cabinet, expiryDate: day(60), productId: 51),
        ])
    }

    // MARK: - EverShelfCalling

    public func callService(_ domain: String, _ service: String, data: [String: any Sendable]) async throws {
        _ = try await respond(domain, service, data)
    }

    public func callServiceForResponse(_ domain: String, _ service: String, data: [String: any Sendable]) async throws -> JSONValue {
        try await respond(domain, service, data)
    }

    /// Fixture failure.
    public struct Failure: LocalizedError {
        public var errorDescription: String?
    }

    private func respond(_ domain: String, _ service: String, _ raw: [String: any Sendable]) async throws -> JSONValue {
        let data = raw.mapValues { JSONValue(any: $0) }
        calls.append(Self.describe(domain, service, data))
        if latency > .zero { try? await Task.sleep(for: latency) }
        if failing.contains("\(domain).\(service)") { throw Failure(errorDescription: "EverShelf is unavailable") }
        switch (domain, service) {
        case ("evershelf", "list_inventory"): return list(data)
        case ("evershelf", "delete_inventory"): delete(data)
        case ("evershelf", "update_inventory_item"): moveOne(data)
        case ("evershelf", "add_scanned_item"): return add(data)
        case ("evershelf", "set_inventory_prepared_food"): prepare(data)
        case ("evershelf", "resolve_barcode"):
            let barcode = data["barcode"]?.string ?? ""
            guard let product = products[barcode] else { return .object(["found": .bool(false), "barcode": .string(barcode)]) }
            return .object(["found": .bool(true), "barcode": .string(barcode), "product": .object(product)])
        case ("evershelf", "prepare_scanned_product"):
            let id = data["product_id"]?.positiveInt ?? 900 + calls.count
            return .object(["success": .bool(true), "id": .number(Double(id)), "product_fingerprint": .string(String(repeating: "a", count: 64))])
        case ("evershelf", "suggest_location"): return suggestion
        case ("evershelf", "read_expiry_image"): return expiryReading
        default: break
        }
        return .null
    }

    // MARK: - Services

    private func list(_ data: [String: JSONValue]) -> JSONValue {
        let location = data["location"]?.string.flatMap(StorageLocation.init(rawValue:))
        let query = (data["q"] ?? data["search"])?.string?.trimmingCharacters(in: .whitespaces) ?? ""
        var matched = rows.filter { location == nil || $0.location == location }
        if !query.isEmpty, !unconfirmedSearch {
            let tokens = InventoryCatalog.searchTokens(query)
            matched = matched.filter { row in tokens.allSatisfy { "\(row.name) \(row.brand ?? "")".lowercased().contains($0) } }
        }
        var inventory = matched.map(Self.json)
        if aggregatedSearch, !query.isEmpty {
            let names = matched.map(\.name).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            inventory = names.map { name in
                .object(["name": .string(name), "inventory_ids": .array(matched.filter { $0.name == name }.map { .number(Double($0.id)) })])
            }
        }
        var response: [String: JSONValue] = ["inventory": .array(inventory)]
        if !query.isEmpty, !unconfirmedSearch {
            response["source"] = .string("ha_sensor_product_search")
            response["search"] = .string(query)
        }
        return .object(response)
    }

    private func delete(_ data: [String: JSONValue]) {
        guard let id = data["inventory_id"]?.positiveInt, let index = rows.firstIndex(where: { $0.id == id }) else { return }
        if let quantity = data["quantity"]?.finiteNumber, quantity < rows[index].quantity {
            rows[index].quantity -= quantity
        } else {
            rows.remove(at: index)
        }
    }

    private func moveOne(_ data: [String: JSONValue]) {
        guard let id = data["inventory_id"]?.positiveInt, let index = rows.firstIndex(where: { $0.id == id }) else { return }
        let date = data["expiry_date"]?.string.flatMap { $0.isEmpty ? nil : $0 }
        var moved = rows[index]
        moved.quantity = min(1, moved.quantity)
        moved.expiryDate = date
        rows[index].quantity -= moved.quantity
        if rows[index].quantity <= 0 { rows.remove(at: index) }
        merge(moved)
    }

    private func add(_ data: [String: JSONValue]) -> JSONValue {
        guard let name = data["name"]?.string, let location = data["location"]?.string.flatMap(StorageLocation.init(rawValue:)) else {
            return .object(["success": .bool(false), "message": .string("Missing name or location")])
        }
        let prepared = (data["prepared_food"] ?? data["inventory_prepared_food"]).map(InventoryItem.isPreparedFlag) ?? false
        let row = Row(id: 0, name: name, quantity: data["quantity"]?.finiteNumber ?? 1, location: location,
                      expiryDate: data["expiry_date"]?.string, preparedFood: prepared, productId: data["product_id"]?.positiveInt)
        merge(row)
        return .object(["success": .bool(true)])
    }

    private func prepare(_ data: [String: JSONValue]) {
        guard let id = data["inventory_id"]?.positiveInt, let index = rows.firstIndex(where: { $0.id == id }) else { return }
        let prepared = data["prepared_food"].map(InventoryItem.isPreparedFlag) ?? true
        let quantity = min(data["quantity"]?.finiteNumber ?? rows[index].quantity, rows[index].quantity)
        var moved = rows[index]
        moved.quantity = quantity
        moved.preparedFood = prepared
        rows[index].quantity -= quantity
        if rows[index].quantity <= 0 { rows.remove(at: index) }
        merge(moved)
    }

    /// Adds stock to the matching batch, or as a new row.
    private func merge(_ row: Row) {
        if let index = rows.firstIndex(where: {
            $0.name == row.name && $0.location == row.location && $0.expiryDate == row.expiryDate && $0.preparedFood == row.preparedFood
        }) {
            rows[index].quantity += row.quantity
            return
        }
        var next = row
        next.id = nextId
        nextId += 1
        rows.append(next)
    }

    static func json(_ row: Row) -> JSONValue {
        var fields: [String: JSONValue] = [
            "inventory_id": .number(Double(row.id)), "name": .string(row.name), "quantity": .number(row.quantity),
            "location": .string(row.location.rawValue), "prepared_food": .number(row.preparedFood ? 1 : 0),
            "unit": .string("pz"), "vacuum_sealed": .number(0),
        ]
        if let date = row.expiryDate { fields["expiry_date"] = .string(date) }
        if let productId = row.productId { fields["product_id"] = .number(Double(productId)) }
        if let brand = row.brand { fields["brand"] = .string(brand) }
        return .object(fields)
    }

    /// `domain.service key=value …`, keys sorted; long values (images) are shortened.
    static func describe(_ domain: String, _ service: String, _ data: [String: JSONValue]) -> String {
        let pairs = data.keys.sorted().map { key -> String in
            var value = data[key].map(describe) ?? ""
            if value.count > 40 { value = String(value.prefix(24)) + "…" }
            return "\(key)=\(value)"
        }
        return ([domain + "." + service] + pairs).joined(separator: " ")
    }

    static func describe(_ value: JSONValue) -> String {
        switch value {
        case let .string(text): text
        case let .number(number): InventoryFormat.quantity(number)
        case let .bool(flag): String(flag)
        case let .array(values): "[" + values.map(describe).joined(separator: ",") + "]"
        case .object: "{…}"
        case .null: "null"
        }
    }
}
#endif
