import Foundation

// MARK: - Dates

/// Parses the date strings Home Assistant sends. Every feature uses these instead of building formatters per call.
public enum HassDates {
    // Formatters are expensive to create and safe to share for parsing; they are configured once and never mutated.
    private nonisolated(unsafe) static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private nonisolated(unsafe) static let plain = ISO8601DateFormatter()
    private nonisolated(unsafe) static let local: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    /// An ISO 8601 timestamp with or without fractional seconds (`last_changed`, `2026-10-11T14:30:00.123Z`).
    /// `nil` or empty text is `nil`.
    public static func iso8601(_ text: String?) -> Date? {
        guard let text, !text.isEmpty else { return nil }
        return fractional.date(from: text) ?? plain.date(from: text)
    }

    /// A zone-less `2026-10-11 14:30:00` (or with a `T`) in the device's time zone, like the web's `Date.parse`.
    public static func localDateTime(_ text: String) -> Date? {
        local.date(from: text.replacing("T", with: " "))
    }
}
