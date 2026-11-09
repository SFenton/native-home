import HassCore
import HassDesign
import SwiftUI

// MARK: - Date fields

extension ScheduleDateField {
    /// A picker over a ``WallClock``: a date-only picker keeps the time and a time-only picker keeps the date.
    init(_ label: String, _ part: Part, _ value: WallClock, id identifier: String,
         calendar: Calendar = .current, onChange: @escaping (WallClock) -> Void) {
        self.init(label: label, part: part, value: value.date(in: calendar) ?? .now, identifier: identifier) { picked in
            let parts = WallClock(picked, calendar: calendar)
            switch part {
            case .date: onChange(WallClock(date: parts.date, time: value.time))
            case .time: onChange(WallClock(date: value.date, time: parts.time))
            case .dateAndTime: onChange(parts)
            }
        }
    }
}

/// Quiet time before a picker that writes to Home Assistant reports its value.
let liveDateCommitDelay: Duration = .milliseconds(900)
