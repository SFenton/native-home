import Foundation

/// A day of the week as Home Assistant's `schedule` helper names it.
public enum Weekday: String, CaseIterable, Hashable, Sendable, Codable {
    case sunday, monday, tuesday, wednesday, thursday, friday, saturday

    /// `Sun` … `Sat`.
    public var shortTitle: String { String(rawValue.prefix(3)).capitalized }
    /// `Sunday` … `Saturday`.
    public var title: String { rawValue.capitalized }

    /// The following day (Saturday → Sunday).
    public var next: Weekday {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

/// One block of a Home Assistant `schedule` helper day (`{from, to, data}`).
public struct HassScheduleBlock: Hashable, Sendable {
    public var from: String
    public var to: String
    public var data: [String: JSONValue]

    /// Creates a block.
    public init(from: String, to: String, data: [String: JSONValue] = [:]) {
        self.from = from
        self.to = to
        self.data = data
    }

    /// The block as `schedule/update` expects it.
    public var json: JSONValue {
        var object: [String: JSONValue] = ["from": .string(from), "to": .string(to)]
        if !data.isEmpty { object["data"] = .object(data) }
        return .object(object)
    }
}

/// A Home Assistant `schedule` helper from `schedule/list` (web `HassSchedule`).
public struct HassSchedule: Hashable, Sendable {
    public var id: String
    public var name: String
    public var icon: String?
    public var days: [Weekday: [HassScheduleBlock]]

    /// Creates a schedule.
    public init(id: String, name: String, icon: String? = nil, days: [Weekday: [HassScheduleBlock]] = [:]) {
        self.id = id
        self.name = name
        self.icon = icon
        self.days = days
    }

    /// Parses one `schedule/list` item.
    public init?(json: JSONValue) {
        guard let id = json["id"]?.string else { return nil }
        self.id = id
        name = json["name"]?.string ?? id
        icon = json["icon"]?.string
        var days: [Weekday: [HassScheduleBlock]] = [:]
        for day in Weekday.allCases {
            days[day] = (json[day.rawValue]?.array ?? []).compactMap { block in
                guard let from = block["from"]?.string, let to = block["to"]?.string else { return nil }
                if case let .object(data)? = block["data"] { return HassScheduleBlock(from: from, to: to, data: data) }
                return HassScheduleBlock(from: from, to: to)
            }
        }
        self.days = days
    }
}

/// One recurring humidifier activity: a profile applied on some days between two times
/// (web `HumidifierScheduleRule`, `src/components/hass/humidifierSchedule.ts`).
///
/// Home Assistant stores each rule as blocks on every day it covers, with the rule's fields in each block's
/// `data`; an overnight rule becomes a block to 24:00 plus one from 00:00 on the next day.
public struct HumidifierScheduleRule: Hashable, Sendable, Identifiable {
    public var id: String
    public var label: String
    public var days: [Weekday]
    /// `HH:mm`.
    public var start: String
    /// `HH:mm`; at or before ``start`` means it ends the next day.
    public var end: String
    public var mode: HumidifierMode
    public var mistLevel: Int
    public var targetHumidity: Int
    public var warmLevel: Int
    public var display: Bool

    /// Creates a rule.
    public init(id: String, label: String, days: [Weekday], start: String, end: String, mode: HumidifierMode,
                mistLevel: Int, targetHumidity: Int, warmLevel: Int, display: Bool) {
        self.id = id
        self.label = label
        self.days = days
        self.start = start
        self.end = end
        self.mode = mode
        self.mistLevel = mistLevel
        self.targetHumidity = targetHumidity
        self.warmLevel = warmLevel
        self.display = display
    }

    /// A new "Night" activity, 22:00–07:00 on weekdays (web `createHumidifierScheduleRule` with
    /// `resolveScheduleDefaultDays`), starting from the humidifier's current settings when given.
    public static func new(id: String = UUID().uuidString, mode: HumidifierMode = .sleep, mistLevel: Int = 4,
                           targetHumidity: Int = 50, warmLevel: Int = 0, display: Bool = false) -> HumidifierScheduleRule {
        HumidifierScheduleRule(id: id, label: "Night", days: [.monday, .tuesday, .wednesday, .thursday, .friday], start: "22:00", end: "07:00", mode: mode,
                               mistLevel: mistLevel, targetHumidity: targetHumidity, warmLevel: warmLevel, display: display)
    }

    /// The data stored with each block.
    var blockData: [String: JSONValue] {
        [
            "display": .bool(display),
            "end_time": .string(end),
            "label": .string(label),
            "mist_level": .number(Double(mistLevel)),
            "mode": .string(mode.rawValue),
            "rule_days": .string(days.map(\.rawValue).joined(separator: ",")),
            "rule_id": .string(id),
            "start_time": .string(start),
            "target_humidity": .number(Double(targetHumidity)),
            "warm_level": .number(Double(warmLevel)),
        ]
    }

    /// Whether the editor can save it (days, a name and valid times; conflicts are checked against the others).
    public var isComplete: Bool {
        !days.isEmpty && !label.trimmingCharacters(in: .whitespaces).isEmpty
            && HumidifierSchedule.isValidTime(start) && HumidifierSchedule.isValidTime(end)
    }
}

/// Two rules overlapping on a day.
public struct ScheduleConflict: Hashable, Sendable {
    public var day: Weekday
    public var firstRuleId: String
    public var secondRuleId: String

    /// The editor's message.
    public var message: String { "This activity overlaps another activity on \(day.title)." }
}

/// Converting rules to and from Home Assistant blocks, conflict checks and formatting (web `humidifierSchedule.ts`).
public enum HumidifierSchedule {
    // MARK: Time

    /// `H:mm` or `HH:mm` → `HH:mm`, clamping hours to 0–24 and minutes to 0–59; `fallback` when unparseable.
    public static func normalizedTime(_ value: String, fallback: String) -> String {
        let parts = value.split(separator: ":")
        guard parts.count >= 2, (1...2).contains(parts[0].count), let hour = Int(parts[0]),
              let minute = Int(parts[1].prefix(2)), parts[1].prefix(2).count == 2 else { return fallback }
        return String(format: "%02d:%02d", min(24, max(0, hour)), min(59, max(0, minute)))
    }

    /// `HH:mm` with hours 0–23 (web `isValidScheduleTime`).
    public static func isValidTime(_ value: String) -> Bool {
        let parts = value.split(separator: ":")
        guard parts.count == 2, parts[0].count == 2, parts[1].count == 2,
              let hour = Int(parts[0]), let minute = Int(parts[1]) else { return false }
        return (0...23).contains(hour) && (0...59).contains(minute)
    }

    // MARK: Rules ⇄ blocks

    /// Reads rules back from a schedule, sorted by start then name (web `scheduleRules`).
    public static func rules(from schedule: HassSchedule?) -> [HumidifierScheduleRule] {
        guard let schedule else { return [] }
        var rules: [String: HumidifierScheduleRule] = [:]
        for day in Weekday.allCases {
            for block in schedule.days[day] ?? [] {
                let data = block.data
                guard let id = data["rule_id"]?.string, !id.isEmpty, rules[id] == nil else { continue }
                let encodedDays = data["rule_days"]?.string.map { $0.split(separator: ",").map(String.init) } ?? [day.rawValue]
                let days = encodedDays.compactMap(Weekday.init(rawValue:))
                let label = data["label"]?.string?.trimmingCharacters(in: .whitespaces)
                rules[id] = HumidifierScheduleRule(
                    id: id,
                    label: label.flatMap { $0.isEmpty ? nil : $0 } ?? "Scheduled activity",
                    days: days.isEmpty ? [day] : days,
                    start: normalizedTime(data["start_time"]?.string ?? block.from, fallback: "22:00"),
                    end: normalizedTime(data["end_time"]?.string ?? block.to, fallback: "07:00"),
                    mode: data["mode"]?.string.flatMap(HumidifierMode.init(rawValue:)) ?? .manual,
                    mistLevel: clamp(data["mist_level"], 1, 9, fallback: 5),
                    targetHumidity: clamp(data["target_humidity"], 40, 80, fallback: 50),
                    warmLevel: clamp(data["warm_level"], 0, 3, fallback: 0),
                    display: data["display"]?.bool != false
                )
            }
        }
        return rules.values.sorted { ($0.start, $0.label) < ($1.start, $1.label) }
    }

    private static func clamp(_ value: JSONValue?, _ low: Int, _ high: Int, fallback: Int) -> Int {
        let number = value?.number ?? value?.string.flatMap(Double.init)
        guard let number, number.isFinite else { return fallback }
        return min(high, max(low, Int(number)))
    }

    /// Blocks for every day the rules cover, sorted within each day (web `scheduleDaysFromRules`).
    public static func days(from rules: [HumidifierScheduleRule]) -> [Weekday: [HassScheduleBlock]] {
        var days: [Weekday: [HassScheduleBlock]] = Dictionary(uniqueKeysWithValues: Weekday.allCases.map { ($0, []) })
        for rule in rules {
            var rule = rule
            rule.start = normalizedTime(rule.start, fallback: "22:00")
            rule.end = normalizedTime(rule.end, fallback: "07:00")
            let data = rule.blockData
            let overnight = rule.end <= rule.start
            for day in rule.days {
                if overnight {
                    days[day, default: []].append(HassScheduleBlock(from: rule.start, to: "24:00", data: data))
                    if rule.end != "00:00" { days[day.next, default: []].append(HassScheduleBlock(from: "00:00", to: rule.end, data: data)) }
                } else {
                    days[day, default: []].append(HassScheduleBlock(from: rule.start, to: rule.end, data: data))
                }
            }
        }
        for day in Weekday.allCases {
            days[day]?.sort { ($0.from, $0.to) < ($1.from, $1.to) }
        }
        return days
    }

    /// Overlapping blocks, day by day (web `scheduleConflicts`).
    public static func conflicts(in rules: [HumidifierScheduleRule]) -> [ScheduleConflict] {
        let days = days(from: rules)
        var conflicts: [ScheduleConflict] = []
        for day in Weekday.allCases {
            let blocks = days[day] ?? []
            for index in blocks.indices.dropFirst() where blocks[index - 1].to > blocks[index].from {
                conflicts.append(ScheduleConflict(day: day, firstRuleId: blocks[index - 1].data["rule_id"]?.string ?? "",
                                                  secondRuleId: blocks[index].data["rule_id"]?.string ?? ""))
            }
        }
        return conflicts
    }

    /// The `schedule/update` message saving `rules` into `schedule` (web `scheduleUpdateMessage`).
    public static func updateMessage(_ schedule: HassSchedule, rules: [HumidifierScheduleRule]) -> [String: JSONValue] {
        var message: [String: JSONValue] = [
            "type": .string("schedule/update"),
            "schedule_id": .string(schedule.id),
            "name": .string(schedule.name),
            "icon": .string(schedule.icon ?? "mdi:calendar-clock"),
        ]
        for (day, blocks) in days(from: rules) { message[day.rawValue] = .array(blocks.map(\.json)) }
        return message
    }

    // MARK: Formatting

    /// `Every day`, `Weekdays`, `Weekends` or `Mon, Wed` (web `formatScheduleDays`).
    public static func formatDays(_ days: [Weekday]) -> String {
        let unique = Weekday.allCases.filter(days.contains)
        if unique.count == 7 { return "Every day" }
        if unique == [.monday, .tuesday, .wednesday, .thursday, .friday] { return "Weekdays" }
        if unique == [.sunday, .saturday] { return "Weekends" }
        return unique.map(\.shortTitle).joined(separator: ", ")
    }

    /// `10:00 PM–7:00 AM` (web `formatScheduleTime`).
    public static func formatTimes(start: String, end: String) -> String {
        "\(formatClock(start))–\(formatClock(end))"
    }

    /// `22:00` → `10:00 PM`.
    public static func formatClock(_ value: String) -> String {
        let normalized = normalizedTime(value, fallback: "00:00")
        let hour = (Int(normalized.prefix(2)) ?? 0) % 24
        return "\(hour % 12 == 0 ? 12 : hour % 12):\(normalized.suffix(2)) \(hour >= 12 ? "PM" : "AM")"
    }

    /// `Sleep`, `Auto 50% • Mist 4` or `Manual • Mist 4 • Warm 1` (web `scheduleProfileSummary`).
    public static func profileSummary(_ rule: HumidifierScheduleRule) -> String {
        switch rule.mode {
        case .sleep: "Sleep"
        case .targetHumidity: "Auto \(rule.targetHumidity)% • Mist \(rule.mistLevel)"
        case .manual: "Manual • Mist \(rule.mistLevel) • Warm \(rule.warmLevel)"
        }
    }
}
