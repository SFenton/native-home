import Foundation

// MARK: - Display item

/// One card on an inventory page: every row with the same name, shown once with the total stock and the
/// soonest expiration (web `groupedInventoryItems`, `EverShelfInventoryPanel.tsx:256`).
public struct InventoryDisplayItem: Hashable, Sendable, Identifiable {
    /// The rows behind the card, in server order.
    public var rows: [InventoryItem]

    /// Grouping key (lowercased name); unique per page.
    public var id: String { rows[0].groupKey }
    /// Name of the first row.
    public var name: String { rows[0].name }
    /// Total stock across rows.
    public var quantity: Double { rows.reduce(0) { $0 + $1.quantity } }

    /// The soonest parseable expiry across rows.
    public func soonestExpiry(_ calendar: InventoryCalendar) -> String? {
        rows.compactMap { row in row.expiryDate.flatMap { date in calendar.date(fromISO: date).map { (date, $0) } } }
            .min { $0.1 < $1.1 }?.0
    }

    /// The card's quantity, shown only above one (`itemQuantity`).
    public var shownQuantity: Double? { quantity > 1 ? quantity : nil }
}

// MARK: - Batches

/// Rows that share location, expiry and prepared state: one editable unit in the item editor
/// (web `inventoryBatches`, `EverShelfInventoryPanel.tsx:781`).
public struct InventoryBatch: Hashable, Sendable, Identifiable {
    /// One row's id and stock.
    public struct Row: Hashable, Sendable {
        public var inventoryId: Int
        public var quantity: Double
        public init(inventoryId: Int, quantity: Double) {
            self.inventoryId = inventoryId
            self.quantity = quantity
        }
    }

    /// `location␀expiry␀prepared`.
    public var key: String
    /// `YYYY-MM-DD` or empty.
    public var expiryDate: String
    /// e.g. "fridge".
    public var locationPhrase: String
    public var preparedFood: Bool
    public var quantity: Double
    /// Addressable rows; empty while projected.
    public var rows: [Row]
    /// A representative row (restocking repeats its identity).
    public var sample: InventoryItem
    /// Every row has an id, so the batch can be edited.
    public var addressable: Bool

    /// The inventory ids of this batch's rows.
    public var rowIds: Set<Int> { Set(rows.map(\.inventoryId)) }

    public var id: String { key }

    /// The batch key for a row (`itemBatchKey`).
    public static func key(for item: InventoryItem) -> String {
        [item.location?.rawValue ?? "", item.expiryDate ?? "", item.preparedFood ? "1" : "0"].joined(separator: "\u{0}")
    }
}

// MARK: - Modes

/// Sort fields (web `SORT_OPTIONS`).
public enum InventorySortMode: String, CaseIterable, Sendable, Identifiable {
    case title, expiry
    public var id: String { rawValue }
    public var title: String { self == .title ? "Title" : "Expiration Date" }
    public var subtitle: String { self == .title ? "Sort alphabetically by item name." : "Sort by the item expiration date." }
}

/// Sort direction (web `SORT_DIRECTION_DETAILS`).
public enum InventorySortDirection: String, CaseIterable, Sendable, Identifiable {
    case ascending, descending
    public var id: String { rawValue }
    public var title: String { self == .ascending ? "Ascending" : "Descending" }
    public var hint: String { self == .ascending ? "A–Z, soonest first" : "Z–A, latest first" }
}

/// Expiry filters (web `FILTER_OPTIONS`).
public enum InventoryFilterMode: String, CaseIterable, Sendable, Identifiable {
    case all, expired, week, month, sixMonths = "six-months", year, noExpiration = "no-expiration"
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: "All Items"
        case .expired: "Expired"
        case .week: "Expiring Within a Week"
        case .month: "Expiring Within a Month"
        case .sixMonths: "Expiring Within 6 Months"
        case .year: "Expiring Within a Year"
        case .noExpiration: "No Expiration Date"
        }
    }

    public var subtitle: String {
        switch self {
        case .all: "Show everything in this location."
        case .expired: "Only items past their expiration date."
        case .week: "Items expiring in the next 7 days."
        case .month: "Items expiring in the next 30 days."
        case .sixMonths: "Items expiring in the next 6 months."
        case .year: "Items expiring in the next year."
        case .noExpiration: "Items without a usable expiration date."
        }
    }

    /// Whether an item `days` from expiry (`nil` = no date) passes (`filterInventoryItems`).
    public func includes(days: Int?) -> Bool {
        if self == .all { return true }
        guard let days else { return self == .noExpiration }
        switch self {
        case .all: return true
        case .noExpiration: return false
        case .expired: return days < 0
        case .week: return (0...7).contains(days)
        case .month: return (0...30).contains(days)
        case .sixMonths: return (0...183).contains(days)
        case .year: return (0...365).contains(days)
        }
    }
}

