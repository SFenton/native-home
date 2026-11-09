import Foundation

/// What the Profile modal shows: the web's Daily Report modal ("Your Summary"), plus who is home.
///
/// Source: `ha-sfenton-react-dash@f5a7bf9:src/components/hass/DailyReportModal.tsx`, `dailyReportModal.ts` (the badge
/// and context), `src/constants/dailyReport.ts` (tabs, per-resident lists, titles) and `expiryDate.ts` (the local
/// calendar's idea of "expired"). The web shows it in a modal behind its header Profile button; the app's Profile
/// button opens the Your Summary sheet, which carries the same content in four tabs (``SummaryTab``; owner, 2026-10-17).
public enum ProfileSummary {
    // MARK: - Entities

    /// The sensor of expired food items; its `expired_list` attribute lists each item: the server's document.
    public static var expiredFoodEntityId: String { FoodConfig.expiredItemsEntityId }

    /// The resident's DoneTick lists the summary reads (web `DAILY_REPORT_USERS[].todoEntityIds`).
    public struct ResidentLists: Hashable, Sendable {
        /// Chores past their due date (tab "Overdue Chores").
        public var overdue: ChoresConfig.TodoList
        /// Chores due today (tab "Upcoming Chores").
        public var dueToday: ChoresConfig.TodoList
        /// Chores without a due date, shown with the upcoming ones.
        public var noDueDate: ChoresConfig.TodoList

        /// The three open-item counts the badge and the empty states read.
        public var all: [ChoresConfig.TodoList] { [overdue, dueToday, noDueDate] }
    }

    /// The lists for a resident: their own plus the unassigned chores, named by the document's person record.
    public static func lists(for resident: ChoresConfig.Resident) -> ResidentLists {
        let lists = resident.person.summaryLists
        return ResidentLists(
            overdue: ChoresConfig.TodoList(title: "Overdue Chores", entityId: lists.overdue),
            dueToday: ChoresConfig.TodoList(title: "Upcoming Chores", entityId: lists.dueToday),
            noDueDate: ChoresConfig.TodoList(title: "No Due Date", entityId: lists.noDueDate)
        )
    }

    // MARK: - Copy

    /// The modal's title: "Your Summary" for the viewer's own, "Summary" when the viewer is not a resident (web
    /// `dailyReportTitle`).
    public static func title(viewer: ChoresConfig.Resident?) -> String {
        viewer == nil ? "Summary" : "Your Summary"
    }

    /// Web `NO_EXPIRED_FOOD_EMPTY_STATE` and the chore empty states.
    public enum Empty {
        public static let overdueTitle = "No Chores Due"
        public static let overdueDescription = "You are all caught up on chores that slipped past their due date."
        public static let upcomingTitle = "No Chores Upcoming"
        public static let upcomingDescription = "There is nothing else on your schedule for the rest of today."
        public static let foodTitle = "No Expired Food"
        public static let foodDescription = "Everything in the kitchen is still within date."
        public static var vacation: String { ChoresConfig.vacationEmptyDescription }
    }

    // MARK: - Counts

    /// A positive whole count from a todo list's state (web `actionableCount`), else 0.
    public static func openCount(_ state: EntityState?) -> Int {
        guard let value = state?.numericState, value.isFinite, value > 0 else { return 0 }
        return Int(value)
    }

    /// The Profile button's badge: overdue chores plus expired food; upcoming chores are informational and never count
    /// (web `badgeCount`). Vacation puts expired food on hold, so it does not nag from the badge either.
    public static func badgeCount(overdue: Int, expiredFood: Int, vacationMode: Bool) -> Int {
        overdue + (vacationMode ? 0 : expiredFood)
    }

    /// The badge as drawn: capped at 9 ("9+", web `CountBadge`), nil for none.
    public static func badgeText(_ count: Int) -> String? {
        guard count > 0 else { return nil }
        return count > 9 ? "9+" : "\(count)"
    }


    // MARK: - Expired food

    /// One expired item from the sensor's `expired_list`.
    public struct ExpiredItem: Hashable, Sendable, Identifiable {
        public var id: String
        public var name: String
        /// The EverShelf location key (`frigo`), mapped through ``locationTitle``.
        public var location: String
        /// The item's expiry date, local calendar day.
        public var expiryDate: Date
        /// Whole days since it expired (1 or more).
        public var daysAgo: Int

        /// The place's name ("Fridge") for a location key, or the key tidied up.
        public var locationTitle: String {
            FoodConfig.spaces.first { $0.location == FoodConfig.normalizedLocation(location) }?.title
                ?? location.replacingOccurrences(of: "_", with: " ").capitalized
        }

        /// "Expired Yesterday", "Expired 6 Days Ago".
        public var expiredText: String {
            daysAgo == 1 ? "Expired Yesterday" : "Expired \(daysAgo) Days Ago"
        }
    }

    /// Items expired on the local calendar, most overdue first (web `countLocallyExpired`: EverShelf computes
    /// `days_remaining` in UTC, so from about 5 pm Pacific an item dated today already reads -1; the app classifies by
    /// the local day instead, in one place).
    public static func expiredItems(_ state: EntityState?, now: Date = .now, calendar: Calendar = .current) -> [ExpiredItem] {
        guard let list = state?.attributes["expired_list"]?.array else { return [] }
        let today = calendar.startOfDay(for: now)
        var items: [ExpiredItem] = []
        for (index, raw) in list.enumerated() {
            guard let text = raw["expiry_date"]?.string, let date = dateOnly(text, calendar: calendar),
                  let days = calendar.dateComponents([.day], from: date, to: today).day, days > 0 else { continue }
            let name = raw["name"]?.string ?? "Item"
            let id = raw["inventory_id"]?.finiteNumber.map { "\(Int($0))" } ?? "\(index)-\(name)"
            items.append(ExpiredItem(id: id, name: name, location: raw["location"]?.string ?? "", expiryDate: date, daysAgo: days))
        }
        return items.sorted { $0.daysAgo > $1.daysAgo }
    }

    /// `YYYY-MM-DD…` as a local calendar day (web `parseIsoDateOnly`).
    static func dateOnly(_ text: String, calendar: Calendar) -> Date? {
        let parts = text.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard text.count >= 10, parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    // MARK: - People

    /// One person from a `person.*` entity.
    public struct Person: Hashable, Sendable, Identifiable {
        public var id: String
        public var name: String
        /// `home`, `not_home` or a zone name.
        public var state: String

        public var isHome: Bool { state == "home" }

        /// "Home", "Away", or the zone's name.
        public var stateText: String {
            switch state {
            case "home": "Home"
            case "not_home": "Away"
            case "unknown", "unavailable": "Unknown"
            default: state.replacingOccurrences(of: "_", with: " ").capitalized
            }
        }
    }

    /// People, those at home first, then by name.
    public static func people(_ states: [EntityState]) -> [Person] {
        states.filter { $0.domain == "person" }
            .map { Person(id: $0.entityId, name: $0.friendlyName, state: $0.state) }
            .sorted { ($0.isHome ? 0 : 1, $0.name) < ($1.isHome ? 0 : 1, $1.name) }
    }

    /// "2 of 3 Home" for the section header.
    public static func homeSummary(_ people: [Person]) -> String {
        "\(people.filter(\.isHome).count) of \(people.count) Home"
    }
}
