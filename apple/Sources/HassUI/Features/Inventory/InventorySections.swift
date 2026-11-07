import HassCore

/// One group of rows on an inventory page, under an optional header.
struct InventorySection: Identifiable, Equatable {
    /// How soon a card's soonest batch expires.
    enum Bucket: String, Equatable {
        case expired, soon, later, undated

        /// The section header.
        var title: String {
            switch self {
            case .expired: "Expired"
            case .soon: "Expiring Soon"
            case .later: "Later"
            case .undated: "No Expiration Date"
            }
        }
    }

    /// The bucket, or nil for the one headerless section of a page sorted by title.
    var bucket: Bucket?
    var items: [InventoryDisplayItem]

    var id: String { bucket?.rawValue ?? "all" }
    var title: String? { bucket?.title }
}

/// Splits an inventory page's rows into sections (owner design pass, 2026-10-16; HIG Lists and tables: "use section
/// headers to organize"; Reminders groups by due date the same way).
///
/// A page sorted by title is one list: the sort order is alphabetical and a status header would break it up. A page sorted
/// by expiration groups the rows, in the order they already come, into Expired, Expiring Soon, Later and No Expiration
/// Date; a bucket with no rows has no header. "Soon" is the same week the rows' orange text and the page's summary use.
enum InventorySections {
    /// The bucket for a card (the same judgement as its row subtitle: local calendar, soon within a week).
    static func bucket(of item: InventoryDisplayItem, calendar: InventoryCalendar) -> InventorySection.Bucket {
        guard let soonest = item.soonestExpiry(calendar) else { return .undated }
        switch InventoryCatalog.expiryInfo(soonest, calendar: calendar).tone {
        case .expired: return .expired
        case .soon: return .soon
        case nil: return .later
        }
    }

    /// The sections for `items`, which are already filtered and sorted.
    static func make(_ items: [InventoryDisplayItem], sort: InventorySortMode, calendar: InventoryCalendar) -> [InventorySection] {
        guard sort == .expiry else { return items.isEmpty ? [] : [InventorySection(bucket: nil, items: items)] }
        var sections: [InventorySection] = []
        for item in items {
            let bucket = bucket(of: item, calendar: calendar)
            if sections.last?.bucket == bucket {
                sections[sections.count - 1].items.append(item)
            } else {
                sections.append(InventorySection(bucket: bucket, items: [item]))
            }
        }
        return sections
    }
}
