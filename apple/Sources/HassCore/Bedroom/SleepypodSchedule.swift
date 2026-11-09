import Foundation

// MARK: - Schedule phase

/// A stage of the Pod's nightly schedule (web `bedTemperatureScope.ts`).
public enum SchedulePhase: String, CaseIterable, Codable, Hashable, Sendable {
    case bedtime, asleep, dawn

    /// `Bedtime`.
    public var label: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    /// SF Symbol for the stage (web `mdi:bed`, `mdi:moon-waning-crescent`, `mdi:weather-sunny`).
    public var symbol: String {
        switch self {
        case .bedtime: "bed.double"
        case .asleep: "moon"
        case .dawn: "sun.max"
        }
    }

    /// The phase a the schedule-phase sensor state names, or `nil` (including `outside`).
    public init?(state: String?) {
        guard let state, let phase = Self(rawValue: state.trimmingCharacters(in: .whitespaces).lowercased()) else { return nil }
        self = phase
    }

    /// The phase sensor reports something usable: a phase, or `outside` the schedule.
    public static func isAvailable(_ state: String?) -> Bool {
        guard let state else { return false }
        let normalized = state.trimmingCharacters(in: .whitespaces).lowercased()
        return normalized == "outside" || Self(rawValue: normalized) != nil
    }
}

/// Where a bed temperature change applies when a stage is running (web `SleepypodTemperatureScope`).
public enum BedTemperatureScope: String, Sendable {
    /// The current night only.
    case tonight
    /// Also becomes the stage's recurring level.
    case allNights = "all-nights"
}

// MARK: - Alarm state

/// The Pod's alarm sensor (web `sleepypodAlarmState.ts`).
public enum BedAlarmState: String, Sendable {
    case idle, ringing, snoozed, unavailable

    /// Parses `sensor.*_alarm_state`; anything else is unavailable.
    public init(state: String?) {
        self = state.flatMap(Self.init(rawValue:)).flatMap { $0 == .unavailable ? nil : $0 } ?? .unavailable
    }

    /// Ringing or snoozed: the active alarm controls show.
    public var isActive: Bool { self == .ringing || self == .snoozed }

    /// `Ringing`.
    public var label: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    /// How long a snooze lasts (web `SNOOZE_SECONDS`).
    public static let snoozeSeconds: TimeInterval = 5 * 60

    /// `4:59 Remaining` until `snoozedUntil` (epoch seconds), or `nil` without a usable time.
    public static func snoozeRemainingText(snoozedUntil: Double?, now: Date) -> String? {
        guard let snoozedUntil, snoozedUntil.isFinite, snoozedUntil > 0 else { return nil }
        let total = max(0, Int((snoozedUntil - now.timeIntervalSince1970).rounded(.up)))
        return String(format: "%d:%02d Remaining", total / 60, total % 60)
    }
}

// MARK: - Levels

/// The Pod's −10…+10 level scale and its Fahrenheit equivalents (web `eightSleepLevelToFahrenheit`).
public enum BedLevel {
    public static let min: Double = -10
    public static let max: Double = 10
    public static let step: Double = 1
    static let zeroFahrenheit = 82.5
    static let rangeFahrenheit = 27.5

    /// The schedule payload temperature for a level, rounded to whole degrees.
    public static func fahrenheit(level: Double) -> Int {
        Int((zeroFahrenheit + (level / max) * rangeFahrenheit).rounded(.toNearestOrAwayFromZero))
    }

    /// The level for a measured temperature, clamped to `range`.
    public static func level(fahrenheit: Double, range: ClosedRange<Double>) -> Double {
        let level = ((fahrenheit - zeroFahrenheit) / rangeFahrenheit) * max
        return Swift.min(range.upperBound, Swift.max(range.lowerBound, level))
    }

