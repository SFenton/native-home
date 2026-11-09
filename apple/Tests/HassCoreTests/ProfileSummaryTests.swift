import Foundation
@testable import HassCore
import HassTestSupport
import Testing

/// The Profile modal's logic: ports of the web's `dailyReportModal` badge, `expiryDate` local-calendar rule and
/// `dailyReport` per-resident lists and titles.
@Suite(.demoHouse)
struct ProfileSummaryTests {
    let calendar = Calendar(identifier: .gregorian)
    /// 5 pm Pacific on Oct 16, 2026, local calendar day Oct 16.
    var now: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: 17))! }

    func expired(_ items: [(name: String, date: String, location: String)]) -> EntityState {
        EntityState(entityId: ProfileSummary.expiredFoodEntityId, state: "\(items.count)", attributes: ["expired_list": .array(
            items.enumerated().map { index, item in
                .object(["name": .string(item.name), "expiry_date": .string(item.date), "location": .string(item.location),
                         "inventory_id": .number(Double(100 + index))])
            }
        )])
    }

    // MARK: Lists and titles

    @Test func residentsReadTheirPastDueTodayAndNoDueDateListsWithUnassigned() {
        let alex = ProfileSummary.lists(for: .resident1)
        // ProfileSummary reads the chores pages of the active house, so the lists are compared with them, not with literals.
        #expect(alex.overdue.entityId == ChoresConfig.pages[2].lists[0].entityId)
        #expect(Set(alex.all.map(\.entityId)).count == 3)
        #expect(ProfileSummary.lists(for: .resident2).overdue.entityId == ChoresConfig.pages[3].lists[0].entityId)
        #expect(alex.all.count == 3)
    }

    @Test func theTitleIsPersonalOnlyForAResident() {
        #expect(ProfileSummary.title(viewer: .resident1) == "Your Summary")
        #expect(ProfileSummary.title(viewer: nil) == "Summary")
    }

    // MARK: Badge

    @Test func theBadgeCountsOverdueChoresAndExpiredFoodButNotUpcoming() {
        #expect(ProfileSummary.badgeCount(overdue: 3, expiredFood: 2, vacationMode: false) == 5)
        #expect(ProfileSummary.badgeCount(overdue: 3, expiredFood: 2, vacationMode: true) == 3, "vacation puts expired food on hold")
        #expect(ProfileSummary.badgeCount(overdue: 0, expiredFood: 0, vacationMode: false) == 0)
    }

    @Test func theBadgeCapsAtNinePlus() {
        #expect(ProfileSummary.badgeText(0) == nil)
        #expect(ProfileSummary.badgeText(7) == "7")
        #expect(ProfileSummary.badgeText(9) == "9")
        #expect(ProfileSummary.badgeText(12) == "9+")
    }

    @Test func openCountReadsOnlyPositiveNumbers() {
        func state(_ value: String) -> EntityState { EntityState(entityId: "todo.demo_x", state: value) }
        #expect(ProfileSummary.openCount(state("4")) == 4)
        #expect(ProfileSummary.openCount(state("0")) == 0)
        #expect(ProfileSummary.openCount(state("unavailable")) == 0)
        #expect(ProfileSummary.openCount(nil) == 0)
    }

    // MARK: Expired food

    @Test func foodExpiredOnTheLocalCalendarListsMostOverdueFirst() {
        let state = expired([("Nachos", "2026-10-02", "dispensa"), ("Sour Cream", "2026-10-15", "frigo"), ("Today", "2026-10-16", "frigo")])
        let items = ProfileSummary.expiredItems(state, now: now, calendar: calendar)
        // EverShelf's UTC rollover lists an item dated today from 5 pm Pacific; the local day says it is still good.
        #expect(items.map(\.name) == ["Nachos", "Sour Cream"])
        #expect(items.map(\.daysAgo) == [14, 1])
        #expect(items[0].expiredText == "Expired 14 Days Ago")
        #expect(items[1].expiredText == "Expired Yesterday")
        #expect(items[0].locationTitle == FoodConfig.spaces[0].title)
        #expect(items[1].locationTitle == FoodConfig.spaces[1].title)
    }

    @Test func missingOrMalformedExpiryDataListsNothing() {
        #expect(ProfileSummary.expiredItems(nil, now: now, calendar: calendar).isEmpty)
        #expect(ProfileSummary.expiredItems(EntityState(entityId: ProfileSummary.expiredFoodEntityId, state: "unavailable"),
                                            now: now, calendar: calendar).isEmpty)
        #expect(ProfileSummary.expiredItems(expired([("Odd", "soon", "frigo"), ("Short", "2026-10", "frigo")]), now: now, calendar: calendar).isEmpty)
    }

    @Test func anUnknownLocationIsTidied() {
        let items = ProfileSummary.expiredItems(expired([("Bag", "2026-10-01", "back_porch")]), now: now, calendar: calendar)
        #expect(items.first?.locationTitle == "Back Porch")
    }

    // MARK: People

    @Test func peopleAtHomeComeFirstThenByName() {
        let people = ProfileSummary.people([
            EntityState(entityId: "person.demo_zed", state: "not_home", attributes: ["friendly_name": .string("Zed")]),
            EntityState(entityId: "person.demo_sam", state: "home", attributes: ["friendly_name": .string("Sam")]),
            EntityState(entityId: "person.demo_amy", state: "work", attributes: ["friendly_name": .string("Amy")]),
            EntityState(entityId: "person.demo_alex", state: "home", attributes: ["friendly_name": .string("Alex")]),
            EntityState(entityId: "light.demo_hall", state: "on"),
        ])
        #expect(people.map(\.name) == ["Alex", "Sam", "Amy", "Zed"])
        #expect(people.map(\.stateText) == ["Home", "Home", "Work", "Away"])
        #expect(ProfileSummary.homeSummary(people) == "2 of 4 Home")
    }
}
