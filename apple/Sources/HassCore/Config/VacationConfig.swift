import Foundation

/// Vacation Mode entities, copy and service calls (web `src/constants/portedDashboard.ts:397-418`,
/// `src/i18n/locales/en/pages/vacation.json`, `DashboardViewPage.tsx` `VacationModePage`).
///
/// Vacation Mode is plain helpers: the vacation-mode `input_boolean`, its start and end `input_datetime`s, an
/// "invalid dates pending" flag Home Assistant raises when the saved range is unusable, and five checklist
/// booleans that must all be on before the mode can be enabled.
public enum Vacation {
    // MARK: - Entities

    /// The Vacation Mode switch: the server's document.
    public static var modeEntityId: String { HouseConfigSource.active.read { $0.vacation.modeEntityId } ?? "" }
    /// The flag raised when the saved dates are unusable.
    public static var invalidDatesPendingEntityId: String { HouseConfigSource.active.read { $0.vacation.invalidDatesPendingEntityId } ?? "" }
    /// The start date-time helper.
    public static var startEntityId: String { HouseConfigSource.active.read { $0.vacation.startEntityId } ?? "" }
    /// The end date-time helper.
    public static var endEntityId: String { HouseConfigSource.active.read { $0.vacation.endEntityId } ?? "" }


    /// One pre-vacation task.
    public struct ChecklistItem: Hashable, Sendable, Identifiable, Codable {
        public var title: String
        public var entityId: String
        public var id: String { entityId }
    }

    /// The pre-vacation checklist, in web order: the server's document.
    public static var checklist: [ChecklistItem] { HouseConfigSource.active.read { $0.vacation.checklist } ?? [] }

    /// Every entity the Vacation Mode page reads.
    public static var pageEntityIds: [String] {
        [modeEntityId, invalidDatesPendingEntityId, startEntityId, endEntityId] + checklist.map(\.entityId)
    }

    // MARK: - Copy

    /// Page copy, verbatim from the web.
    public enum Copy {
        public static let chooserTitle = "Vacation"
        public static let chooserAccessibilityLabel = "Away modes"
        public static let vacationLinkTitle = "Vacation"
        public static let vacationLinkSubtitle = "Set away dates and prepare the house for vacation."
        public static let settingsLinkTitle = "Vacation"
        public static let settingsLinkSubtitle = "Set away dates and prepare the house for vacation."
        public static let modeTitle = "Vacation Mode"
        public static let modeDescription = "Enable or disable vacation mode for the house"
        public static let preChecklistError = "All pre-vacation tasks must be checked off before Vacation Mode can be enabled."
        public static let checklistTitle = "Pre-Vacation Checklist"
        public static let datesTitle = "Vacation Dates"
        public static let datesDescription = "Set the start and end time for your vacation. Vacation mode will automatically be turned off at the set end date and time."
        public static let dateRangeError = "Start date and time must be before end date and time. Vacation mode is disabled until the dates are fixed."
        public static let confirmTitle = "Confirm Vacation"
        public static let confirmAction = "Confirm Vacation"
        /// The combined start picker's label (the Calendar app's "Starts").
        public static let starts = "Starts"
        /// The combined end picker's label.
        public static let ends = "Ends"
        public static let pending = "Pending"
        public static let on = "On"
        public static let off = "Off"
        public static let unavailable = "Unavailable"
    }

    // MARK: - Dates

    /// The vacation's start and end.
    public struct DateRange: Equatable, Sendable {
        public var start: WallClock
        public var end: WallClock

        public init(start: WallClock, end: WallClock) {
            self.start = start
            self.end = end
        }

        /// Starts now and ends a day later (web `defaultVacationDateRange`).
        public static func makeDefault(now: Date = .now, calendar: Calendar = .current) -> DateRange {
            let end = calendar.date(byAdding: .day, value: 1, to: now) ?? now
            return DateRange(start: WallClock(now, calendar: calendar), end: WallClock(end, calendar: calendar))
        }