// MARK: - Expiry label

/// A row's expiry text and tone (`expiryInfo`).
public struct ExpiryInfo: Hashable, Sendable {
    public enum Tone: Sendable { case expired, soon }
    public var label: String
    public var tone: Tone?
}

/// One delete call: the whole row, or `quantity` of it.
public struct InventoryDeleteStep: Hashable, Sendable {
    public var inventoryId: Int
    public var quantity: Double?
    public init(inventoryId: Int, quantity: Double? = nil) {
        self.inventoryId = inventoryId
        self.quantity = quantity
    }
}

// MARK: - Catalog

/// The inventory pages' pure rules, ported from `EverShelfInventoryPanel.tsx`.
public enum InventoryCatalog {
    /// Most a batch can hold in the editor (`INVENTORY_QUANTITY_MAX`).
    public static let maxQuantity: Double = 999
    /// Shown on a card whose rows have different dates (`MULTIPLE_EXPIRATION_DATES_LABEL`).
    public static let multipleDatesLabel = "Multiple Expiration Dates"

    // MARK: Grouping

    /// Rows grouped into cards by lowercased name, in first-seen order.
    public static func displayItems(_ items: [InventoryItem]) -> [InventoryDisplayItem] {
        var groups: [String: [InventoryItem]] = [:]
        var order: [String] = []
        for item in items {
            if groups[item.groupKey] == nil { order.append(item.groupKey) }
            groups[item.groupKey, default: []].append(item)
        }
        return order.map { InventoryDisplayItem(rows: groups[$0]!) }
    }

    /// The batches of a card, soonest first, undated last, ties by location.
    public static func batches(_ item: InventoryDisplayItem?, fallbackPhrase: String, calendar: InventoryCalendar) -> [InventoryBatch] {
        guard let item else { return [] }
        var batches: [String: InventoryBatch] = [:]
        var order: [String] = []
        for row in item.rows {
            let key = InventoryBatch.key(for: row)
            let addressable = row.inventoryId.map { [InventoryBatch.Row(inventoryId: $0, quantity: row.quantity)] } ?? []
            if var existing = batches[key] {
                existing.addressable = existing.addressable && row.inventoryId != nil
                existing.quantity += row.quantity
                existing.rows += addressable
                batches[key] = existing
                continue
            }
            order.append(key)
            batches[key] = InventoryBatch(
                key: key, expiryDate: row.expiryDate ?? "", locationPhrase: row.location?.phrase ?? fallbackPhrase,
                preparedFood: row.preparedFood, quantity: row.quantity, rows: addressable, sample: row,
                addressable: row.inventoryId != nil
            )
        }
        func time(_ batch: InventoryBatch) -> Date? { batch.expiryDate.isEmpty ? nil : calendar.date(fromISO: batch.expiryDate) }
        return order.compactMap { batches[$0] }.enumerated().sorted { lhs, rhs in
            let (left, right) = (time(lhs.element), time(rhs.element))
            if left == right {
                let order = lhs.element.locationPhrase.compare(rhs.element.locationPhrase)
                return order == .orderedSame ? lhs.offset < rhs.offset : order == .orderedAscending
            }
            guard let left else { return false }
            guard let right else { return true }
            return left < right
        }.map(\.element)
    }

    /// A stable fingerprint of batch keys and stock, to tell when the server confirms a projection
    /// (`inventoryBatchToken`).
    public static func token(_ batches: [InventoryBatch]) -> String {
        batches.map { "\($0.key)=\(InventoryFormat.quantity($0.quantity))" }.sorted().joined(separator: "|")
    }

    // MARK: Filter and sort

    /// Filters then sorts cards (`visibleInventoryItems`). Undated cards sort last by expiry in both directions.
    public static func visible(
        _ items: [InventoryDisplayItem], sort: InventorySortMode, direction: InventorySortDirection,
        filter: InventoryFilterMode, calendar: InventoryCalendar
    ) -> [InventoryDisplayItem] {
        let dated = items.map { item in (item, item.soonestExpiry(calendar).flatMap(calendar.date(fromISO:))) }
        let filtered = dated.filter { filter.includes(days: $0.1.map(calendar.days(until:))) }
        let ascending = direction == .ascending
        func byName(_ left: InventoryDisplayItem, _ right: InventoryDisplayItem) -> ComparisonResult {
            left.name.compare(right.name, options: [.caseInsensitive, .diacriticInsensitive])
        }
        return filtered.sorted { lhs, rhs in
            if sort == .expiry {
                switch (lhs.1, rhs.1) {
                case (nil, nil): return byName(lhs.0, rhs.0) == .orderedAscending
                case (nil, _): return false
                case (_, nil): return true
                case let (left?, right?) where left != right: return ascending ? left < right : left > right
                default: break
                }
            }
            let order = byName(lhs.0, rhs.0)
            return ascending ? order == .orderedAscending : order == .orderedDescending
        }.map(\.0)
    }

