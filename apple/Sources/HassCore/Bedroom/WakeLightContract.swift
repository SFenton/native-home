import Foundation

/// The `wake_light` integration's read and command contract (web `wakeLightContract.ts`,
/// `ha-sfenton-react-dash@9ac2a46:src/components/hass/wakeLights/wakeLightContract.ts`; server
/// `SFenton/ha-wake-light`). The status sensor's attributes carry everything; changes go through
/// `wake_light.command`, which answers with an outcome.
public enum WakeLight {
    /// Contract versions this app reads (web: 4…6).
    public static let supportedContracts: ClosedRange<Int> = 4...6
    /// Ramp choices (minutes).
    public static let rampMinutes: [Int] = [0, 5, 10, 15, 30]
    /// Post-wake hold choices (minutes).
    public static let holdMinutes: [Int] = [5, 10, 15, 30]

    // MARK: - Types

    /// The integration's run phase.
    public enum Phase: String, CaseIterable, Sendable {
        case blockedVacation = "blocked_vacation"
        case degraded, holding, idle, ramping, recovering, scheduled, snoozed, unavailable

        /// The light is running for a wake.
        public var isActive: Bool { self == .ramping || self == .holding || self == .snoozed }

        /// Copy for the phase (web `phases`; snoozed reads as holding, as on the web).
        public var label: String {
            switch self {
            case .idle: "Idle"
            case .scheduled: "Wake Scheduled"
            case .ramping: "Brightening Gradually"
            case .holding, .snoozed: "Holding Brightness"
            case .recovering: "Waiting to Resume"
            case .blockedVacation, .degraded: "Execution Blocked"
            case .unavailable: "Unavailable"
            }
        }
    }

    /// Recurring or one-time.
    public enum Kind: String, CaseIterable, Sendable {
        case weekly, once

        /// `Scheduled` / `One-Time`.
        public var label: String { self == .weekly ? "Scheduled" : "One-Time" }
    }

    /// One wake alarm: native (owned by the wake light) or mirrored from a bed side.
    public struct Alarm: Hashable, Sendable, Identifiable {
        public var id: String
        public var label: String
        public var kind: Kind
        /// `HH:MM`.
        public var localTime: String
        public var weekdays: [Weekday]
        /// `YYYY-MM-DD` for one-time alarms.
        public var date: String?
        public var enabled: Bool
        public var rampMinutes: Int
        public var revision: Int
        /// `native` or `sleepypod`.
        public var source: String
        public var sourceLabel: String?
        /// `sleepypod:left` for bed alarms.
        public var sourceRef: String?
        /// Bed sides a one-time alarm also rings.
        public var bedSides: [BedSide]

        public var isNative: Bool { source == "native" }

        public init(id: String, label: String, kind: Kind, localTime: String, weekdays: [Weekday] = [], date: String? = nil,
                    enabled: Bool = true, rampMinutes: Int = 30, revision: Int = 0, source: String = "native",
                    sourceLabel: String? = nil, sourceRef: String? = nil, bedSides: [BedSide] = []) {
            self.id = id
            self.label = label
            self.kind = kind
            self.localTime = localTime
            self.weekdays = weekdays
            self.date = date
            self.enabled = enabled
            self.rampMinutes = rampMinutes
            self.revision = revision
            self.source = source
            self.sourceLabel = sourceLabel
            self.sourceRef = sourceRef
            self.bedSides = bedSides
        }

        /// A new one-time alarm for tomorrow at 07:00 (web `createWakeLightAlarm`).
        public static func new(id: String, label: String = "Morning Alarm", now: Date = .now, defaults: Defaults = .standard,
                               calendar: Calendar = .current) -> Alarm {
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
            return Alarm(id: id, label: label, kind: .once, localTime: "07:00", date: WakeLight.dateString(tomorrow, calendar: calendar),
                         rampMinutes: defaults.rampMinutes)
        }

