import Foundation

/// The Household Away contract: one plan (Solo Trip or Vacation) published by the Household Away status sensor
/// and changed only through the queued the Household Away command script
/// (web `src/components/hass/householdAway/householdAwayContract.ts`).
public enum HouseholdAway {
    // MARK: - Entities

    /// The status sensor: the document's `bedroom.householdAwayEntityId`.
    public static var statusEntityId: String { HouseConfigSource.active.read { $0.bedroom.householdAwayEntityId } ?? "" }
    /// The command script's domain.
    public static let commandDomain = "script"
    /// The command script's service: the document's `bedroom.householdAwayScript`.
    public static var commandService: String { HouseConfigSource.active.read { $0.bedroom.householdAwayScript } ?? "" }
    /// The only contract version this app understands.
    public static let contractVersion = 1

    // MARK: - Values

    /// Which plan is engaged.
    public enum Mode: String, Sendable {
        case none
        case soloTrip = "solo_trip"
        case vacation
    }

    /// The plan's lifecycle.
    public enum State: String, CaseIterable, Sendable {
        case activating, active, degraded, ending, idle, scheduled
        case restoreRequired = "restore_required"
    }

    /// How a `restore_required` plan is resolved.
    public enum ResolveAction: String, Sendable {
        case keepCurrent = "keep_current"
        case restoreSaved = "restore_saved"
    }

    /// Effects Home Assistant has confirmed for an active Solo Trip.
    public struct Effects: Equatable, Sendable {
        public var sleepypodLiveFollow = false
        public var sleepypodSchedule = false
        public var wakeLightSource = false

        public init(sleepypodLiveFollow: Bool = false, sleepypodSchedule: Bool = false, wakeLightSource: Bool = false) {
            self.sleepypodLiveFollow = sleepypodLiveFollow
            self.sleepypodSchedule = sleepypodSchedule
            self.wakeLightSource = wakeLightSource
        }

        /// All three effects confirmed.
        public var all: Bool { sleepypodLiveFollow && sleepypodSchedule && wakeLightSource }
    }

    // MARK: - Snapshot

    /// The parsed status sensor (web `householdAwaySnapshotFromEntity`).
    public struct Snapshot: Equatable, Sendable {
        public var available: Bool
        public var blockers: [String]
        public var commandAvailable: Bool
        public var compatible: Bool
        public var contractVersion: Int
        public var effects: Effects
        public var endsAt: String?
        public var homeResident: HouseholdResident?
        public var mode: Mode
        public var revision: Int
        public var startsAt: String?
        public var state: State
        public var traveler: HouseholdResident?

        /// Parses the sensor; a missing, unavailable or incompatible sensor is idle and unavailable.
        public init(entity: EntityState?) {
            let attributes = entity?.attributes ?? [:]
            let rawState = entity?.state ?? "unavailable"
            contractVersion = Self.integer(attributes["contract_version"])
            compatible = contractVersion == HouseholdAway.contractVersion
            state = State(rawValue: rawState) ?? .idle
            available = entity != nil && rawState != "unknown" && rawState != "unavailable" && compatible
            blockers = attributes["blockers"]?.array?.compactMap(\.string).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? []
            commandAvailable = attributes["command_available"]?.bool == true
            effects = Effects(
                sleepypodLiveFollow: attributes["effects"]?["sleepypod_live_follow"]?.bool == true,
                sleepypodSchedule: attributes["effects"]?["sleepypod_schedule"]?.bool == true,
                wakeLightSource: attributes["effects"]?["wake_light_source"]?.bool == true
            )
            endsAt = Self.nonEmpty(attributes["ends_at"])
            startsAt = Self.nonEmpty(attributes["starts_at"])
            homeResident = attributes["home_resident"]?.string.flatMap { HouseholdResident(soloTripId: $0) }
            traveler = attributes["traveler"]?.string.flatMap { HouseholdResident(soloTripId: $0) }
            mode = attributes["mode"]?.string.flatMap(Mode.init(rawValue:)) ?? .none
            revision = Self.integer(attributes["revision"])
        }