    // MARK: Copy

    /// `Expires Oct 14, 2026` (orange within a week) or `Expired Oct 9, 2026` (red), else `No Expiration Date`.
    public static func expiryInfo(_ value: String?, calendar: InventoryCalendar) -> ExpiryInfo {
        guard let value, let date = calendar.date(fromISO: value) else { return ExpiryInfo(label: "No Expiration Date") }
        let days = calendar.days(until: date)
        if days < 0 { return ExpiryInfo(label: "Expired \(calendar.displayDate(date))", tone: .expired) }
        return ExpiryInfo(label: "Expires \(calendar.displayDate(date))", tone: days < 7 ? .soon : nil)
    }

    /// `Quantity 3 · Expires …`, or `Multiple Expiration Dates` when batches differ (`rowSubtitle`).
    public static func rowSubtitle(_ expiry: ExpiryInfo, quantity: Double?, batchCount: Int) -> String {
        let stock = quantity.map { "Quantity \(InventoryFormat.quantity($0))" }
        let label = batchCount > 1 ? multipleDatesLabel : expiry.label
        return [stock, label].compactMap { $0 }.joined(separator: " · ")
    }

    /// Words appended to an item's name so each batch's controls are unique (`batchQualifier`):
    /// ` expiring Oct 14, 2026`, ` without an expiration date`, plus ` prepared`.
    public static func batchQualifier(_ batch: InventoryBatch, multipleBatches: Bool, calendar: InventoryCalendar) -> String {
        guard multipleBatches else { return batch.preparedFood ? " prepared" : "" }
        let label = calendar.date(fromISO: batch.expiryDate).map(calendar.displayDate)
        let expiry = label.map { " expiring \($0)" } ?? " without an expiration date"
        return batch.preparedFood ? "\(expiry) prepared" : expiry
    }

    /// `Saving adds 2 items to the fridge.` (`quantityChangeHint`).
    public static func quantityChangeHint(delta: Double, phrase: String) -> String {
        let amount = InventoryFormat.quantity(abs(delta))
        let noun = abs(delta) == 1 ? "item" : "items"
        return delta > 0 ? "Saving adds \(amount) \(noun) to the \(phrase)." : "Saving removes \(amount) \(noun) from the \(phrase)."
    }

    /// The empty or error state an inventory page shows (`EverShelfInventoryPanel` render).
    public static func emptyState(
        title: String, error: String?, loadedCount: Int, visibleCount: Int, query: String, filterActive: Bool
    ) -> (title: String, description: String)? {
        let searchDescription = filterActive
            ? "Try a different search, clear the selected filter, or clear the search to show all items."
            : "Try a different search or clear the search to show all items."
        if let error {
            let description = error == "Unable to load inventory"
                ? "Try again in a moment, or scan an item while \(title.lowercased()) is unavailable."
                : error.replacingOccurrences(of: "EverShelf is unavailable", with: "\(title) is unavailable")
            return ("Unable to Load \(title)", description)
        }
        if loadedCount == 0 {
            return query.isEmpty ? ("No Items Found", "Scan an item to add it to your \(title.lowercased()).") : ("No Matching Items", searchDescription)
        }
        guard visibleCount == 0 else { return nil }
        return ("No Matching Items", query.isEmpty ? "Try a different filter, or clear it to show all items." : searchDescription)
    }

    // MARK: Stock changes

    /// Spreads a removal over rows, smallest first, so whole rows go before one is split
    /// (`inventoryDecreaseSteps`).
    public static func decreaseSteps(_ rows: [InventoryBatch.Row], amount: Double) -> (steps: [InventoryDeleteStep], remaining: [InventoryBatch.Row]) {
        var steps: [InventoryDeleteStep] = []
        var remaining: [InventoryBatch.Row] = []
        var left = amount
        for row in rows.sorted(by: { $0.quantity < $1.quantity }) {
            if left <= 0 {
                remaining.append(row)
            } else if row.quantity <= left {
                steps.append(InventoryDeleteStep(inventoryId: row.inventoryId))
                left -= row.quantity
            } else {
                steps.append(InventoryDeleteStep(inventoryId: row.inventoryId, quantity: left))
                remaining.append(InventoryBatch.Row(inventoryId: row.inventoryId, quantity: row.quantity - left))
                left = 0
            }
        }
        return (steps, remaining)
    }

