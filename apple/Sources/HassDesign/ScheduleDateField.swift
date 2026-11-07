import SwiftUI

/// One date, time, or date-and-time picker in ``ScheduleDateFields``.
public struct ScheduleDateField: Identifiable {
    /// Which part of the moment the picker edits: the date, the time, or both in one row (the Calendar
    /// app's Starts/Ends idiom; HIG Pickers, "Date pickers").
    public enum Part: Sendable { case date, time, dateAndTime }

    public var label: String
    public var part: Part
    public var value: Date
    public var identifier: String
    /// Receives the picked moment; a date-only or time-only picker leaves the other part unchanged.
    public var onChange: (Date) -> Void
    /// The earliest moment the picker offers (an end picker passes its start), so an invalid pair cannot be picked
    /// (HIG Pickers: constrain the range rather than report the error afterwards).
    public var earliest: Date?
    /// The latest moment the picker offers (a start picker passes its end).
    public var latest: Date?
    public var id: String { identifier }

    /// The selectable range, or `nil` when the picker is unbounded.
    public var bounds: ClosedRange<Date>? {
        guard earliest != nil || latest != nil else { return nil }
        let low = earliest ?? .distantPast
        // A saved value already outside the other bound must stay reachable, so the range never inverts.
        return low...max(latest ?? .distantFuture, low)
    }

    /// This field limited to `earliest...latest` (either may be `nil`).
    public func limited(from earliest: Date? = nil, to latest: Date? = nil) -> ScheduleDateField {
        var copy = self
        copy.earliest = earliest
        copy.latest = latest
        return copy
    }

    /// Creates a field.
    public init(label: String, part: Part, value: Date, identifier: String, onChange: @escaping (Date) -> Void) {
        self.label = label
        self.part = part
        self.value = value
        self.identifier = identifier
        self.onChange = onChange
    }
}

extension ScheduleDateField.Part {
    /// The picker's components.
    var components: DatePickerComponents {
        switch self {
        case .date: .date
        case .time: .hourAndMinute
        case .dateAndTime: [.date, .hourAndMinute]
        }
    }
}
