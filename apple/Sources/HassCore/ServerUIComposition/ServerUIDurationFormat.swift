import Foundation

// MARK: - Duration format

/// How a `format` hole draws a duration (`formats[name] = { duration: { style, unit? } }`, `sh.duration-format@1`).
///
/// The argument is a number of seconds; `unit` ``Unit/minutes`` on a ``Style/compact`` duration says it is minutes. The text is United States
/// English and integer arithmetic, so a published layout reads the same on every phone and the evaluation corpus holds the exact bytes (the
/// Studio's `duration-format.ts` is the same rules). A number that is not finite, or is 1e13 or more in either sign, has no text.
///
/// | Style | Example | Rule (the shipped code it reproduces) |
/// |---|---|---|
/// | ``Style/compact`` | `30m`, `1h`, `1h 30m` | minutes round to the nearest whole minute (a tie away from zero); seconds round **up** to whole minutes, at least 1 (`HumidifierController.formatMinutes`, `formatSeconds`). No text for 0 or less, so the slot's fallback ("Off") draws |
/// | ``Style/clock`` | `05:00`, `01:00:00` | whole seconds rounded down, never below `00:00`; hours only from one hour (`BathroomFanController.formatRemaining`) |
/// | ``Style/minutesSeconds`` | `4:30`, `75:00` | seconds rounded **up**, never below `0:00`; unbounded minutes (`BedFormat.countdown`) |
/// | ``Style/span`` | `1 hour`, `3 days`, `3 weeks`, `2 months` | the size of the number: under a day in hours, under 21 days in days, under 60 days in weeks, else months of 30 days; the amount rounded (a tie away from zero), at least 1 (`TodoItem.dueLabel`) |
public struct ServerUIDurationFormat: Hashable, Sendable {
    /// The four drawings.
    public enum Style: String, Sendable, CaseIterable {
        case compact
        case clock
        case minutesSeconds = "minutes-seconds"
        case span
    }

    /// What a compact duration's number counts.
    public enum Unit: String, Sendable, CaseIterable { case seconds, minutes }

    /// How the number is drawn.
    public let style: Style
    /// What a compact duration counts, or `nil` when the document wrote none (seconds).
    public let unit: Unit?

    /// Creates a format.
    public init(style: Style, unit: Unit? = nil) {
        self.style = style
        self.unit = unit
    }

    /// The numbers from here up have no text: a duration that long is not a duration.
    static let limit = 1e13

    /// The text of `number` in this format, or `nil` when it has none (not finite, 1e13 or more, or a compact duration of 0 or less).
    public func text(_ number: Double) -> String? {
        guard number.isFinite, abs(number) < Self.limit else { return nil }
        switch style {
        case .compact:
            let minutes: Int
            if unit == .minutes { minutes = Int(number.rounded()) }
            else { minutes = number > 0 ? max(1, Int((number / 60).rounded(.up))) : 0 }
            guard minutes > 0 else { return nil }
            if minutes < 60 { return "\(minutes)m" }
            let rest = minutes % 60
            return rest == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h \(rest)m"
        case .clock:
            let total = Int(max(0, number.rounded(.down)))
            let hours = total / 3_600, minutes = total % 3_600 / 60, seconds = total % 60
            return hours > 0 ? "\(Self.pad(hours)):\(Self.pad(minutes)):\(Self.pad(seconds))" : "\(Self.pad(minutes)):\(Self.pad(seconds))"
        case .minutesSeconds:
            let total = Int(max(0, number.rounded(.up)))
            return "\(total / 60):\(Self.pad(total % 60))"
        case .span:
            let magnitude = abs(number), hour = 3_600.0, day = 24 * hour
            let (name, divisor): (String, Double) = magnitude < day ? ("hour", hour) : magnitude < 21 * day ? ("day", day)
                : magnitude < 60 * day ? ("week", 7 * day) : ("month", 30 * day)
            let amount = max(1, Int((magnitude / divisor).rounded()))
            return "\(amount) \(name)\(amount == 1 ? "" : "s")"
        }
    }

    private static func pad(_ number: Int) -> String { number < 10 ? "0\(number)" : "\(number)" }
}