    /// Where the current-temperature marker sits: the live target level once the Pod is within half a degree of
    /// its target temperature, else the converted temperature (web `eightSleepCurrentLevel`).
    public static func currentLevel(current: Double, range: ClosedRange<Double>, targetLevel: Double?, targetTemperature: Double?) -> Double {
        if let targetLevel, let targetTemperature, abs(current - targetTemperature) <= 0.5 {
            return Swift.min(range.upperBound, Swift.max(range.lowerBound, targetLevel))
        }
        return level(fahrenheit: current, range: range)
    }

    /// `+3`, `0`, `-2.5`, or `--` (web `formatEightSleepTargetLevel`).
    public static func format(_ value: Double?) -> String {
        guard let value else { return "--" }
        let text = value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
        return value > 0 ? "+" + text : text
    }

    /// Snaps `value` to `step` from `range.lowerBound`, clamped (web `snapNumberToStep`).
    public static func snap(_ value: Double, range: ClosedRange<Double>, step: Double) -> Double {
        let safe = step > 0 ? step : 1
        let snapped = ((value - range.lowerBound) / safe).rounded() * safe + range.lowerBound
        let places = Double(String(safe).split(separator: ".").dropFirst().first?.count ?? 0)
        let scale = pow(10, places)
        return (Swift.min(range.upperBound, Swift.max(range.lowerBound, snapped)) * scale).rounded() / scale
    }

    /// Heating above +0.5, cooling below −0.5, idle between, off when the side is off (web `eightSleepTemperatureAction`).
    public static func action(targetLevel: Double?, isOn: Bool) -> String {
        guard isOn else { return "off" }
        guard let targetLevel else { return "idle" }
        if targetLevel > 0.5 { return "heating" }
        if targetLevel < -0.5 { return "cooling" }
        return "idle"
    }
}

// MARK: - Clock times

