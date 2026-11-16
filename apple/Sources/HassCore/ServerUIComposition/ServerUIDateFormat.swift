import Foundation

// MARK: - Date styles

/// The six date styles of a `format` operand (`formats[name] = { date: { style } }`, `sh.pipeline-operands@1`).
///
/// A style is a name, never a pattern string: a pattern would freeze one region's order into every published layout.
public enum ServerUIDateStyle: String, Sendable, CaseIterable {
    case shortDate = "short-date"
    case longDate = "long-date"
    case weekdayDate = "weekday-date"
    case time
    case dateTime = "date-time"
    case relative
}

/// How one argument of a `format` operand is drawn: a number with at most six fraction digits, or a date in one of the closed styles.
public enum ServerUIFormatSpec: Equatable, Sendable {
    case number(ServerUINumberFormat)
    case date(ServerUIDateStyle)
}

// MARK: - Drawing a date

/// Draws a date or a date and time in one of the six styles.
///
/// **United States English is pinned.** For `en_US` (and for a reader that gives no locale) the text is the Studio's: all integer
/// arithmetic, so the evaluation corpus holds the exact bytes and no time-zone database, `Intl` or ICU data version can change them
/// (ICU 72 put a narrow no-break space before `AM`, which a published layout must not inherit). Any other locale is drawn by the
/// system's formatters in the phone's language and region, on the clock's fixed offset.
///
/// | Style | en_US example |
/// |---|---|
/// | `short-date` | `Nov 12`; with the year when it is not the clock's year: `Nov 12, 2025` |
/// | `long-date` | `November 12, 2026` |
/// | `weekday-date` | `Thu, Nov 12` |
/// | `time` | `9:41 AM` (a date without a time is midnight: `12:00 AM`) |
/// | `date-time` | `Nov 12 at 9:41 AM` (the short date's year rule) |
/// | `relative` | `Today`, `Yesterday`, `Tomorrow`, `3 days ago`, `In 3 days`: whole days on the clock |
///
/// `short-date`, `date-time` and `relative` need the clock (they ask what today is); without one they have no text.
public enum ServerUIDateFormat {
    private static let months = ["January", "February", "March", "April", "May", "June", "July", "August", "September",
                                 "October", "November", "December"]
    private static let weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    /// The text of `text` (a date or a date and time) in `style` on `clock`, or `nil` when there is none.
    public static func text(_ style: ServerUIDateStyle, of text: String, clock: ServerUIClock?, locale: Locale? = nil) -> String? {
        guard let time = ServerUIDates.wallTime(text, utcOffsetMinutes: clock?.utcOffsetMinutes ?? 0) else { return nil }
        let today = clock.flatMap(Self.today)
        if style.needsClock, today == nil { return nil }
        if let locale, !isPinned(locale) { return localized(style, time: time, today: today, clock: clock, locale: locale) }
        return pinned(style, time: time, today: today)
    }

    /// Whether the locale is one the pinned United States English text stands for.
    static func isPinned(_ locale: Locale) -> Bool {
        let language = locale.language.languageCode?.identifier
        let region = locale.region?.identifier
        return (language == "en" || language == nil) && (region == "US" || region == nil)
    }

    private static func today(_ clock: ServerUIClock) -> (year: Int, days: Int)? {
        guard let day = ServerUIDates.today(of: clock) else { return nil }
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return (parts[0], ServerUIDates.daysFromCivil(year: parts[0], month: parts[1], day: parts[2]))
    }

    private static func clockText(_ seconds: Int) -> String {
        let hour = seconds / 3_600, minute = seconds / 60 % 60
        let twelve = hour % 12 == 0 ? 12 : hour % 12
        return "\(twelve):\(minute < 10 ? "0" : "")\(minute) \(hour < 12 ? "AM" : "PM")"
    }

    private static func pinned(_ style: ServerUIDateStyle, time: ServerUIWallTime, today: (year: Int, days: Int)?) -> String? {
        let (year, month, day) = ServerUIDates.civil(fromDays: time.days)
        let monthShort = String(months[month - 1].prefix(3))
        switch style {
        case .longDate: return "\(months[month - 1]) \(day), \(year)"
        case .weekdayDate:
            let weekday = ((time.days + 4) % 7 + 7) % 7
            return "\(weekdays[weekday]), \(monthShort) \(day)"
        case .time: return clockText(time.seconds)
        case .shortDate, .dateTime:
            guard let today else { return nil }
            let date = "\(monthShort) \(day)\(year == today.year ? "" : ", \(year)")"
            return style == .shortDate ? date : "\(date) at \(clockText(time.seconds))"
        case .relative:
            guard let today else { return nil }
            let apart = time.days - today.days
            switch apart {
            case 0: return "Today"
            case -1: return "Yesterday"
            case 1: return "Tomorrow"
            case ..<0: return "\(-apart) days ago"
            default: return "In \(apart) days"
            }
        }
    }

    /// The system's text for a locale other than United States English, on the clock's fixed offset.
    private static func localized(_ style: ServerUIDateStyle, time: ServerUIWallTime, today: (year: Int, days: Int)?,
                                  clock: ServerUIClock?, locale: Locale) -> String? {
        let offset = clock?.utcOffsetMinutes ?? 0
        let date = Date(timeIntervalSince1970: TimeInterval(time.instant - offset * 60))
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = TimeZone(secondsFromGMT: offset * 60)
        let year = ServerUIDates.civil(fromDays: time.days).year
        let sameYear = today.map { $0.year == year } ?? true
        switch style {
        case .longDate: formatter.dateStyle = .long; formatter.timeStyle = .none
        case .weekdayDate: formatter.setLocalizedDateFormatFromTemplate("EEEMMMd")
        case .time: formatter.dateStyle = .none; formatter.timeStyle = .short
        case .shortDate: formatter.setLocalizedDateFormatFromTemplate(sameYear ? "MMMd" : "yMMMd")
        case .dateTime: formatter.setLocalizedDateFormatFromTemplate(sameYear ? "MMMdjmm" : "yMMMdjmm")
        case .relative:
            guard let today else { return nil }
            let relative = RelativeDateTimeFormatter()
            relative.locale = locale
            relative.dateTimeStyle = .named
            relative.unitsStyle = .full
            relative.formattingContext = .beginningOfSentence
            return relative.localizedString(from: DateComponents(day: time.days - today.days))
        }
        return formatter.string(from: date)
    }
}

extension ServerUIDateStyle {
    /// Whether the style asks what today is (`short-date`, `date-time` and `relative`), so it needs the clock and re-draws with it.
    var needsClock: Bool { self == .shortDate || self == .dateTime || self == .relative }
}
