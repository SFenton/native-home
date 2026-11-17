import Foundation

// MARK: - Clock and wall time

/// The clock an expression's `clock` and `date` operands and the `time`, `date-time` and `relative` date styles read.
///
/// `now` is the viewer's wall time as `YYYY-MM-DDTHH:MM:SS` with no zone suffix, and ``utcOffsetMinutes`` is that wall time's
/// offset from UTC. The app builds one from `Date()` once a minute and only while something reads it
/// (``ServerUIAppState/clock(at:calendar:)``); a document is never given the wall clock any other way.
public struct ServerUIClock: Equatable, Sendable {
    /// The wall time, `YYYY-MM-DDTHH:MM:SS`.
    public var now: String
    /// The offset of the wall time from UTC, in minutes.
    public var utcOffsetMinutes: Int

    /// Creates a clock.
    public init(now: String, utcOffsetMinutes: Int) {
        self.now = now
        self.utcOffsetMinutes = utcOffsetMinutes
    }
}

/// A moment on a clock's wall: whole days since 1970-01-01 and the seconds into that day.
public struct ServerUIWallTime: Equatable, Sendable {
    public var days: Int
    public var seconds: Int

    /// The moment as one integer, for comparing.
    public var instant: Int { days * 86_400 + seconds }
}

/// The date rules of an expression: all integer arithmetic, so the app and the Studio agree and no time-zone database is involved.
///
/// A date is `YYYY-MM-DD`; a date and time is `YYYY-MM-DD[T or space]HH:MM[:SS[.fraction]]` with an optional `Z` or `±HH:MM`. A date
/// and time with an offset is moved to the clock's wall; one without is already on it; a date has no time (midnight). A value that does
/// not parse, or is not a real calendar date, has no date: comparing it answers no and measuring it gives `unavailable`.
public enum ServerUIDates {
    /// Days since 1970-01-01 of a proleptic Gregorian date (Howard Hinnant's `days_from_civil`).
    public static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = floorDivide(y, 400)
        let yoe = y - era * 400
        let doy = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    /// Year, month (1 to 12) and day of the month of a count of days since 1970-01-01 (Howard Hinnant's `civil_from_days`).
    public static func civil(fromDays days: Int) -> (year: Int, month: Int, day: Int) {
        let z = days + 719_468
        let era = floorDivide(z, 146_097)
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let day = doy - (153 * mp + 2) / 5 + 1
        let month = mp < 10 ? mp + 3 : mp - 9
        return (yoe + era * 400 + (month <= 2 ? 1 : 0), month, day)
    }

    /// Whether the three numbers are a real calendar date (year 1 to 9999).
    public static func isCalendarDate(year: Int, month: Int, day: Int) -> Bool {
        guard year >= 1, (1...12).contains(month), day >= 1 else { return false }
        let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
        let lengths = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        return day <= lengths[month - 1]
    }

    /// The moment `text` names on a wall clock `utcOffsetMinutes` from UTC, or `nil` when it is not a date or a date and time.
    public static func wallTime(_ text: String, utcOffsetMinutes: Int) -> ServerUIWallTime? {
        var scanner = Scanner(Array(text.utf8))
        guard let year = scanner.digits(4), scanner.expect("-"), let month = scanner.digits(2), scanner.expect("-"),
              let day = scanner.digits(2) else { return nil }
        if scanner.atEnd {
            guard isCalendarDate(year: year, month: month, day: day) else { return nil }
            return ServerUIWallTime(days: daysFromCivil(year: year, month: month, day: day), seconds: 0)
        }
        guard scanner.expect("T") || scanner.expect(" "), let hour = scanner.digits(2), scanner.expect(":"),
              let minute = scanner.digits(2) else { return nil }
        var second = 0
        if scanner.expect(":") {
            guard let value = scanner.digits(2) else { return nil }
            second = value
            if scanner.expect(".") {
                guard scanner.skipDigits() > 0 else { return nil }
            }
        }
        var own: Int?
        if scanner.expect("Z") { own = 0 }
        else if let sign = scanner.sign() {
            guard let zoneHour = scanner.digits(2), scanner.expect(":"), let zoneMinute = scanner.digits(2) else { return nil }
            guard zoneHour < 24, zoneMinute < 60 else { return nil }
            own = sign * (zoneHour * 60 + zoneMinute)
        }
        guard scanner.atEnd, isCalendarDate(year: year, month: month, day: day), hour < 24, minute < 60, second < 60 else { return nil }
        let days = daysFromCivil(year: year, month: month, day: day)
        let seconds = hour * 3_600 + minute * 60 + second
        guard let own else { return ServerUIWallTime(days: days, seconds: seconds) }
        let total = days * 86_400 + seconds + (utcOffsetMinutes - own) * 60
        let wholeDays = floorDivide(total, 86_400)
        return ServerUIWallTime(days: wholeDays, seconds: total - wholeDays * 86_400)
    }