/// `HH:MM` helpers shared by the bed and wake-light schedules.
public enum ClockTime {
    /// The first `HH:MM` in `state` (web `parsedInputTime`), else `fallback`.
    public static func parse(_ state: String?, fallback: String? = nil) -> String? {
        guard let state, let range = state.range(of: #"\b([01]\d|2[0-3]):[0-5]\d"#, options: .regularExpression) else { return fallback }
        return String(state[range])
    }

    /// Strict `HH:MM` (web `isValidScheduleTime`).
    public static func isValid(_ value: String) -> Bool {
        value.range(of: #"^([01]\d|2[0-3]):[0-5]\d$"#, options: .regularExpression) != nil
    }

    /// `7:05 AM` (web `formatClockTime`).
    public static func display(_ value: String) -> String {
        let parts = value.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2 else { return value }
        let hour = parts[0] % 24
        return "\(hour % 12 == 0 ? 12 : hour % 12):\(String(format: "%02d", parts[1])) \(hour >= 12 ? "PM" : "AM")"
    }

    /// Minutes after midnight.
    public static func minutes(_ value: String) -> Int {
        let parts = value.split(separator: ":").compactMap { Int($0) }
        return parts.count >= 2 ? parts[0] * 60 + parts[1] : 0
    }

    /// `H:MM` or `HH:MM[:SS]` normalized to `HH:MM`, or `nil` (web `normalizedBedAlarmTime`).
    public static func normalized(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard trimmed.range(of: #"^\d{1,2}:[0-5]\d(:[0-5]\d)?$"#, options: .regularExpression) != nil else { return nil }
        let parts = trimmed.split(separator: ":")
        guard let hour = Int(parts[0]), hour <= 23 else { return nil }
        return String(format: "%02d", hour) + ":" + parts[1]
    }
}

// MARK: - Alarms

/// One Pod alarm (web `FreeSleepAlarmRecord`). The SleepyPod adapter reports alarms on the day they ring
/// ("execution" day semantics), so ``day`` is the schedule day too.
public struct BedAlarm: Hashable, Sendable, Identifiable {
    public var day: Weekday
    /// `HH:MM`.
    public var time: String
    public var enabled: Bool
    public var alarmTemperature: Double
    public var duration: Double
    public var vibrationIntensity: Double
    /// `rise` or `double`.
    public var vibrationPattern: String
    /// Position among the day's alarms.
    public var index: Int
    public var id: String

    /// The defaults a new alarm takes (web `FREE_SLEEP_DEFAULT_ALARM`).
    public static func new(day: Weekday, time: String, enabled: Bool = true, id: String) -> BedAlarm {
        BedAlarm(day: day, time: time, enabled: enabled, alarmTemperature: 82, duration: 300,
                 vibrationIntensity: 100, vibrationPattern: "rise", index: 0, id: id)
    }

    /// The default time for a new alarm.
    public static let defaultTime = "07:00"

    /// Parses one schedule alarm object (web `normalizeFreeSleepAlarmSchedule`); `nil` without a valid time.
    static func parse(_ value: JSONValue, day: Weekday, index: Int) -> BedAlarm? {
        guard case .object = value, let time = ClockTime.parse(value["time"]?.string) else { return nil }
        let enabled = value["enabled"]?.bool == true
        return BedAlarm(
            day: day, time: time, enabled: enabled,
            alarmTemperature: value["alarmTemperature"].flatMap(Self.number) ?? 82,
            duration: value["duration"].flatMap(Self.number) ?? 300,
            vibrationIntensity: value["vibrationIntensity"].flatMap(Self.number) ?? 100,
            vibrationPattern: value["vibrationPattern"]?.string == "double" ? "double" : "rise",
            index: index,
            id: "\(day.rawValue)-\(index)-\(time)-\(enabled ? "on" : "off")"
        )
    }

    static func number(_ value: JSONValue) -> Double? { value.finiteNumber }

    /// The payload object Home Assistant expects for this alarm.
    var payload: JSONValue {
        .object([
            "alarmTemperature": .number(alarmTemperature),
            "duration": .number(duration),
            "enabled": .bool(enabled),
            "time": .string(time),
            "vibrationIntensity": .number(vibrationIntensity),
            "vibrationPattern": .string(vibrationPattern),
        ])
    }

    /// Everything but ``id`` and ``index``, to tell whether Home Assistant confirmed a list.
    var contentKey: String {
        "\(day.rawValue)|\(time)|\(enabled)|\(alarmTemperature)|\(duration)|\(vibrationIntensity)|\(vibrationPattern)"
    }
}

public extension Array where Element == BedAlarm {
    /// Sorted by day, time, then position (web `compareAlarmRecords`).
    func sortedForDisplay() -> [BedAlarm] {
        sorted { ($0.day.index, $0.time, $0.index) < ($1.day.index, $1.time, $1.index) }
    }

    /// Sorted for display with each day's positions renumbered from 0 (web `normalizeAlarmRecordIndexes`).
    func normalizedIndexes() -> [BedAlarm] {
        var counts: [Weekday: Int] = [:]
        return sortedForDisplay().map { alarm in
            var alarm = alarm
            alarm.index = counts[alarm.day, default: 0]
            counts[alarm.day] = alarm.index + 1
            return alarm
        }
    }

    /// Identity of the list's content in source order (web `alarmRecordsStateKey`).
    var contentKey: String {
        sorted { ($0.day.index, $0.index) < ($1.day.index, $1.index) }.map(\.contentKey).joined(separator: ";")
    }
}

/// A day's alarms on the Alarms tab (web `FreeSleepAlarmDayGroup`).
public struct BedAlarmDayGroup: Hashable, Sendable, Identifiable {
    public var day: Weekday
    public var alarms: [BedAlarm]
    public var id: Weekday { day }

    public var enabledCount: Int { alarms.filter(\.enabled).count }
    public var disabledCount: Int { alarms.count - enabledCount }

    /// `Monday Alarm` or `Monday Alarms`.
    public var title: String { "\(day.label) \(alarms.count == 1 ? "Alarm" : "Alarms")" }

    /// `Enabled`, `Disabled`, or `2 Enabled • 1 Disabled` (web `alarmEnabledSummary`).
    public var summary: String {
        if alarms.count == 1 { return enabledCount == 1 ? "Enabled" : "Disabled" }
        return [enabledCount > 0 ? "\(enabledCount) Enabled" : nil, disabledCount > 0 ? "\(disabledCount) Disabled" : nil]
            .compactMap { $0 }.joined(separator: " • ")
    }

    /// Groups by day in week order, skipping empty days.
    public static func groups(_ alarms: [BedAlarm]) -> [BedAlarmDayGroup] {
        Weekday.allCases.compactMap { day in
            let dayAlarms = alarms.filter { $0.day == day }
            return dayAlarms.isEmpty ? nil : BedAlarmDayGroup(day: day, alarms: dayAlarms)
        }
    }
}

// MARK: - Schedule

/// Both sides' weekly schedules from the schedule sensor (``MasterBedroom/scheduleEntityId``)
/// (web `scheduleFromEntityAttributes`).
public struct SleepypodSchedule: Equatable, Sendable {
    /// Raw day objects by side and day.
    public var days: [BedSide: [Weekday: JSONValue]]

    /// Parses the sensor's attributes; `nil` when neither side has a schedule.
    public init?(attributes: [String: JSONValue]?) {
        guard let attributes else { return nil }
        var days: [BedSide: [Weekday: JSONValue]] = [:]
        for side in BedSide.allCases {
            guard case let .object(sideValue)? = attributes[side.rawValue] else { continue }
            var sideDays: [Weekday: JSONValue] = [:]
            for day in Weekday.allCases {
                if case .object? = sideValue[day.rawValue] { sideDays[day] = sideValue[day.rawValue] }
            }
            days[side] = sideDays
        }
        guard !days.isEmpty else { return nil }
        self.days = days
    }

    /// Whether `side` has a schedule.
    public func has(_ side: BedSide) -> Bool { days[side] != nil }

    /// A day's alarms: the `alarms` list, else an enabled legacy `alarm` (web `alarmsFromDailySchedule`).
    static func alarms(in day: JSONValue?, weekday: Weekday) -> [BedAlarm] {
        let listed = (day?["alarms"]?.array ?? []).enumerated().compactMap { BedAlarm.parse($1, day: weekday, index: $0) }
        if !listed.isEmpty { return listed }
        if let legacy = day?["alarm"].flatMap({ BedAlarm.parse($0, day: weekday, index: 0) }), legacy.enabled { return [legacy] }
        return []
    }

    /// Every alarm on `side`, sorted (web `alarmRecordsFromSchedule` with execution semantics).
    public func alarms(_ side: BedSide) -> [BedAlarm] {
        Weekday.allCases.flatMap { Self.alarms(in: days[side]?[$0], weekday: $0) }.sortedForDisplay()
    }

    /// The MQTT payload replacing `side`'s alarms with `alarms` on every day (web `alarmSchedulePayload`).
    public static func alarmPayload(_ alarms: [BedAlarm], side: BedSide) -> JSONValue {
        var sideDays: [String: JSONValue] = [:]
        for day in Weekday.allCases {
            let dayAlarms = alarms.filter { $0.day == day }.sorted { $0.index < $1.index }
            sideDays[day.rawValue] = .object(["alarms": .array(dayAlarms.map(\.payload))])
        }
        return .object([side.rawValue: .object(sideDays)])
    }

    /// The MQTT payload rewriting `side`'s power and stage temperatures for new stage levels, keeping alarms and
    /// any real bedtime and wake times (web `sleepypodSchedulePayload`).
    public func stagePayload(side: BedSide, levels: [SchedulePhase: Double]) -> JSONValue {
        var sideDays: [String: JSONValue] = [:]
        for day in Weekday.allCases {
            let dayValue = days[side]?[day]
            let power = Self.power(dayValue?["power"], bedtimeLevel: levels[.bedtime] ?? 0)
            let on = power["on"]?.string ?? Self.defaultBedtime
            sideDays[day.rawValue] = .object([
                "alarms": .array(Self.alarms(in: dayValue, weekday: day).map(\.payload)),
                "power": power,
                "temperatures": Self.temperatures(dayValue, powerOn: on, levels: levels),
            ])
        }
        return .object([side.rawValue: .object(sideDays)])
    }

    static let defaultBedtime = "21:30"
    static let defaultWake = "09:00"
    static let defaultAsleep = "01:00"
    static let defaultDawn = "05:00"

    private static func power(_ power: JSONValue?, bedtimeLevel: Double) -> JSONValue {
        let on = ClockTime.parse(power?["on"]?.string)
        let off = ClockTime.parse(power?["off"]?.string)
        // 00:00–23:59 is the adapter's placeholder, not a real schedule.
        let real = power != nil && !(on == "00:00" && off == "23:59")
        return .object([
            "enabled": .bool(power?["enabled"]?.bool != false),
            "off": .string(real ? (off ?? defaultWake) : defaultWake),
            "on": .string(real ? (on ?? defaultBedtime) : defaultBedtime),
            "onTemperature": .number(Double(BedLevel.fahrenheit(level: bedtimeLevel))),
        ])
    }

    private static func temperatures(_ day: JSONValue?, powerOn: String, levels: [SchedulePhase: Double]) -> JSONValue {
        var entries: [(time: String, temperature: Double)] = []
        if case let .object(values)? = day?["temperatures"] {
            for (key, value) in values {
                guard let time = ClockTime.parse(key) else { continue }
                let raw = value["temperature"] ?? value["temperatureF"] ?? value["level"] ?? value["value"] ?? value
                if let temperature = BedAlarm.number(raw) { entries.append((time, temperature)) }
            }
        }
        let start = ClockTime.minutes(powerOn)
        entries.sort { (ClockTime.minutes($0.time) - start + 1440) % 1440 < (ClockTime.minutes($1.time) - start + 1440) % 1440 }
        let asleep = entries.first?.time ?? defaultAsleep
        let dawn = entries.count > 1 ? entries.last!.time : defaultDawn
        var result: [String: JSONValue] = [:]
        for entry in entries { result[entry.time] = .number(entry.temperature) }
        result[asleep] = .number(Double(BedLevel.fahrenheit(level: levels[.asleep] ?? 0)))
        result[dawn] = .number(Double(BedLevel.fahrenheit(level: levels[.dawn] ?? 0)))
        return .object(result)
    }
}

// MARK: - Formatting

/// Text helpers for the bed sheet (web `formatTemperatureCompact`, `formatEightSleepCountdown`).
public enum BedFormat {
    /// `72°F`, `71.5°F`, or `--°F`.
    public static func temperature(_ value: Double?, unit: String = "°F") -> String {
        guard let value else { return "--" + unit }
        return (value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)) + unit
    }

    /// `4:05` for a remaining interval.
    public static func countdown(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// A sensor's state with its unit (`62 bpm`), or `Unavailable`.
    public static func metric(_ state: EntityState?) -> String {
        guard let state, !state.isUnavailable else { return "Unavailable" }
        let value: String
        if let number = Double(state.state) {
            value = number == number.rounded() ? String(Int(number)) : String(format: "%.1f", (number * 10).rounded(.toNearestOrAwayFromZero) / 10) // JS toFixed(1): 91.25 → 91.3
        } else {
            value = state.state.prefix(1).uppercased() + state.state.dropFirst()
        }
        guard let unit = state.attributes["unit_of_measurement"]?.string, !unit.isEmpty else { return value }
        return unit.hasPrefix("°") ? value + unit : value + " " + unit
    }
}
