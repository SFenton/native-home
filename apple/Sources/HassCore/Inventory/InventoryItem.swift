import Foundation

// MARK: - Locations

/// An EverShelf storage location (`location` in EverShelf's API; Italian keys from upstream).
///
/// Web: `EVERSHELF_ADD_LOCATIONS` and `ScanItemCameraSheet.tsx` `EVERSHELF_LOCATIONS`
/// (`ha-sfenton-react-dash@9ac2a46:src/components/hass/EverShelfInventoryPanel.tsx:148`).
public enum StorageLocation: String, CaseIterable, Hashable, Sendable, Identifiable {
    case pantry = "dispensa"
    case fridge = "frigo"
    case freezer
    case spiceRack = "spice_rack"
    case cabinet
    /// EverShelf's "other" bucket, offered only when adding an item.
    case library = "altro"

    public var id: String { rawValue }

    /// Locations that hold food a page can list and an item can be restocked into.
    public static let storage: [StorageLocation] = [.pantry, .fridge, .freezer, .spiceRack, .cabinet]

    /// Title case, e.g. `Spice Rack`.
    public var title: String {
        switch self {
        case .pantry: "Pantry"
        case .fridge: "Fridge"
        case .freezer: "Freezer"
        case .spiceRack: "Spice Rack"
        case .cabinet: "Cabinet"
        case .library: "Library"
        }
    }

    /// In a sentence, e.g. "the spice rack".
    public var phrase: String { title.lowercased() }
}

// MARK: - Inventory spaces (pages)

/// One of the six inventory pages (web `EVERSHELF_INVENTORY_PAGES`, `DashboardViewPage.tsx:1814`).
public enum InventorySpace: String, CaseIterable, Hashable, Sendable, Identifiable {
    case allFood = "all-food"
    case pantry
    case fridge
    case freezer
    case spiceRack = "spice-rack"
    case cabinet

    public var id: String { rawValue }

    /// The location this page lists; `nil` lists everything.
    public var location: StorageLocation? {
        switch self {
        case .allFood: nil
        case .pantry: .pantry
        case .fridge: .fridge
        case .freezer: .freezer
        case .spiceRack: .spiceRack
        case .cabinet: .cabinet
        }
    }

    /// Page title.
    public var title: String { location?.title ?? "All Food" }

    /// Where a deleted or restocked item lives in copy. The web calls the all-food page's rows "library"
    /// (`LOCATION_DELETE_LABELS.all`), and a row's own location wins when it reports one.
    public var phrase: String { location?.phrase ?? "library" }

    /// The web's icon (`everShelfFood.ts`).
    public var mdiIcon: String {
        switch self {
        case .allFood: "mdi:food-variant"
        case .pantry: "mdi:food-fork-drink"
        case .fridge: "mdi:fridge"
        case .freezer: "mdi:snowflake"
        case .spiceRack: "mdi:shaker-outline"
        case .cabinet: "mdi:cupboard"
        }
    }

    /// Where Scan Item starts: the page's own location, else the pantry (`EVERSHELF_DEFAULT_LOCATION`).
    public var defaultScanLocation: StorageLocation { location ?? .pantry }

    /// Whether Scan Item is defaulting to this page's location (changes the hint copy).
    public var hasOwnScanLocation: Bool { location != nil }
}

// MARK: - Item

/// One EverShelf inventory row as `evershelf.list_inventory` returns it.
///
/// Every field is parsed leniently, like the web: numbers may arrive as strings, and taxonomy search
/// results may carry only `inventory_ids` instead of one `inventory_id`.
public struct InventoryItem: Hashable, Sendable {
    /// `inventory_id` (or `id`) when positive.
    public var inventoryId: Int?
    /// Rows an aggregated search result stands for.
    public var inventoryIds: [Int]
    /// Trimmed name, or `Untitled item`.
    public var name: String
    /// Positive stock, else 1.
    public var quantity: Double
    /// e.g. `pz`.
    public var unit: String?
    /// One of the five storage locations, when reported.
    public var location: StorageLocation?
    /// `YYYY-MM-DD…` as stored (expiry_date, expiration_date or expires_at).
    public var expiryDate: String?
    /// Prepared units form their own batch.
    public var preparedFood: Bool
    /// Part of EverShelf's batch identity when restocking.
    public var vacuumSealed: Bool
    /// The product this row stocks.
    public var productId: Int?
    /// Lowercased name, brand, category, shopping name and canonical ingredient terms, for the local
    /// search fallback (`fallbackSearchText`).
    public var searchText: String