    /// The wall time of the clock itself, or `nil` when `now` is not `YYYY-MM-DDTHH:MM:SS`.
    public static func time(of clock: ServerUIClock) -> ServerUIWallTime? {
        let bytes = Array(clock.now.utf8)
        guard bytes.count == 19, bytes[10] == UInt8(ascii: "T") else { return nil }
        return wallTime(clock.now, utcOffsetMinutes: clock.utcOffsetMinutes)
    }

    /// `YYYY-MM-DD` of the clock's day, or `nil` when `now` does not parse.
    public static func today(of clock: ServerUIClock) -> String? {
        time(of: clock) == nil ? nil : String(clock.now.prefix(10))
    }

    /// Whole calendar days from the date of `from` to the date of `to` (positive when `to` is later), or `nil` when either is not a date.
    public static func daysBetween(_ from: String, _ to: String, utcOffsetMinutes: Int) -> Int? {
        guard let a = wallTime(from, utcOffsetMinutes: utcOffsetMinutes), let b = wallTime(to, utcOffsetMinutes: utcOffsetMinutes)
        else { return nil }
        return b.days - a.days
    }

    /// How far the clock has come from the moment `from` to the moment `to` (`sh.flow-extras@1`): 0 at `from`, 1 at `to`, clamped to that range, in
    /// whole seconds on the clock's wall. `nil` when either moment is not a date or a date and time, when the clock does not parse, or when `to` is not
    /// after `from` (there is no span to measure).
    public static func progress(from: String, to: String, clock: ServerUIClock) -> Double? {
        guard let start = wallTime(from, utcOffsetMinutes: clock.utcOffsetMinutes), let end = wallTime(to, utcOffsetMinutes: clock.utcOffsetMinutes),
              let now = time(of: clock) else { return nil }
        let span = end.instant - start.instant
        guard span > 0 else { return nil }
        return min(1, max(0, Double(now.instant - start.instant) / Double(span)))
    }

    /// Integer division that rounds toward negative infinity (JavaScript's `Math.floor(a / b)`).
    static func floorDivide(_ a: Int, _ b: Int) -> Int {
        let quotient = a / b
        return (a % b != 0 && (a < 0) != (b < 0)) ? quotient - 1 : quotient
    }

    /// A byte cursor over ASCII text, so a date is read exactly as the Studio's patterns read it (ASCII digits only).
    private struct Scanner {
        private let bytes: [UInt8]
        private var index = 0
        init(_ bytes: [UInt8]) { self.bytes = bytes }
        var atEnd: Bool { index == bytes.count }
        mutating func expect(_ character: Character) -> Bool {
            guard index < bytes.count, bytes[index] == character.asciiValue else { return false }
            index += 1
            return true
        }
        mutating func sign() -> Int? {
            guard index < bytes.count else { return nil }
            if bytes[index] == UInt8(ascii: "+") { index += 1; return 1 }
            if bytes[index] == UInt8(ascii: "-") { index += 1; return -1 }
            return nil
        }
        mutating func digits(_ count: Int) -> Int? {
            guard index + count <= bytes.count else { return nil }
            var value = 0
            for offset in 0..<count {
                let byte = bytes[index + offset]
                guard (48...57).contains(byte) else { return nil }
                value = value * 10 + Int(byte - 48)
            }
            index += count
            return value
        }
        mutating func skipDigits() -> Int {
            var skipped = 0
            while index < bytes.count, (48...57).contains(bytes[index]) { index += 1; skipped += 1 }
            return skipped
        }
    }
}
