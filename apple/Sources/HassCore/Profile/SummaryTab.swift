import Foundation

/// One section of the "Your Summary" sheet behind the header Profile button (owner, 2026-10-17): the web's Daily Report
/// modal (`ha-sfenton-react-dash@f5a7bf9:src/constants/dailyReport.ts:22-36`, `DAILY_REPORT_TABS`) with the app's own
/// Profile section ahead of it.
///
/// Tab order is the bar's order: Profile first, then the web's three. The sheet opens on ``initial(viewer:)``, which is
/// not the first tab.
public enum SummaryTab: String, CaseIterable, Hashable, Identifiable, Sendable {
    /// The signed-in person, who is home, Location and Sign Out (the app's own extras).
    case profile
    /// The viewer's chores past their due date.
    case overdue
    /// The viewer's chores due today, then those without a due date.
    case upcoming
    /// EverShelf's expired items.
    case expiredFood = "expired-food"

    public var id: String { rawValue }

    /// The tab's name: the web's `label`, which is also its section header.
    public var title: String {
        switch self {
        case .profile: "Profile"
        case .overdue: "Overdue Chores"
        case .upcoming: "Upcoming Chores"
        case .expiredFood: "Expired Food"
        }
    }

    /// The web's icon (`DAILY_REPORT_TABS[].icon`); Profile has none there and takes the account glyph.
    public var mdiIcon: String {
        switch self {
        case .profile: "mdi:account-circle"
        case .overdue: "mdi:alert-circle"
        case .upcoming: "mdi:clipboard-list"
        case .expiredFood: "mdi:food-off-outline"
        }
    }

    /// The spoken name of the bar (web `dailyReportSections`, "Daily report sections").
    public static let barLabel = "Summary sections"

    // MARK: - Which tabs

    /// The tabs a viewer sees.
    ///
    /// A resident has all four. Anyone else has Profile and Expired Food: the chore tabs are personal (the web shows
    /// "Whose Summary?" and no tabs at all until a resident is picked, which the app cannot offer because it is
    /// signed in as one person), while the kitchen is the household's.
    public static func tabs(viewer: ChoresConfig.Resident?) -> [SummaryTab] {
        viewer == nil ? [.profile, .expiredFood] : allCases
    }

    /// The tab the sheet opens on: Overdue Chores for a resident, else Expired Food. Not Profile: the sheet is a summary
    /// first (owner, 2026-10-17).
    public static func initial(viewer: ChoresConfig.Resident?) -> SummaryTab {
        viewer == nil ? .expiredFood : .overdue
    }

    // MARK: - Badges

    /// The count a tab's badge shows: only the actionable tabs badge (web `DailyReportModalNav`); upcoming chores are
    /// informational.
    /// - Parameters:
    ///   - overdue: Open overdue chores for the viewer.
    ///   - expiredFood: Expired items, already zero in Vacation Mode.
    public func badge(overdue: Int, expiredFood: Int) -> Int {
        switch self {
        case .overdue: overdue
        case .expiredFood: expiredFood
        case .profile, .upcoming: 0
        }
    }

    /// What VoiceOver says for a tab: the title, then the count when there is one ("Overdue Chores, 3 items", web
    /// `tabItemCount`, which is singular for one).
    public static func accessibilityLabel(title: String, badge: Int) -> String {
        guard badge > 0 else { return title }
        return "\(title), \(badge) \(badge == 1 ? "item" : "items")"
    }

    /// ``accessibilityLabel(title:badge:)`` for this tab.
    public func accessibilityLabel(badge: Int) -> String {
        Self.accessibilityLabel(title: title, badge: badge)
    }
}

// MARK: - Counts

/// What the Summary's tab badges and the header Profile badge count.
public struct SummaryCounts: Equatable, Sendable {
    /// Open overdue chores for the viewer (0 for a guest).
    public var overdue: Int
    /// Expired items on the local calendar; 0 in Vacation Mode, which puts the kitchen on hold.
    public var expiredFood: Int

