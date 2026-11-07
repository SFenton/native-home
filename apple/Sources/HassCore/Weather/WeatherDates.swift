import Foundation

/// Date formatting for weather (parsing is `HassDates.iso8601`), matching the web's `en-US` output regardless of the device locale
/// (`ha-sfenton-react-dash@f5a7bf9:src/i18n/formatters.ts`).
public enum WeatherDates {
    /// The calendar fields of an instant in a time zone (`zonedDateParts`).
    public struct Parts: Equatable, Sendable {
        public var year: Int
        public var month: Int
        public var day: Int
        public var hour: Int
        public var minute: Int
    }

    private final class CalendarCache: @unchecked Sendable {
        private let lock = NSLock()
        private var calendars: [String: Calendar] = [:]

        func calendar(for timeZone: TimeZone) -> Calendar {
            lock.lock()
            defer { lock.unlock() }
            if let calendar = calendars[timeZone.identifier] { return calendar }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            calendars[timeZone.identifier] = calendar
            return calendar
        }
    }

    // Building a calendar per call made the briefing generator 30x slower.
    private static let calendars = CalendarCache()

    /// Calendar fields in `timeZone`.
    public static func parts(_ date: Date, in timeZone: TimeZone) -> Parts {
        let calendar = calendars.calendar(for: timeZone)
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return Parts(
            year: components.year ?? 0, month: components.month ?? 0, day: components.day ?? 0,
            hour: components.hour ?? 0, minute: components.minute ?? 0
        )
    }

    /// `2026-01-15`, the local calendar day (`localDateKey`).
    public static func dateKey(_ date: Date, in timeZone: TimeZone) -> String {
        let parts = parts(date, in: timeZone)
        return String(format: "%04d-%02d-%02d", parts.year, parts.month, parts.day)
    }

    /// `7:12 AM` (`formatClockTime`).
    public static func clock(_ date: Date, in timeZone: TimeZone = .current) -> String {
        let parts = parts(date, in: timeZone)
        return String(format: "%d:%02d %@", twelveHour(parts.hour), parts.minute, parts.hour < 12 ? "AM" : "PM")
    }

    /// `7 AM` (`formatHourLabel`).
    public static func hour(_ date: Date, in timeZone: TimeZone = .current) -> String {
        let parts = parts(date, in: timeZone)
        return "\(twelveHour(parts.hour)) \(parts.hour < 12 ? "AM" : "PM")"
    }

    /// `Mon`.
    public static func weekday(_ date: Date, in timeZone: TimeZone = .current) -> String {
        let calendar = calendars.calendar(for: timeZone)
        let names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return names[(calendar.component(.weekday, from: date) - 1) % 7]
    }

    private static func twelveHour(_ hour: Int) -> Int { hour % 12 == 0 ? 12 : hour % 12 }
}