        /// The script can take commands right now.
        public var canCommand: Bool { available && commandAvailable }

        /// `mode` is engaged in any state but idle (web `householdAwayModeEngaged`).
        public func isEngaged(_ mode: Mode) -> Bool { self.mode == mode && state != .idle }

        /// A Solo Trip with every effect confirmed: the only case that earns the green notice
        /// (web `householdAwayFullyActive`).
        public var isFullyActive: Bool { mode == .soloTrip && state == .active && effects.all }

        /// The traveler is away now: Solo Trip past scheduling and not yet idle.
        public var isTravelerAway: Bool {
            mode == .soloTrip && traveler != nil && state != .idle && state != .scheduled
        }

        /// Starting or started, before effects are confirmed; presented optimistically as active.
        public var isActivationSettling: Bool { mode == .soloTrip && (state == .activating || state == .active) }

        /// The departure time as wall-clock parts.
        public var start: WallClock? { startsAt.flatMap(WallClock.init(parsing:)) }
        /// The return time as wall-clock parts.
        public var end: WallClock? { endsAt.flatMap(WallClock.init(parsing:)) }

        private static func integer(_ value: JSONValue?) -> Int {
            max(0, Int((value?.finiteNumber ?? 0).rounded()))
        }

        private static func nonEmpty(_ value: JSONValue?) -> String? {
            guard let string = value?.string, !string.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return string
        }
    }

    // MARK: - Commands

    /// One request to the command script.
    public enum Command: Equatable, Sendable {
        case cancel
        case endNow
        case resolveRestore(ResolveAction)
        case scheduleSoloTrip(traveler: HouseholdResident, start: WallClock, end: WallClock)
        case updateEnd(WallClock)

        /// The `operation` field.
        public var operation: String {
            switch self {
            case .cancel: "cancel"
            case .endNow: "end_now"
            case .resolveRestore: "resolve_restore"
            case .scheduleSoloTrip: "schedule"
            case .updateEnd: "update_end"
            }
        }
    }

    /// Service data for the command script (web `householdAwayServiceCall`). `expected_revision` lets the
    /// script reject a command built from stale state; `request_id` makes retries idempotent.
    public static func serviceData(for command: Command, expectedRevision: Int, requestId: String) -> [String: JSONValue] {
        var data: [String: JSONValue] = [
            "expected_revision": .number(Double(expectedRevision)),
            "operation": .string(command.operation),
            "request_id": .string(requestId),
        ]
        switch command {
        case .cancel, .endNow: break
        case let .resolveRestore(action):
            data["resolve_action"] = .string(action.rawValue)
        case let .scheduleSoloTrip(traveler, start, end):
            data["mode"] = .string(Mode.soloTrip.rawValue)
            data["traveler"] = .string(traveler.soloTripId)
            data["start_date"] = .string(start.date)
            data["start_time"] = .string(start.time)
            data["end_date"] = .string(end.date)
            data["end_time"] = .string(end.time)
        case let .updateEnd(end):
            data["end_date"] = .string(end.date)
            data["end_time"] = .string(end.time)
        }
        return data
    }
}

// MARK: - Wall clock

/// A local date and minute as Home Assistant's helpers store them: `YYYY-MM-DD` and `HH:MM`.
///
/// Kept as strings so confirmation compares exactly what was sent, as the web does; ``date(in:)`` and
/// ``init(_:calendar:)`` convert for the native pickers.
public struct WallClock: Hashable, Sendable {
    public var date: String
    public var time: String

    /// Creates a value from already formatted parts.
    public init(date: String, time: String) {
        self.date = date
        self.time = time
    }