    /// Creates an item directly (tests and fixtures).
    public init(
        inventoryId: Int?, inventoryIds: [Int] = [], name: String, quantity: Double = 1, unit: String? = nil,
        location: StorageLocation? = nil, expiryDate: String? = nil, preparedFood: Bool = false,
        vacuumSealed: Bool = false, productId: Int? = nil, searchText: String? = nil
    ) {
        self.inventoryId = inventoryId
        self.inventoryIds = inventoryIds
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.location = location
        self.expiryDate = expiryDate
        self.preparedFood = preparedFood
        self.vacuumSealed = vacuumSealed
        self.productId = productId
        self.searchText = searchText ?? name.lowercased()
    }

    /// Parses a row object; returns `nil` for anything that isn't an object.
    public init?(json: JSONValue) {
        guard case let .object(fields) = json else { return nil }
        func text(_ key: String) -> String? { fields[key]?.looseString.flatMap(Self.compact) }
        // JavaScript `inventory_id ?? id`: a null inventory_id falls back to id.
        let rowId = fields["inventory_id"].flatMap { $0 == .null ? nil : $0 } ?? fields["id"]
        inventoryId = rowId?.positiveInt
        inventoryIds = fields["inventory_ids"]?.array?.compactMap(\.positiveInt) ?? []
        name = text("name") ?? "Untitled item"
        let quantity = fields["quantity"]?.finiteNumber ?? 0
        self.quantity = quantity.isFinite && quantity > 0 ? quantity : 1
        unit = text("unit")
        location = text("location").flatMap(StorageLocation.init(rawValue:)).flatMap { StorageLocation.storage.contains($0) ? $0 : nil }
        expiryDate = text("expiry_date") ?? text("expiration_date") ?? text("expires_at")
        preparedFood = fields["prepared_food"].map(Self.isPreparedFlag) ?? false
        vacuumSealed = fields["vacuum_sealed"].map(Self.isTruthy) ?? false
        productId = fields["product_id"]?.positiveInt
        let canonical = fields["canonical_ingredients"]?.array?.flatMap { term in
            ["name", "slug", "role"].compactMap { term[$0]?.string }
        } ?? []
        searchText = ([name, text("brand"), text("category"), text("shopping_name")].compactMap { $0 } + canonical)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .joined(separator: " ")
            .lowercased()
    }

    /// Lowercased name: rows with the same name show as one card per page.
    public var groupKey: String { name.lowercased() }

    // MARK: - Lenient flags

    static func compact(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// `prepared_food`: only `true`, `1` or `"1"` (`itemPreparedFood`).
    static func isPreparedFlag(_ value: JSONValue) -> Bool {
        switch value {
        case let .bool(flag): flag
        case let .number(number): number == 1
        case let .string(text): text == "1"
        default: false
        }
    }

    /// `vacuum_sealed`: any non-empty string other than `0`/`false`, or a truthy value (`itemVacuumSealed`).
    static func isTruthy(_ value: JSONValue) -> Bool {
        switch value {
        case let .bool(flag): return flag
        case let .number(number): return number != 0
        case let .string(text):
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            return !trimmed.isEmpty && trimmed != "0" && trimmed.lowercased() != "false"
        case .array, .object: return true
        case .null: return false
        }
    }
}

// MARK: - Lenient JSON

extension JSONValue {
    /// A string, or a number written out (`12`, `2.5`).
    var looseString: String? {
        switch self {
        case let .string(text): text
        case let .number(value): InventoryFormat.quantity(value)
        default: nil
        }
    }

    /// A positive whole number.
    var positiveInt: Int? {
        guard let number = finiteNumber, number > 0, number < Double(Int.max) else { return nil }
        return Int(number)
    }
}