    public init(overdue: Int, expiredFood: Int) {
        self.overdue = overdue
        self.expiredFood = expiredFood
    }

    /// The header Profile button's badge: overdue plus expired (``ProfileSummary/badgeCount(overdue:expiredFood:vacationMode:)``).
    public var attention: Int { overdue + expiredFood }

    /// The badge on `tab`.
    public func badge(for tab: SummaryTab) -> Int { tab.badge(overdue: overdue, expiredFood: expiredFood) }
}

extension ProfileSummary {
    /// The counts for a viewer, read from the entity store.
    @MainActor
    public static func counts(viewer: ChoresConfig.Resident?, store: EntityStore, now: Date = .now, calendar: Calendar = .current) -> SummaryCounts {
        let vacation = store.entity(ChoresConfig.vacationModeEntityId).state?.state == "on"
        let overdue = viewer.map { openCount(store.entity(lists(for: $0).overdue.entityId).state) } ?? 0
        let expired = expiredFoodCount(store.entity(expiredFoodEntityId).state, now: now, calendar: calendar) ?? 0
        return SummaryCounts(overdue: overdue, expiredFood: badgeCount(overdue: 0, expiredFood: expired, vacationMode: vacation))
    }
}

// MARK: - Expired food copy

extension ProfileSummary {
    /// The expired food count the Expired Food tab and its badge read: the number of items past their date on the
    /// local calendar, or `nil` when the sensor is missing or unavailable (web `useExpiredFoodCount`, which returns `null`
    /// for a missing entity). Nil is "unknown", never "none".
    public static func expiredFoodCount(_ state: EntityState?, now: Date = .now, calendar: Calendar = .current) -> Int? {
        guard let state, !state.isUnavailable else { return nil }
        return expiredItems(state, now: now, calendar: calendar).count
    }

    /// A tab's empty state.
    public struct EmptyCopy: Equatable, Sendable {
        public var title: String
        public var description: String
    }

    /// "No Expired Food": the sensor's count is zero, or the list has nothing past its date.
    public static let noExpiredFood = EmptyCopy(title: Empty.foodTitle, description: Empty.foodDescription)

    /// What the Expired Food tab says when it has no list to show (web `DailyReportExpiredFoodTab`).
    ///
    /// - Vacation Mode on: the kitchen cannot be dealt with from away, so the list is hidden with "Enjoy vacation!". It
    ///   only says "No Expired Food" when the count is a confirmed zero; an unavailable sensor stays "Expired Food Hidden".
    /// - Otherwise: "No Expired Food" when the count is zero, and `nil` when there are items (or the sensor is unknown) and
    ///   the list should show.
    public static func expiredFoodEmpty(count: Int?, vacationMode: Bool) -> EmptyCopy? {
        if vacationMode {
            return EmptyCopy(title: count == 0 ? Empty.foodTitle : "Expired Food Hidden", description: Empty.vacation)
        }
        return count == 0 ? noExpiredFood : nil
    }

    /// An empty chore tab's copy: "Enjoy vacation!" while Vacation Mode is on (web `VACATION_EMPTY_DESCRIPTION`).
    public static func choresEmpty(_ tab: SummaryTab, vacationMode: Bool) -> EmptyCopy {
        let overdue = tab == .overdue
        return EmptyCopy(
            title: overdue ? Empty.overdueTitle : Empty.upcomingTitle,
            description: vacationMode ? Empty.vacation : (overdue ? Empty.overdueDescription : Empty.upcomingDescription)
        )
    }
}

// MARK: - People

extension ProfileSummary.Person {
    /// The household resident this person is, matched by entity id (the resident's `person.*` entity) or first name; nil
    /// for a guest.
    ///
    /// The first word, not a prefix: a first name that merely starts with another resident's name is not that resident.
    public var resident: ChoresConfig.Resident? {
        let firstName = name.split(whereSeparator: \.isWhitespace).first.map { $0.lowercased() }
        return ChoresConfig.Resident.allCases.first { id == $0.personEntityId || firstName == $0.name.lowercased() }
    }
}
