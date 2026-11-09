import Foundation

/// The Sprinklers page's text, from `ha-sfenton-react-dash@9ac2a46:src/i18n/locales/en/pages/sprinklers.json` and
/// the formatting in `SprinklerController.tsx` (times only, no dates, as on the web).
public struct SprinklerFormat: Sendable {
    public var locale: Locale
    public var timeZone: TimeZone

    /// Formats for the user's locale and time zone.
    public init(locale: Locale = .autoupdatingCurrent, timeZone: TimeZone = .autoupdatingCurrent) {
        self.locale = locale
        self.timeZone = timeZone
    }

    /// Day names, Sunday first (B-hyve day 0 is Sunday).
    public static let dayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    /// One-letter day labels for the day picker.
    public static let dayLetters = ["S", "M", "T", "W", "T", "F", "S"]

    // MARK: - Times

    /// A time of day, e.g. `7:00 AM` (web `formatTimestamp`).
    public func time(_ date: Date) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale)
        style.timeZone = timeZone
        return date.formatted(style)
    }

    /// A program start time (`HH:mm`) as a time of day; unparseable text comes back as is (web `formatClockTime`).
    public func clock(_ text: String) -> String {
        guard let date = Self.date(clock: text, timeZone: timeZone) else { return text }
        return time(date)
    }

    /// `HH:mm` on a fixed day in `timeZone`, for a time picker.
    public static func date(clock text: String, timeZone: TimeZone = .autoupdatingCurrent) -> Date? {
        let parts = text.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2, (0..<24).contains(parts[0]), (0..<60).contains(parts[1]) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: 2000, month: 1, day: 1, hour: parts[0], minute: parts[1]))
    }

    /// A picked time as `HH:mm` in `timeZone`.
    public static func clock(from date: Date, timeZone: TimeZone = .autoupdatingCurrent) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    // MARK: - Controller

    /// The controller's status word: Unavailable, Watering, Fault, else the mode in title case.
    public func status(_ snapshot: SprinklerSnapshot) -> String {
        switch snapshot.status {
        case .unavailable: "Unavailable"
        case .watering: "Watering"
        case .fault: "Fault"
        case .ready: StateText.titleCase(snapshot.mode)
        }
    }

    /// The next watering: Unknown, a time, Not scheduled, or Unavailable.
    public func nextStart(_ snapshot: SprinklerSnapshot) -> String {
        if snapshot.nextStartUnknown { return "Unknown" }
        if let next = snapshot.nextStart { return time(next) }
        return snapshot.available ? "Not scheduled" : "Unavailable"
    }

    /// A run's start time, or No history.
    public func lastStart(_ run: SprinklerSnapshot.LastRun) -> String {
        run.startTime.map(time) ?? "No history"
    }

    /// The tile subtitle: `Auto · Next 7:00 AM`, or Unavailable.
    public func subtitle(_ snapshot: SprinklerSnapshot) -> String {
        snapshot.available ? "\(status(snapshot)) · Next \(nextStart(snapshot))" : "Unavailable"
    }

    /// Battery percent, or Unavailable.
    public func battery(_ snapshot: SprinklerSnapshot) -> String {
        snapshot.batteryPercent.map { "\(Self.number($0))%" } ?? "Unavailable"
    }

    /// Minutes, e.g. `15 min`.
    public func minutes(_ value: Double) -> String { "\(Self.number(value)) min" }

    // MARK: - Programs

    /// Days as names (`Every day` for all seven).
    public func days(_ days: [Int]) -> String {
        let names = days.compactMap { Self.dayNames.indices.contains($0) ? Self.dayNames[$0] : nil }
        if names.count == 7 { return "Every day" }
        return names.formatted(.list(type: .and).locale(locale))
    }

    /// `{days} · {times}`, with Unavailable for an empty side.
    public func summary(_ program: SprinklerSnapshot.Program) -> String {
        let days = days(program.days)
        let times = program.startTimes.map(clock).formatted(.list(type: .and).locale(locale))
        return "\(days.isEmpty ? "Unavailable" : days) · \(times.isEmpty ? "Unavailable" : times)"
    }

    /// `{zone} · {minutes} min · {budget}%`.
    public func details(_ program: SprinklerSnapshot.Program, zone: String) -> String {
        "\(zone) · \(program.runTimeMinutes ?? 0) min · \(program.budget)%"
    }

    /// A zone's program name (`Bushes schedule`).
    public func programName(zone: String) -> String { "\(zone) schedule" }

    /// The low battery notice: the problem and the action ("Garden Faucet battery is low (15%). Replace the batteries soon.").
    public static func lowBatteryWarning(title: String, percent: Double) -> String {
        "\(title) battery is low (\(number(percent))%). Replace the batteries soon."
    }

    /// A whole number without a fraction, else one decimal.
    public static func number(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}