        /// The fields an edit can change, to tell whether a draft differs from the saved alarm.
        public func sameEdits(as other: Alarm) -> Bool {
            label.trimmingCharacters(in: .whitespaces) == other.label.trimmingCharacters(in: .whitespaces)
                && kind == other.kind && localTime == other.localTime && Weekday.ordered(weekdays) == Weekday.ordered(other.weekdays)
                && date == other.date && enabled == other.enabled && rampMinutes == other.rampMinutes && bedSides == other.bedSides
        }

        /// The days this mirrored alarm's wake link covers (web `wakeLightAlarmLinkDays`).
        public func linkDays(calendar: Calendar = .current) -> [Weekday] {
            guard !isNative, sourceRef != nil else { return [] }
            if kind == .weekly { return weekdays }
            guard let date, let parsed = WakeLight.date(date, calendar: calendar) else { return [] }
            return [Weekday(date: parsed, calendar: calendar)]
        }

        /// The link keys covering this mirrored alarm.
        public func linkKeys(calendar: Calendar = .current) -> [String] {
            guard let sourceRef else { return [] }
            return linkDays(calendar: calendar).map { WakeLight.linkKey(source: sourceRef, day: $0, time: localTime) }
        }

        /// The service payload (web `alarmPayload`). The web's `null` date and source are left out: the integration
        /// reads them with `.get`, and a JSON `null` can't travel through `[String: any Sendable]`.
        var payload: [String: any Sendable] {
            var payload: [String: any Sendable] = [
                "bed_sides": kind == .once ? bedSides.map(\.rawValue) : [String](),
                "enabled": enabled,
                "id": id,
                "kind": kind.rawValue,
                "label": label,
                "local_time": localTime,
                "ramp_minutes": rampMinutes,
                "revision": revision,
                "source": source,
                "weekdays": kind == .weekly ? weekdays.map(\.rawValue) : [String](),
            ]
            if kind == .once, let date { payload["date"] = date }
            if let sourceRef { payload["source_ref"] = sourceRef }
            return payload
        }
    }

    /// Room defaults.
    public struct Defaults: Hashable, Sendable {
        public var rampMinutes: Int
        public var postWakeHoldMinutes: Int

        public init(rampMinutes: Int, postWakeHoldMinutes: Int) {
            self.rampMinutes = rampMinutes
            self.postWakeHoldMinutes = postWakeHoldMinutes
        }

        public static let standard = Defaults(rampMinutes: 30, postWakeHoldMinutes: 5)
    }

    /// A wake in progress.
    public struct Occurrence: Hashable, Sendable, Identifiable {
        public var id: String
        public var alarmId: String
        public var phase: Phase
        public var progress: Double
        public var wakeAt: String
    }

    /// Room safety facts the integration reports.
    public struct Safety: Hashable, Sendable {
        public var vacationState: String
    }

    /// Everything the status sensor reports (web `WakeLightSnapshot`).
    public struct Snapshot: Equatable, Sendable {
        public var available: Bool
        public var compatible: Bool
        public var contractVersion: Int
        public var phase: Phase
        public var profileId: String
        public var revision: Int
        public var alarms: [Alarm]
        public var defaults: Defaults
        /// Link keys explicitly turned off (absent means linked).
        public var unlinkedKeys: Set<String>
        public var activeOccurrences: [Occurrence]
        public var currentBlockers: [String]
        public var episodeRef: String?
        public var commandedBrightnessPct: Double
        public var progress: Double
        public var nextWakeAt: String?
        public var nextRampMinutes: Int?
        public var safety: Safety

        /// Whether a link key is on.
        public func isLinked(_ key: String) -> Bool { !unlinkedKeys.contains(key) }

        /// Whether a mirrored alarm drives the wake light on any of its days (web `wakeLightAlarmLinked`).
        public func isLinked(_ alarm: Alarm, calendar: Calendar = .current) -> Bool {
            let keys = alarm.linkKeys(calendar: calendar)
            return keys.isEmpty || keys.contains(where: isLinked)
        }
    }

    // MARK: - Parsing

