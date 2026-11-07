import HassCore
import HassDesign
import SwiftUI

/// `HH:mm` ⇄ a time today, for the time pickers.
enum ActivityTime {
    static func date(from value: String, calendar: Calendar = .current, now: Date = Date()) -> Date {
        let normalized = HumidifierSchedule.normalizedTime(value, fallback: "00:00")
        let hour = min(23, Int(normalized.prefix(2)) ?? 0)
        let minute = Int(normalized.suffix(2)) ?? 0
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) ?? now
    }

    static func string(from date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
}
