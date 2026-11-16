import Foundation
@testable import HassCore
@testable import HassUI
import Testing

/// How an inventory page groups its rows (`InventorySections`). "Today" is 2026-10-11 (UTC).
struct InventorySectionsTests {
    private let calendar: InventoryCalendar = {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let now = utc.date(from: DateComponents(year: 2026, month: 10, day: 11, hour: 12))!
        return InventoryCalendar(calendar: utc, now: { now })
    }()

    private func card(_ name: String, expiry: String?, id: Int = 1) -> InventoryDisplayItem {
        InventoryDisplayItem(rows: [InventoryItem(inventoryId: id, name: name, expiryDate: expiry)])
    }

    @Test func aPageSortedByTitleIsOneHeaderlessList() {
        let items = [card("Honey", expiry: nil), card("Rice", expiry: "2026-10-01", id: 2)]
        let sections = InventorySections.make(items, sort: .title, calendar: calendar)
        #expect(sections.count == 1)
        #expect(sections[0].title == nil)
        #expect(sections[0].items == items)
        #expect(InventorySections.make([], sort: .title, calendar: calendar).isEmpty)
    }

    @Test func aPageSortedByExpirationGroupsByStatusInTheOrderItAlreadyHas() {
        let items = [
            card("Rice", expiry: "2026-10-01", id: 1),
            card("Milk", expiry: "2026-10-14", id: 2),
            card("Soup", expiry: "2026-10-17", id: 3),
            card("Peas", expiry: "2027-03-15", id: 4),
            card("Beans", expiry: "2027-08-12", id: 5),
            card("Honey", expiry: nil, id: 6),
        ]
        let sections = InventorySections.make(items, sort: .expiry, calendar: calendar)
        #expect(sections.map(\.title) == ["Expired", "Expiring Soon", "Later", "No Expiration Date"])
        #expect(sections.map(\.items.count) == [1, 2, 2, 1])
        #expect(sections.map(\.id) == ["expired", "soon", "later", "undated"])
    }

    @Test func descendingOrderKeepsItsGroupsInReverse() {
        let items = [card("Honey", expiry: nil, id: 1), card("Peas", expiry: "2027-03-15", id: 2), card("Rice", expiry: "2026-10-01", id: 3)]
        let sections = InventorySections.make(items, sort: .expiry, calendar: calendar)
        #expect(sections.map(\.title) == ["No Expiration Date", "Later", "Expired"])
    }

    @Test func aCardsBucketFollowsItsSoonestBatch() {
        let both = InventoryDisplayItem(rows: [
            InventoryItem(inventoryId: 1, name: "Beans", expiryDate: "2027-08-12"),
            InventoryItem(inventoryId: 2, name: "Beans", expiryDate: "2026-10-12"),
        ])
        #expect(InventorySections.bucket(of: both, calendar: calendar) == .soon)
        #expect(InventorySections.bucket(of: card("Salt", expiry: nil), calendar: calendar) == .undated)
        #expect(InventorySections.bucket(of: card("Old", expiry: "2026-10-10"), calendar: calendar) == .expired)
        #expect(InventorySections.bucket(of: card("Far", expiry: "2026-10-18"), calendar: calendar) == .later)
    }
}
