import Foundation
@testable import HassCore
import Testing

/// Local-calendar expiry rules and number formatting, with a pinned UTC calendar and "now" of 2026-10-11 noon.
struct InventoryCalendarTests {
    let calendar = InventoryFixtures.calendar()

    // MARK: Parsing

    @Test func parsesTheDatePrefix() {
        #expect(calendar.date(fromISO: "2026-10-11") == InventoryFixtures.date(2026, 10, 11))
        #expect(calendar.date(fromISO: "2026-10-20T23:59:00Z") == InventoryFixtures.date(2026, 10, 20))
    }

    @Test(arguments: ["", "2026", "2026/10/11", "20261011xx", "2026-1a-11", "26-10-11", "2026-10-1", "abcd-ef-gh"])
    func rejectsNonDates(value: String) {
        #expect(calendar.date(fromISO: value) == nil)
        #expect(calendar.days(untilISO: value) == nil)
    }

    @Test func partsSplitsYearMonthDay() throws {
        let parts = try #require(InventoryCalendar.parts("2026-02-03"))
        #expect(parts.0 == 2026 && parts.1 == 2 && parts.2 == 3)
    }

    @Test func validInputIsEmptyOrExactlyADate() {
        #expect(InventoryCalendar.isValidInput(""))
        #expect(InventoryCalendar.isValidInput("   "))
        #expect(InventoryCalendar.isValidInput("2026-10-11"))
        #expect(InventoryCalendar.isValidInput(" 2026-10-11 "))
        #expect(!InventoryCalendar.isValidInput("2026-10-11T00:00"))
        #expect(!InventoryCalendar.isValidInput("2026-1-1"))
        #expect(!InventoryCalendar.isValidInput("10/11/2026"))
    }

    // MARK: Days

    @Test func todayIsLocalMidnight() {
        #expect(calendar.today == InventoryFixtures.date(2026, 10, 11))
        _ = InventoryCalendar.current.today
    }

    @Test func daysUntil() {
        #expect(calendar.days(until: InventoryFixtures.date(2026, 10, 11)) == 0)
        #expect(calendar.days(until: InventoryFixtures.date(2026, 10, 12)) == 1)
        #expect(calendar.days(until: InventoryFixtures.date(2026, 10, 1)) == -10)
        // Later the same day still counts as today.
        #expect(calendar.days(until: InventoryFixtures.date(2026, 10, 11).addingTimeInterval(23 * 3600)) == 0)
        #expect(calendar.days(untilISO: "2027-10-11") == 365)
        #expect(calendar.days(untilISO: nil) == nil)
    }

    @Test func expiredByTheLocalDay() {
        #expect(calendar.isExpired("2026-10-10"))
        #expect(!calendar.isExpired("2026-10-11"))
        #expect(!calendar.isExpired("2026-12-01"))
        #expect(!calendar.isExpired(nil))
        #expect(!calendar.isExpired("garbage"))
    }

    @Test func daysFollowTheCalendarsTimeZone() {
        // 2026-10-12 03:00 UTC is still the 11th in Los Angeles.
        var pacific = Calendar(identifier: .gregorian)
        pacific.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let now = InventoryFixtures.date(2026, 10, 12).addingTimeInterval(3 * 3600)
        let local = InventoryCalendar(calendar: pacific, now: { now })
        #expect(!local.isExpired("2026-10-11"))
        #expect(local.days(untilISO: "2026-10-11") == 0)
    }

    // MARK: Formatting

    @Test func formats() {
        let date = InventoryFixtures.date(2026, 3, 7)
        #expect(calendar.displayDate(date) == "Mar 7, 2026")
        #expect(calendar.isoString(date) == "2026-03-07")
    }

    @Test func addingMonthsClampsToTheMonthEnd() {
        #expect(calendar.isoString(calendar.adding(months: 1, to: InventoryFixtures.date(2026, 1, 31))) == "2026-02-28")
        #expect(calendar.isoString(calendar.adding(months: 1, to: InventoryFixtures.date(2024, 1, 31))) == "2024-02-29")
        #expect(calendar.isoString(calendar.adding(months: 12, to: InventoryFixtures.date(2026, 10, 11))) == "2027-10-11")
        #expect(calendar.isoString(calendar.adding(months: -1, to: InventoryFixtures.date(2026, 3, 31))) == "2026-02-28")
    }

    // MARK: InventoryFormat

    @Test func quantityHasNoTrailingZeros() {
        #expect(InventoryFormat.quantity(2) == "2")
        #expect(InventoryFormat.quantity(0) == "0")
        #expect(InventoryFormat.quantity(-2) == "-2")
        #expect(InventoryFormat.quantity(1.5) == "1.5")
        #expect(InventoryFormat.quantity(0.25) == "0.25")
        #expect(InventoryFormat.quantity(1.0 / 3.0) == "0.333333")
        #expect(InventoryFormat.quantity(1e16) == "10000000000000000")
    }

    @Test(arguments: [("5", 5.0), ("1.5", 1.5), (".5", 0.5), ("1,5", 1.5), (" 3 ", 3.0), ("007", 7.0)])
    func parsesQuantities(text: String, expected: Double) {
        #expect(InventoryFormat.parseQuantity(text) == expected)
    }

    @Test(arguments: ["5.", "1.2.3", "a", "", " ", "-1", "1e3", "1 2", "٣"])
    func rejectsQuantities(text: String) {
        #expect(InventoryFormat.parseQuantity(text) == nil)
    }
}