    /// Reads the status sensor (web `wakeLightSnapshotFromEntity`).
    public static func snapshot(_ entity: EntityState?, profileId fallbackProfile: String) -> Snapshot {
        let attributes = entity?.attributes ?? [:]
        let state = entity?.state ?? "unavailable"
        let contract = integer(attributes["contract_version"]) ?? 0
        let compatible = supportedContracts.contains(contract)
        let available = entity != nil && state != "unknown" && state != "unavailable" && compatible
            && attributes["command_available"]?.bool == true
        let defaultsSource = object(attributes["defaults"])
        func defaultsValue(_ key: String) -> JSONValue? { defaultsSource?[key] ?? attributes[key] }
        let unlinked: Set<String> = {
            guard case let .object(links)? = attributes["alarm_links"] else { return [] }
            return Set(links.filter { $0.value == .bool(false) }.map(\.key))
        }()
        let safety = object(attributes["safety"])
        return Snapshot(
            available: available,
            compatible: compatible,
            contractVersion: contract,
            phase: Phase(rawValue: state) ?? .unavailable,
            profileId: attributes["profile_id"]?.string ?? fallbackProfile,
            revision: integer(attributes["revision"]) ?? 0,
            alarms: (attributes["alarms"]?.array ?? []).compactMap(alarm),
            defaults: Defaults(
                rampMinutes: Int(clamped(defaultsValue("ramp_minutes"), 0...60) ?? 30),
                postWakeHoldMinutes: Int(clamped(defaultsValue("post_wake_hold_minutes"), 5...30) ?? 5)
            ),
            unlinkedKeys: unlinked,
            activeOccurrences: (attributes["active_occurrences"]?.array ?? []).compactMap(occurrence),
            currentBlockers: strings(attributes["current_blockers"]),
            episodeRef: nonEmpty(attributes["episode_ref"]?.string),
            commandedBrightnessPct: clamped(attributes["commanded_brightness_pct"], 0...100) ?? 0,
            progress: clamped(attributes["progress"], 0...100) ?? 0,
            nextWakeAt: nonEmpty(attributes["next_wake_at"]?.string),
            nextRampMinutes: attributes["next_ramp_minutes"].flatMap { value in value == .null ? nil : clamped(value, 0...60).map { Int($0) } },
            safety: Safety(vacationState: (safety?["vacation_state"] ?? attributes["vacation_state"])?.string ?? "unknown")
        )
    }

    static func alarm(_ value: JSONValue) -> Alarm? {
        guard let id = nonEmpty(value["id"]?.string), let label = nonEmpty(value["label"]?.string),
              let kind = value["kind"]?.string.flatMap(Kind.init(rawValue:)),
              let time = value["local_time"]?.string, isValidTime(time) else { return nil }
        let weekdays = (value["weekdays"]?.array ?? []).compactMap { $0.string.flatMap(Weekday.init(rawValue:)) }
        let date = nonEmpty(value["date"]?.string)
        if kind == .weekly && weekdays.isEmpty { return nil }
        if kind == .once && date == nil { return nil }
        let sides = (value["bed_sides"]?.array ?? []).compactMap { $0.string.flatMap(BedSide.init(rawValue:)) }
        return Alarm(
            id: id, label: label, kind: kind, localTime: time, weekdays: weekdays, date: date,
            enabled: value["enabled"]?.bool != false,
            rampMinutes: Int(clamped(value["ramp_minutes"], 0...60) ?? 30),
            revision: integer(value["revision"]) ?? 0,
            source: value["source"]?.string == "sleepypod" ? "sleepypod" : "native",
            sourceLabel: nonEmpty(value["source_label"]?.string),
            sourceRef: nonEmpty(value["source_ref"]?.string),
            bedSides: BedSide.allCases.filter(sides.contains)
        )
    }