    /// Parses `2026-10-11T16:30:00-07:00`, `2026-10-11 16:30:00` or `2026-10-11 16:30`; the zone is ignored
    /// because the sensor reports house-local wall time (web `householdAwayWallClockParts`).
    public init?(parsing value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard let separator = trimmed.firstIndex(where: { $0 == "T" || $0 == " " }) else { return nil }
        let datePart = String(trimmed[..<separator])
        let timePart = String(trimmed[trimmed.index(after: separator)...].prefix(5))
        guard Self.isDate(datePart), Self.isTime(timePart) else { return nil }
        self.init(date: datePart, time: timePart)
    }

    /// The wall-clock parts of `instant` in `calendar`'s zone, to the minute.
    public init(_ instant: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: instant)
        date = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        time = String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    /// The instant in `calendar`'s zone, or `nil` if a part is malformed.
    public func date(in calendar: Calendar = .current) -> Date? {
        guard Self.isDate(date), Self.isTime(time) else { return nil }
        let day = date.split(separator: "-").compactMap { Int($0) }
        let clock = time.split(separator: ":").compactMap { Int($0) }
        guard day.count == 3, clock.count == 2 else { return nil }
        let components = DateComponents(year: day[0], month: day[1], day: day[2], hour: clock[0], minute: clock[1])
        guard let resolved = calendar.date(from: components),
              calendar.component(.day, from: resolved) == day[2] else { return nil }
        return resolved
    }

    /// `time` with seconds, as `input_datetime.set_datetime` takes it.
    public var timeWithSeconds: String { time.count == 5 ? time + ":00" : time }

    static func isDate(_ value: String) -> Bool {
        value.count == 10 && value.enumerated().allSatisfy { index, character in
            index == 4 || index == 7 ? character == "-" : character.isASCII && character.isNumber
        }
    }

    static func isTime(_ value: String) -> Bool {
        guard value.count == 5, value.enumerated().allSatisfy({ index, character in
            index == 2 ? character == ":" : character.isASCII && character.isNumber
        }) else { return false }
        let parts = value.split(separator: ":").compactMap { Int($0) }
        return parts.count == 2 && parts[0] < 24 && parts[1] < 60
    }
}

// MARK: - Solo Trip drafts

/// The Solo Trip editor's dates (web `SoloTripDraft`).
public struct SoloTripDraft: Equatable, Sendable {
    public var start: WallClock
    public var end: WallClock

    public init(start: WallClock, end: WallClock) {
        self.start = start
        self.end = end
    }

    /// Departure now (to the minute), return three days later (web `defaultSoloTripDraft`).
    public static func makeDefault(now: Date = .now, calendar: Calendar = .current) -> SoloTripDraft {
        let end = calendar.date(byAdding: .day, value: 3, to: now) ?? now
        return SoloTripDraft(start: WallClock(now, calendar: calendar), end: WallClock(end, calendar: calendar))
    }

    /// Return is after departure.
    public func endAfterStart(calendar: Calendar = .current) -> Bool {
        guard let start = start.date(in: calendar), let end = end.date(in: calendar) else { return false }
        return end > start
    }

    /// Ready to schedule for `traveler` (web `validateSoloTripDraft`).
    public func isValid(traveler: HouseholdResident?, calendar: Calendar = .current) -> Bool {
        traveler != nil && endAfterStart(calendar: calendar)
    }
}

/// Validation of a new return time for an engaged Solo Trip (web `validateSoloTripEndDraft`).
public struct SoloTripReturnValidation: Equatable, Sendable {
    public var endAfterStart: Bool
    public var endInFuture: Bool
    public var isValid: Bool { endAfterStart && endInFuture }

    /// Validates `end` against the plan's `start` and `now`.
    public init(end: WallClock, start: WallClock?, now: Date = .now, calendar: Calendar = .current) {
        let endDate = end.date(in: calendar)
        let startDate = start?.date(in: calendar)
        if let endDate, let startDate { endAfterStart = endDate > startDate } else { endAfterStart = false }
        endInFuture = endDate.map { $0 > now } ?? false
    }
}
