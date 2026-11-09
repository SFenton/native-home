import Foundation

/// Local-calendar expiry rules (web `expiryDate.ts`).
///
/// EverShelf computes `days_remaining` in UTC, so in the evening Pacific an item dated today already
/// reports -1. Everything user facing classifies against the local calendar day instead, here, so every
/// screen agrees on what "expired" means.
public struct InventoryCalendar: Sendable {
    /// The calendar dates are read in (the device's, normally).
    public var calendar: Calendar
    /// "Now"; tests pin it.
    public var now: @Sendable () -> Date

    /// Creates a calendar.
    public init(calendar: Calendar = .current, now: @escaping @Sendable () -> Date = { Date() }) {
        self.calendar = calendar
        self.now = now
    }

    /// The local calendar, live clock.
    public static let current = InventoryCalendar()

    // MARK: - Parsing

    /// The local midnight of a `YYYY-MM-DD…` string, or `nil` if it doesn't start with a date.
    public func date(fromISO value: String) -> Date? {
        guard let (year, month, day) = Self.parts(value) else { return nil }
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    static func parts(_ value: String) -> (Int, Int, Int)? {
        let scalars = Array(value.utf8.prefix(10))
        guard scalars.count == 10, scalars[4] == UInt8(ascii: "-"), scalars[7] == UInt8(ascii: "-") else { return nil }
        let digits = scalars.enumerated().filter { $0.offset != 4 && $0.offset != 7 }.map(\.element)
        guard digits.allSatisfy({ $0 >= UInt8(ascii: "0") && $0 <= UInt8(ascii: "9") }) else { return nil }
        let text = String(decoding: scalars, as: UTF8.self)
        guard let year = Int(text.prefix(4)), let month = Int(text.dropFirst(5).prefix(2)), let day = Int(text.dropFirst(8)) else { return nil }
        return (year, month, day)
    }

    /// Whether `value` is empty or exactly `YYYY-MM-DD` (the editor's accepted input, `validExpiryInput`).
    public static func isValidInput(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || (trimmed.utf8.count == 10 && parts(trimmed) != nil)
    }

    // MARK: - Days

    /// Today's local midnight.
    public var today: Date { calendar.startOfDay(for: now()) }

    /// Whole days from today to `date` (negative once it has passed).
    public func days(until date: Date) -> Int {
        calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: date)).day ?? 0
    }

    /// Days until a stored expiry string, or `nil` without a usable date.
    public func days(untilISO value: String?) -> Int? {
        guard let value, let date = date(fromISO: value) else { return nil }
        return days(until: date)
    }

    /// Expired by the local calendar.
    public func isExpired(_ value: String?) -> Bool {
        (days(untilISO: value) ?? 0) < 0
    }

    // MARK: - Formatting

    /// `Oct 16, 2026`: the abbreviated date Apple's apps show in rows (direction G mockups n6; the web's
    /// `formatDisplayDate` reads `10/16/2026`). The app's copy is English, so the format is fixed to it.
    public func displayDate(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: Locale(identifier: "en_US"),
                                        calendar: calendar, timeZone: calendar.timeZone))
    }

    /// `YYYY-MM-DD` for a local date (`dateInputValue`).
    public func isoString(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Adds months the way the web does: the same day of month, clamped to the target month's last day
    /// (`addMonths`; Jan 31 + 1 month = Feb 28/29).
    public func adding(months: Int, to date: Date) -> Date {
        calendar.date(byAdding: .month, value: months, to: date) ?? date
    }
}

/// Number formatting shared by rows, steppers and prompts.
public enum InventoryFormat {
    /// `2`, `1.5`, `0.25`: no trailing zeros (`formatQuantity`).
    public static func quantity(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 { return String(Int(value)) }
        var text = String(format: "%.6f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    /// Parses a typed quantity: digits with an optional `.` or `,` decimal (`promptDeleteQuantity`).
    public static func parseQuantity(_ text: String) -> Double? {
        let normalized = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        // The web's pattern `\d+|\d*\.\d+`: `5`, `1.5`, `.5`; not `5.` or `1.2.3`.
        guard normalized.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }),
              normalized.filter({ $0 == "." }).count <= 1,
              normalized.last?.isNumber == true
        else { return nil }
        return Double(normalized)
    }
}