    static func occurrence(_ value: JSONValue) -> Occurrence? {
        guard let id = nonEmpty((value["occurrence_id"] ?? value["id"])?.string),
              let alarmId = nonEmpty(value["alarm_id"]?.string),
              let wakeAt = nonEmpty(value["wake_at"]?.string) else { return nil }
        return Occurrence(id: id, alarmId: alarmId, phase: value["phase"]?.string.flatMap(Phase.init(rawValue:)) ?? .idle,
                          progress: clamped(value["progress"], 0...100) ?? 0, wakeAt: wakeAt)
    }

    // MARK: - Links and validation

    /// `sleepypod:left#monday#07:00` (web `wakeLightAlarmLinkKey`).
    public static func linkKey(source: String, day: Weekday, time: String) -> String { "\(source)#\(day.rawValue)#\(time)" }

    /// Strict `HH:MM`.
    public static func isValidTime(_ value: String) -> Bool { ClockTime.isValid(value) }

    /// What blocks saving a draft (web `validateWakeLightAlarm`), in display order; empty when valid.
    public static func problems(_ alarm: Alarm, now: Date = .now, calendar: Calendar = .current) -> [String] {
        var problems: [String] = []
        if alarm.label.trimmingCharacters(in: .whitespaces).isEmpty { problems.append("Wake alarm name is required. Enter a name.") }
        if !isValidTime(alarm.localTime) { problems.append("Wake time is invalid. Choose a valid time.") }
        if !rampMinutes.contains(alarm.rampMinutes) { problems.append("Choose a supported light ramp duration before saving.") }
        if alarm.kind == .weekly && alarm.weekdays.isEmpty { problems.append("A recurring alarm requires at least one weekday.") }
        if alarm.kind == .once && alarm.enabled {
            let at = alarm.date.flatMap { dateTime($0, alarm.localTime, calendar: calendar) }
            if at.map({ $0 <= now }) ?? true { problems.append("A one-time alarm requires a future date.") }
        }
        return problems
    }

    // MARK: - Commands

    /// One `wake_light.command` operation (web `WakeLightCommandOperation`).
    public enum Command: Sendable {
        case upsert(Alarm)
        case delete(alarmId: String)
        case link(keys: [String], enabled: Bool)
        case updateDefaults(Defaults)
        case endEpisode

        public var operation: String {
            switch self {
            case .upsert: "upsert_alarm"
            case .delete: "delete_alarm"
            case .link: "link_alarm"
            case .updateDefaults: "update_defaults"
            case .endEpisode: "end_episode"
            }
        }

        /// Keys that stop the same thing being sent twice at once (web `commandPendingKeys`).
        public var pendingKeys: [String] {
            switch self {
            case let .upsert(alarm): ["alarm:\(alarm.id)"]
            case let .delete(id): ["alarm:\(id)"]
            case let .link(keys, _): keys.map { "link:\($0)" }
            case .updateDefaults: ["defaults"]
            case .endEpisode: ["end_episode"]
            }
        }
    }

    /// Service data for `wake_light.command` (web `wakeLightServiceCall`).
    public static func serviceData(_ command: Command, snapshot: Snapshot, requestId: String) -> [String: any Sendable] {
        var data: [String: any Sendable] = [
            "expected_revision": snapshot.revision,
            "operation": command.operation,
            "profile_id": snapshot.profileId,
            "request_id": requestId,
        ]
        switch command {
        case let .upsert(alarm): data["alarm"] = alarm.payload
        case let .delete(id): data["alarm_id"] = id
        case let .link(keys, enabled):
            data["enabled"] = enabled
            data["link_keys"] = keys
        case let .updateDefaults(defaults):
            data["defaults"] = ["post_wake_hold_minutes": defaults.postWakeHoldMinutes, "ramp_minutes": defaults.rampMinutes]
        case .endEpisode:
            if let episode = snapshot.episodeRef { data["episode_ref"] = episode }
        }
        return data
    }