    /// Spreads a prepared-food change over rows, smallest first (`inventoryPreparedSteps`).
    public static func preparedSteps(_ rows: [InventoryBatch.Row], amount: Double) -> [InventoryBatch.Row] {
        var steps: [InventoryBatch.Row] = []
        var left = amount
        for row in rows.sorted(by: { $0.quantity < $1.quantity }) where left > 0 {
            let take = min(row.quantity, left)
            steps.append(InventoryBatch.Row(inventoryId: row.inventoryId, quantity: take))
            left -= take
        }
        return steps
    }

    /// Batches after a delete, before the server confirms (`inventoryBatchesAfterDelete`).
    public static func batches(_ batches: [InventoryBatch], after steps: [InventoryDeleteStep]) -> [InventoryBatch] {
        let byId = Dictionary(steps.map { ($0.inventoryId, $0) }, uniquingKeysWith: { first, _ in first })
        return batches.compactMap { batch in
            let rows = batch.rows.compactMap { row -> InventoryBatch.Row? in
                guard let step = byId[row.inventoryId] else { return row }
                guard let quantity = step.quantity else { return nil }
                let left = row.quantity - quantity
                return left > 0 ? InventoryBatch.Row(inventoryId: row.inventoryId, quantity: left) : nil
            }
            guard !rows.isEmpty else { return nil }
            var next = batch
            next.rows = rows
            next.quantity = rows.reduce(0) { $0 + $1.quantity }
            return next
        }
    }

    /// Rows after deletes, before the server confirms (`removeDeletedItems`).
    public static func items(_ items: [InventoryItem], after steps: [InventoryDeleteStep]) -> [InventoryItem] {
        let byId = Dictionary(steps.map { ($0.inventoryId, $0) }, uniquingKeysWith: { first, _ in first })
        return items.compactMap { item in
            guard let id = item.inventoryId, let step = byId[id] else { return item }
            guard let quantity = step.quantity else { return nil }
            var next = item
            next.quantity -= quantity
            return next.quantity > 0 ? next : nil
        }
    }

    /// Batches after moving `steps` into or out of prepared food, shown until the server confirms
    /// (`inventoryBatchesAfterPreparedToggle`). Projected batches are not addressable.
    public static func batches(_ batches: [InventoryBatch], preparing source: InventoryBatch, steps: [InventoryBatch.Row], to prepared: Bool) -> [InventoryBatch] {
        let moved = steps.reduce(0) { $0 + $1.quantity }
        var sample = source.sample
        sample.preparedFood = prepared
        let destinationKey = InventoryBatch.key(for: sample)
        let existing = batches.first { $0.key == destinationKey }
        let destination = InventoryBatch(
            key: destinationKey, expiryDate: source.expiryDate, locationPhrase: source.locationPhrase,
            preparedFood: prepared, quantity: (existing?.quantity ?? 0) + moved, rows: [],
            sample: existing?.sample ?? sample, addressable: false
        )
        var remainder = source
        remainder.quantity -= moved
        remainder.rows = []
        remainder.addressable = false
        return batches.flatMap { batch -> [InventoryBatch] in
            if batch.key == source.key {
                let kept = remainder.quantity > 0 ? [remainder] : []
                return existing == nil ? kept + [destination] : kept
            }
            return batch.key == destinationKey ? [destination] : [batch]
        }
    }

    /// `add_scanned_item` data that restocks an existing batch: EverShelf merges into a batch only when
    /// product, location, expiry and sealed state match (`inventoryAddServiceData`).
    public static func restockData(_ sample: InventoryItem, quantity: Double, expiryDate: String) -> [String: JSONValue] {
        var data: [String: JSONValue] = [
            "inventory_prepared_food": .bool(sample.preparedFood),
            "name": .string(sample.name),
            "quantity": .number(quantity),
            "vacuum_sealed": .bool(sample.vacuumSealed),
        ]
        if let productId = sample.productId { data["product_id"] = .number(Double(productId)) }
        if let location = sample.location { data["location"] = .string(location.rawValue) }
        if !expiryDate.isEmpty { data["expiry_date"] = .string(expiryDate) }
        if let unit = sample.unit { data["unit"] = .string(unit) }
        return data
    }

    // MARK: Search

    /// Search terms of two or more characters (`fallbackSearchTokens`).
    public static func searchTokens(_ query: String) -> [String] {
        query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init).filter { $0.count >= 2 }
    }

    /// Local filter used when the server didn't confirm it ran the search (`fallbackFilterSearchResults`).
    public static func locallySearched(_ items: [InventoryItem], query: String) -> [InventoryItem] {
        let tokens = searchTokens(query)
        guard !tokens.isEmpty else { return items }
        return items.filter { item in tokens.allSatisfy { item.searchText.contains($0) } }
    }
}