        /// The helpers' saved range; a missing or malformed date or time falls back part by part to the
        /// default (web `vacationDateRangeFromStates`).
        public init(startState: String?, endState: String?, now: Date = .now, calendar: Calendar = .current) {
            let fallback = DateRange.makeDefault(now: now, calendar: calendar)
            start = Self.parse(startState, fallback: fallback.start)
            end = Self.parse(endState, fallback: fallback.end)
        }

        /// Start is not before end; `false` while either side can't be read (web `isVacationDateRangeInvalid`).
        public func isInvalid(calendar: Calendar = .current) -> Bool {
            guard let start = start.date(in: calendar), let end = end.date(in: calendar) else { return false }
            return start >= end
        }

        /// The end is still ahead (web `isVacationDateRangeFuture`).
        public func isFuture(now: Date = .now, calendar: Calendar = .current) -> Bool {
            end.date(in: calendar).map { $0 > now } ?? false
        }

        /// Reads `YYYY-MM-DD HH:MM[:SS]` (or with `T`) part by part (web `parsedInputDateTime`).
        static func parse(_ state: String?, fallback: WallClock) -> WallClock {
            let parts = (state ?? "").replacingOccurrences(of: "T", with: " ").split(separator: " ", maxSplits: 1).map(String.init)
            let date = parts.first.flatMap { WallClock.isDate($0) ? $0 : nil } ?? fallback.date
            let time = parts.count > 1 ? String(parts[1].prefix(5)) : ""
            return WallClock(date: date, time: WallClock.isTime(time) ? time : fallback.time)
        }
    }

    // MARK: - Service calls

    /// `input_datetime.set_datetime` for one helper (web `inputDateTimeServiceData`).
    public static func setDateTime(_ entityId: String, _ value: WallClock) -> ServiceCall {
        ServiceCall("input_datetime", "set_datetime", target: entityId, data: [
            "date": .string(value.date), "time": .string(value.timeWithSeconds),
        ])
    }

    /// `input_boolean.turn_on` / `turn_off`.
    public static func setBoolean(_ entityId: String, on: Bool) -> ServiceCall {
        ServiceCall("input_boolean", on ? "turn_on" : "turn_off", target: entityId)
    }

    /// Confirming a vacation: save both dates, clear the invalid flag, then enable (web `confirmVacation`).
    public static func confirmCalls(_ range: DateRange) -> [ServiceCall] {
        [
            setDateTime(startEntityId, range.start),
            setDateTime(endEntityId, range.end),
            setBoolean(invalidDatesPendingEntityId, on: false),
            setBoolean(modeEntityId, on: true),
        ]
    }

    /// Disabling: turn the mode and the invalid flag off and reset the checklist (web `disableVacation`).
    public static func disableCalls() -> [ServiceCall] {
        [setBoolean(modeEntityId, on: false), setBoolean(invalidDatesPendingEntityId, on: false)]
            + checklist.map { setBoolean($0.entityId, on: false) }
    }

    /// Fixing the dates of a vacation Home Assistant paused for invalid dates re-enables it
    /// (web `VacationDateControls.updateDateTime`).
    public static func recoveryCalls() -> [ServiceCall] {
        [setBoolean(modeEntityId, on: true), setBoolean(invalidDatesPendingEntityId, on: false)]
    }

    // MARK: - Routing

    /// Which page the Vacation entry shows.
    public enum Route: String, Hashable, Sendable {
        case chooser, vacationMode, soloTrip
    }

    /// An engaged mode skips the chooser (web `vacationFeaturePath`).
    public static func route(snapshot: HouseholdAway.Snapshot, vacationModeOn: Bool, invalidDatesPending: Bool) -> Route {
        if snapshot.isEngaged(.vacation) || vacationModeOn || invalidDatesPending { return .vacationMode }
        if snapshot.isEngaged(.soloTrip) { return .soloTrip }
        return .chooser
    }
}