    /// Copy for an error code from a command response (web `useWakeLightController` `error`).
    public static func errorMessage(_ code: String) -> String {
        switch code {
        case "revision_conflict", "request_id_conflict": "Alarm configuration changed elsewhere. Review the latest settings before retrying."
        case "episode_duration_exceeded": "Connected alarms exceed 105 minutes. Reduce their ramps or separate their execution windows."
        case "no_active_occurrence", "occurrence_already_ended": "That wake episode ended or changed. Review the active episode before retrying."
        case "transport": "Home Assistant did not confirm the change. Check the connection before retrying."
        case "unavailable": "Wake-light controls are unavailable. Check Home Assistant, then try again."
        default: "The wake light change was rejected. Review the settings, then try again."
        }
    }

    /// Copy for a readiness blocker (web `blockedMessage`).
    public static func blockerMessage(_ code: String) -> String {
        if code.hasPrefix("source") {
            return "The linked alarm schedule or scheduled wake is unavailable, so the wake light cannot start. Check the device connection and integration compatibility."
        }
        switch code {
        case "pbl_not_ready": return "Presence lighting is not ready to hand control to the wake light, so the wake cannot start safely. Check presence lighting before trying again."
        case "blocker_not_off": return "Another lighting controller is active or its status is unknown, so the wake cannot start. Ensure the wake light has exclusive control, then try again."
        case "legacy_brightness_255_lifecycle_unresolved": return "The room's older lighting behavior is not confirmed compatible with wake-light control, so the wake light cannot start. Complete setup before trying again."
        case "target_unavailable": return "A required room light is unavailable, so the wake light cannot start. Check the light's connection, then try again."
        case "vacation_not_off": return "Vacation Mode · Runs Blocked"
        case "episode_duration_exceeded": return errorMessage(code)
        default: return errorMessage("unavailable")
        }
    }

    // MARK: - Display

    /// The tile and sheet subtitle (web `tileSubtitle`).
    public static func subtitle(_ snapshot: Snapshot, modal: Bool = false, calendar: Calendar = .current) -> String {
        guard snapshot.available else { return "Setup · Unavailable" }
        if snapshot.phase == .recovering || snapshot.phase == .snoozed { return snapshot.phase.label }
        if snapshot.phase.isActive { return "Active • \(Int(snapshot.commandedBrightnessPct.rounded()))%" }
        if !snapshot.alarms.contains(where: \.enabled) { return modal ? "No Active Wake-Light Alarms" : "Alarms · None Enabled" }
        if snapshot.safety.vacationState != "off" { return "Vacation Mode · Runs Blocked" }
        if !snapshot.currentBlockers.isEmpty { return "Execution Blocked" }
        if let next = snapshot.nextWakeAt {
            let date = timestamp(next).map { "\(calendar.component(.month, from: $0))/\(calendar.component(.day, from: $0))" } ?? "—"
            let time = displayTime(next, calendar: calendar)
            if let ramp = snapshot.nextRampMinutes { return "Next Alarm: \(date) \(time) • \(ramp) min ramp" }
            return "Next Alarm: \(date) \(time)"
        }
        return Phase.idle.label
    }

    /// Whether the Wake-Light tile fills: a wake is running now (ramping, holding or snoozed) on an available light.
    /// An armed alarm that is waiting, blocked or in vacation mode does not fill.
    public static func fillsTile(_ snapshot: Snapshot) -> Bool { snapshot.available && snapshot.phase.isActive }

    /// Whether the Wake-Light room card fills, from the status sensor's state (the phase).
    public static func fillsTile(statusState: String?) -> Bool { statusState.flatMap(Phase.init(rawValue:))?.isActive ?? false }

    /// `Every Day`, `Weekdays`, `Weekends`, `Mon, Wed`, or a one-time date (web `scheduleLabel`).
    public static func scheduleLabel(_ alarm: Alarm, calendar: Calendar = .current) -> String {
        if alarm.kind == .once {
            guard let date = alarm.date, let parsed = WakeLight.date(date, calendar: calendar) else { return "—" }
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.locale = Locale(identifier: "en_US")
            formatter.setLocalizedDateFormatFromTemplate("MMMdyyyy")
            return formatter.string(from: parsed)
        }
        let days = Weekday.ordered(alarm.weekdays)
        if days.count == 7 { return "Every Day" }
        if days == Weekday.workdays { return "Weekdays" }
        if days == Weekday.weekend { return "Weekends" }
        return days.map(\.shortLabel).joined(separator: ", ")
    }

