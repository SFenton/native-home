import Foundation
@testable import HassCore
import Testing
import HassTestSupport

/// The Your Summary sheet's tabs: their order, who sees which, badges, spoken names and the empty and vacation copy
/// (web `dailyReport.ts`, `DailyReportModalContent.tsx`).
@MainActor
@Suite(.demoHouse)
struct SummaryTabTests {
    let calendar = Calendar(identifier: .gregorian)
    var now: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: 12))! }

    // MARK: Order and membership

    @Test func profileLeadsAndTheWebsThreeFollowInOrder() {
        #expect(SummaryTab.allCases == [.profile, .overdue, .upcoming, .expiredFood])
        #expect(SummaryTab.tabs(viewer: .resident1) == SummaryTab.allCases)
        #expect(SummaryTab.tabs(viewer: .resident2) == SummaryTab.allCases)
    }

    @Test func aGuestHasNoChoreTabs() {
        // The chore tabs are personal; the web asks "Whose Summary?" and shows no tabs until one is picked.
        #expect(SummaryTab.tabs(viewer: nil) == [.profile, .expiredFood])
    }

    @Test func theSheetOpensOnTheSummaryNotOnProfile() {
        #expect(SummaryTab.initial(viewer: .resident1) == .overdue)
        #expect(SummaryTab.initial(viewer: nil) == .expiredFood)
        #expect(SummaryTab.tabs(viewer: nil).contains(SummaryTab.initial(viewer: nil)))
    }

    @Test func tabsCarryTheWebsTitlesAndIcons() {
        #expect(SummaryTab.allCases.map(\.title) == ["Profile", "Overdue Chores", "Upcoming Chores", "Expired Food"])
        #expect(SummaryTab.overdue.mdiIcon == "mdi:alert-circle")
        #expect(SummaryTab.upcoming.mdiIcon == "mdi:clipboard-list")
        #expect(SummaryTab.expiredFood.mdiIcon == "mdi:food-off-outline")
        #expect(SummaryTab.barLabel == "Summary sections")
        #expect(Set(SummaryTab.allCases.map(\.id)).count == 4)
    }

    // MARK: Badges

    @Test func onlyOverdueAndExpiredFoodBadge() {
        #expect(SummaryTab.overdue.badge(overdue: 3, expiredFood: 2) == 3)
        #expect(SummaryTab.expiredFood.badge(overdue: 3, expiredFood: 2) == 2)
        #expect(SummaryTab.upcoming.badge(overdue: 3, expiredFood: 2) == 0, "upcoming chores are informational")
        #expect(SummaryTab.profile.badge(overdue: 3, expiredFood: 2) == 0)
    }

    @Test func voiceOverHearsTheCountAfterTheName() {
        #expect(SummaryTab.overdue.accessibilityLabel(badge: 3) == "Overdue Chores, 3 items")
        #expect(SummaryTab.expiredFood.accessibilityLabel(badge: 1) == "Expired Food, 1 item")
        #expect(SummaryTab.upcoming.accessibilityLabel(badge: 0) == "Upcoming Chores")
        #expect(SummaryTab.accessibilityLabel(title: "Profile", badge: 0) == "Profile")
    }

    // MARK: Counts

    func store(overdue: Int, expired: [String], vacation: Bool, viewer: ChoresConfig.Resident = .resident1) -> EntityStore {
        let store = EntityStore()
        store.replaceAll([
            EntityState(entityId: ProfileSummary.lists(for: viewer).overdue.entityId, state: "\(overdue)"),
            EntityState(entityId: ChoresConfig.vacationModeEntityId, state: vacation ? "on" : "off"),
            EntityState(entityId: ProfileSummary.expiredFoodEntityId, state: "\(expired.count)", attributes: ["expired_list": .array(
                expired.map { .object(["name": .string($0), "expiry_date": .string("2026-10-01"), "location": .string("frigo")]) }
            )]),
        ])
        return store
    }

    @Test func countsReadTheViewersOverdueListAndTheLocalExpiredFood() {
        let counts = ProfileSummary.counts(viewer: .resident1, store: store(overdue: 3, expired: ["Milk", "Eggs"], vacation: false), now: now, calendar: calendar)
        #expect(counts == SummaryCounts(overdue: 3, expiredFood: 2))
        #expect(counts.attention == 5)
        #expect(counts.badge(for: .overdue) == 3)
        #expect(counts.badge(for: .expiredFood) == 2)
        #expect(counts.badge(for: .upcoming) == 0)
    }

    @Test func vacationPutsExpiredFoodOnHoldInTheBadges() {
        let counts = ProfileSummary.counts(viewer: .resident1, store: store(overdue: 3, expired: ["Milk"], vacation: true), now: now, calendar: calendar)
        #expect(counts == SummaryCounts(overdue: 3, expiredFood: 0))
    }

    @Test func aGuestHasNoOverdueButStillSeesTheKitchen() {
        let counts = ProfileSummary.counts(viewer: nil, store: store(overdue: 3, expired: ["Milk"], vacation: false), now: now, calendar: calendar)
        #expect(counts == SummaryCounts(overdue: 0, expiredFood: 1))
    }

    @Test func samsOverdueListIsHerOwn() {
        let counts = ProfileSummary.counts(viewer: .resident2, store: store(overdue: 4, expired: [], vacation: false, viewer: .resident2), now: now, calendar: calendar)
        #expect(counts.overdue == 4)
    }

    // MARK: Expired food count

    @Test func theExpiredCountIsUnknownUntilTheSensorIsThere() {
        #expect(ProfileSummary.expiredFoodCount(nil) == nil)
        #expect(ProfileSummary.expiredFoodCount(EntityState(entityId: ProfileSummary.expiredFoodEntityId, state: "unavailable")) == nil)
        #expect(ProfileSummary.expiredFoodCount(EntityState(entityId: ProfileSummary.expiredFoodEntityId, state: "0"), now: now, calendar: calendar) == 0)
    }

    // MARK: Copy

    @Test func emptyChoreTabsSayTheWebsWords() {
        let overdue = ProfileSummary.choresEmpty(.overdue, vacationMode: false)
        #expect(overdue.title == "No Chores Due")
        #expect(overdue.description == "You are all caught up on chores that slipped past their due date.")
        let upcoming = ProfileSummary.choresEmpty(.upcoming, vacationMode: false)
        #expect(upcoming.title == "No Chores Upcoming")
        #expect(upcoming.description == "There is nothing else on your schedule for the rest of today.")
    }

    @Test func vacationReplacesTheDescriptionButKeepsTheChoreTitle() {
        #expect(ProfileSummary.choresEmpty(.overdue, vacationMode: true) == .init(title: "No Chores Due", description: "Enjoy vacation!"))
        #expect(ProfileSummary.choresEmpty(.upcoming, vacationMode: true) == .init(title: "No Chores Upcoming", description: "Enjoy vacation!"))
    }

    @Test func noExpiredFoodIsASettledZero() {
        let none = ProfileSummary.expiredFoodEmpty(count: 0, vacationMode: false)
        #expect(none == .init(title: "No Expired Food", description: "Everything in the kitchen is still within date."))
        #expect(none == ProfileSummary.noExpiredFood)
    }

    @Test func aListOrAnUnknownCountShowsRows() {
        #expect(ProfileSummary.expiredFoodEmpty(count: 3, vacationMode: false) == nil)
        #expect(ProfileSummary.expiredFoodEmpty(count: nil, vacationMode: false) == nil, "an unavailable sensor is not 'none'")
    }

    @Test func vacationHidesExpiredFoodUnlessTheCountIsAConfirmedZero() {
        #expect(ProfileSummary.expiredFoodEmpty(count: 3, vacationMode: true) == .init(title: "Expired Food Hidden", description: "Enjoy vacation!"))
        #expect(ProfileSummary.expiredFoodEmpty(count: nil, vacationMode: true) == .init(title: "Expired Food Hidden", description: "Enjoy vacation!"))
        #expect(ProfileSummary.expiredFoodEmpty(count: 0, vacationMode: true) == .init(title: "No Expired Food", description: "Enjoy vacation!"))
    }

    // MARK: People

    @Test func aPersonIsAResidentByEntityOrFirstWord() {
        func person(_ id: String, _ name: String) -> ProfileSummary.Person { .init(id: id, name: name, state: "home") }
        #expect(person("person.demo_alex", "Anyone").resident == .resident1)
        #expect(person("person.demo_x", "Alex Demo").resident == .resident1)
        #expect(person("person.demo_y", "Sam Demo").resident == .resident2, "Sam is not a prefix match for Samantha")
        #expect(person("person.demo_z", "Samantha").resident == nil)
        #expect(person("person.demo_guest", "Guest").resident == nil)
    }
}
