import Foundation

/// One item of a Home Assistant `todo` list (`todo/item/list`), with the web's row logic
/// (`ha-sfenton-react-dash:src/components/hass/TodoListPanel.tsx`).
public struct TodoItem: Codable, Hashable, Sendable, Identifiable {
    /// `needs_action` or `completed`.
    public enum Status: String, Codable, Sendable {
        case needsAction = "needs_action"
        case completed

        /// The status a tap moves to.
        public var toggled: Status { self == .completed ? .needsAction : .completed }
    }

    public var uid: String?
    public var summary: String?
    public var status: Status
    public var description: String?
    /// `due` from the server: an ISO date (`2026-10-11`) or date-time.
    public var due: String?

    /// Creates an item.
    public init(uid: String?, summary: String?, status: Status = .needsAction, description: String? = nil, due: String? = nil) {
        self.uid = uid
        self.summary = summary
        self.status = status
        self.description = description
        self.due = due
    }

    /// Builds an item from the websocket's JSON, accepting `due`, `due_datetime` or `due_date`.
    public init?(json: JSONValue) {
        guard case .object = json else { return nil }
        uid = json["uid"]?.string
        summary = json["summary"]?.string
        status = json["status"]?.string.flatMap(Status.init(rawValue:)) ?? .needsAction
        description = json["description"]?.string
        due = json["due_datetime"]?.string ?? json["due"]?.string ?? json["due_date"]?.string
    }

    /// The service's item key: the uid, else the summary (web `todoIdentity`).
    public var identity: String { uid ?? summary ?? "" }

    public var id: String { identity }

    /// DoneTick task id from a uid like `42--2026-10-11` (web `donetickTaskIdFromUid`).
    public var donetickTaskId: Int? {
        guard let uid, let head = uid.components(separatedBy: "--").first, let id = Int(head), id > 0 else { return nil }
        return id
    }

    // MARK: - Due

    /// When the item is due, if its `due` parses.
    public var dueDate: Date? { due.flatMap(DueDateCache.shared.date(for:)) }

    /// Parses an ISO date-time (with or without fractional seconds) or a bare date as local midnight,
    /// like JavaScript's `new Date(...)` for these shapes.
    static func parseDue(_ value: String) -> Date? {
        if value.count == 10 {
            // `new Date("2026-10-11")` is UTC midnight.
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "UTC")!
            let parts = value.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3 else { return nil }
            return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
        }
        if let date = HassDates.iso8601(value) { return date }
        // A date-time without a zone is local time.
        return HassDates.localDateTime(value)
    }

    /// Parses `due` once per distinct string: a row's body asks for its due label on every pass, and the same few hundred
    /// strings come back each time (a scrolling page spent ~1.5% of the main thread re-parsing them, 2026-10-27). A string is
    /// pure input except for a date-time without a zone, which reads in the phone's time zone
    /// (`HassDates`'s local calendar follows the system), so the cache starts over when the zone identifier changes and when it outgrows
    /// ``DueDateCache/limit``.
    final class DueDateCache: @unchecked Sendable {
        static let shared = DueDateCache()
        /// Entries kept before the cache starts over.
        static let limit = 1024
        private let lock = NSLock()
        private var dates: [String: Date?] = [:]
        private var zoneIdentifier = TimeZone.autoupdatingCurrent.identifier

        /// The parsed date for `value`, or `nil` when it doesn't parse.
        func date(for value: String) -> Date? { date(for: value, zone: TimeZone.autoupdatingCurrent.identifier) }

        /// As ``date(for:)`` with the current time zone's identifier given (tests change it).
        func date(for value: String, zone: String) -> Date? {
            lock.lock()
            if zone != zoneIdentifier {
                dates.removeAll(keepingCapacity: true)
                zoneIdentifier = zone
            }
            if let cached = dates[value] { lock.unlock(); return cached }
            lock.unlock()
            let parsed = TodoItem.parseDue(value)
            lock.lock()
            if dates.count >= Self.limit { dates.removeAll(keepingCapacity: true) }
            dates[value] = .some(parsed)
            lock.unlock()
            return parsed
        }

        /// Entries held now (tests).
        var count: Int { lock.lock(); defer { lock.unlock() }; return dates.count }
    }

    /// Built once: compiling a regex per row per render was a share of a Chores scroll frame.
    private enum Parsers {
        static let batteryWords = try? NSRegularExpression(pattern: #"\bbatter(?:y|ies)\b"#, options: .caseInsensitive)
    }

    /// How urgent the due label reads.
    public enum DueTone: String, Sendable {
        case future
        /// Overdue by less than a day.
        case overdueHours
        /// Overdue by a day or more.
        case overdueLong
    }

    /// "Due in 3 days" or "2 hours overdue" (web `relativeDueInfo`).
    public func dueLabel(now: Date = .now) -> (text: String, tone: DueTone)? {
        guard let due = dueDate else { return nil }
        let difference = due.timeIntervalSince(now)
        let magnitude = abs(difference)
        let hour = 3600.0, day = 24 * hour, week = 7 * day, month = 30 * day
        let (unit, divisor): (String, Double) =
            magnitude < day ? ("hour", hour) : magnitude < 21 * day ? ("day", day) : magnitude < 60 * day ? ("week", week) : ("month", month)
        let amount = max(1, Int((magnitude / divisor).rounded()))
        let span = "\(amount) \(unit)\(amount == 1 ? "" : "s")"
        if difference >= 0 { return ("Due in \(span)", .future) }
        return ("\(span) overdue", unit == "hour" ? .overdueHours : .overdueLong)
    }

    // MARK: - Title

    /// The row title: the summary, with a battery-maintenance task's level appended
    /// (`Replace Battery · 18%`; web `batteryMaintenanceLevel`).
    public var displayTitle: String {
        let summary = summary?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = (summary?.isEmpty == false ? summary : nil) ?? "Untitled task"
        guard let level = batteryLevel else { return title }
        let normalized = Self.capitalizingBatteryWords(title)
        if normalized.hasSuffix("(\(level))") || normalized.hasSuffix(" · \(level)") { return normalized }
        return "\(normalized) · \(level)"
    }

    /// `18%` from a description carrying a `Maintenance reference: BATT-…` line.
    var batteryLevel: String? {
        guard let description = description?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty,
              description.range(of: #"\bMaintenance reference:\s*BATT-[A-Z0-9]+\b"#, options: [.regularExpression, .caseInsensitive]) != nil,
              let match = description.range(of: #"\bbattery is at\s+(\d+(?:\.\d+)?)%"#, options: [.regularExpression, .caseInsensitive])
        else { return nil }
        let digits = description[match].drop { !$0.isNumber }.prefix { $0.isNumber || $0 == "." }
        return "\(digits)%"
    }

    private static func capitalizingBatteryWords(_ title: String) -> String {
        guard let regex = Parsers.batteryWords else { return title }
        var result = title
        for match in regex.matches(in: title, range: NSRange(title.startIndex..., in: title)).reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let word = result[range]
            result.replaceSubrange(range, with: word.prefix(1).uppercased() + word.dropFirst().lowercased())
        }
        return result
    }

    // MARK: - Sorting

    /// Earliest due first; undated items last, in server order (web `sortByDueDate`).
    public static func sortedByDue(_ items: [TodoItem]) -> [TodoItem] {
        items.enumerated().sorted { left, right in
            switch (left.element.dueDate, right.element.dueDate) {
            case let (l?, r?) where l != r: l < r
            case (nil, _?): false
            case (_?, nil): true
            default: left.offset < right.offset
            }
        }.map(\.element)
    }
}