    /// `7:00 AM` from `HH:MM` or an ISO timestamp.
    public static func displayTime(_ value: String, calendar: Calendar = .current) -> String {
        if let date = timestamp(value) {
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            return ClockTime.display(String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0))
        }
        return ClockTime.display(value)
    }

    /// `7 minutes` style ramp copy for rows (`None` for 0).
    public static func rampLabel(_ minutes: Int) -> String { minutes == 0 ? "None" : "\(minutes) min" }

    /// `5 Minutes` style copy for the duration pickers.
    public static func durationLabel(_ minutes: Int) -> String { minutes == 0 ? "None" : "\(minutes) Minutes" }

    // MARK: - Helpers

    static func timestamp(_ value: String) -> Date? { HassDates.iso8601(value) }

    /// `YYYY-MM-DD` in `calendar`.
    public static func dateString(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Midnight of `YYYY-MM-DD` in `calendar`.
    public static func date(_ value: String, calendar: Calendar = .current) -> Date? {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    static func dateTime(_ date: String, _ time: String, calendar: Calendar) -> Date? {
        guard isValidTime(time), let day = WakeLight.date(date, calendar: calendar) else { return nil }
        return calendar.date(byAdding: .minute, value: ClockTime.minutes(time), to: day)
    }

    static func object(_ value: JSONValue?) -> JSONValue? {
        if case .object? = value { return value }
        return nil
    }

    static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return value
    }

    static func integer(_ value: JSONValue?) -> Int? { value.flatMap(BedAlarm.number).map { max(0, Int($0.rounded())) } }

    static func clamped(_ value: JSONValue?, _ range: ClosedRange<Double>) -> Double? {
        value.flatMap(BedAlarm.number).map { min(range.upperBound, max(range.lowerBound, $0)) }
    }

    static func strings(_ value: JSONValue?) -> [String] {
        (value?.array ?? []).compactMap { nonEmpty($0.string) }
    }
}

// MARK: - Bed alarm provisioning

/// Planning "Add to <bed>" when saving a weekly wake alarm (web `bedAlarmProvisioning.ts`).
public enum BedAlarmProvisioning {
    /// What saving does to one bed side.
    public struct Plan: Equatable, Sendable {
        /// Days that get a new bed alarm.
        public var createDays: [Weekday] = []
        public var linkKeysOn: [String] = []
        public var linkKeysOff: [String] = []

        public var isEmpty: Bool { createDays.isEmpty && linkKeysOn.isEmpty && linkKeysOff.isEmpty }
    }

    /// The days `alarms` already ring at `time`.
    public static func days(of alarms: [BedAlarm], at time: String) -> [Weekday] {
        guard let target = ClockTime.normalized(time) else { return [] }
        return Weekday.ordered(alarms.filter { ClockTime.normalized($0.time) == target }.map(\.day))
    }

    /// Plans one side (web `planBedAlarmProvision`). A toggle on creates missing alarms and turns links on; a toggle
    /// off turns off links for alarms that exist. Bed alarms are only ever created, never deleted.
    public static func plan(snapshot: WakeLight.Snapshot, days: [Weekday], linked: Bool, alarms: [BedAlarm],
                            source: String, time: String) -> Plan? {
        guard let target = ClockTime.normalized(time), !source.isEmpty else { return nil }
        let existing = Set(Self.days(of: alarms, at: target))
        var plan = Plan()
        for day in Weekday.ordered(days) {
            let key = WakeLight.linkKey(source: source, day: day, time: target)
            let currentlyLinked = snapshot.isLinked(key)
            let exists = existing.contains(day)
            if !exists && linked { plan.createDays.append(day) }
            if linked && !currentlyLinked { plan.linkKeysOn.append(key) }
            if !linked && exists && currentlyLinked { plan.linkKeysOff.append(key) }
        }
        return plan
    }
}
