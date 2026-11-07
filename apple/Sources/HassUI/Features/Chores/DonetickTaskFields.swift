import HassCore
import HassDesign
import SwiftUI

// MARK: - Fields

/// The task form's fields (web `DonetickTaskFormBody`), in a grouped `Form`.
struct DonetickTaskFormFields {
    var editing: Bool
    var viewer: ChoresConfig.Resident?
    var error: String?
    var onDelete: (() -> Void)?
    @FocusState private var repeatFocused: Bool

    /// What the Task Name field is for.
    static let nameFooter = "A short name for the chore, as it appears in your lists. For example, “Take out the recycling”."
    /// What the Description field is for.
    static let descriptionFooter = "Optional. Add steps, notes or where to find supplies. It shows with the task when you open it."

}

/// Bindings between the form's `yyyy-MM-dd` / `HH:mm` strings and date pickers in the device's time zone.
enum DonetickDueBinding {
    /// The two formats the form uses, built once: a formatter per binding read was allocated on every body pass.
    private nonisolated(unsafe) static let dateFormatter = makeFormatter("yyyy-MM-dd")
    private nonisolated(unsafe) static let timeFormatter = makeFormatter("HH:mm")

    private static func makeFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = format
        return formatter
    }

    static func formatter(_ format: String) -> DateFormatter {
        switch format {
        case "yyyy-MM-dd": dateFormatter
        case "HH:mm": timeFormatter
        default: makeFormatter(format)
        }
    }

    /// Turning the date on picks today; off clears it.
    static func hasDate(_ form: Binding<DonetickTaskForm>, now: Date = .now) -> Binding<Bool> {
        Binding(get: { !form.wrappedValue.dueDate.isEmpty },
                set: { form.wrappedValue.dueDate = $0 ? formatter("yyyy-MM-dd").string(from: now) : "" })
    }

    /// Turning the time on picks noon (the web's default when only a date is set); off clears it.
    static func hasTime(_ form: Binding<DonetickTaskForm>) -> Binding<Bool> {
        Binding(get: { !form.wrappedValue.dueTime.isEmpty }, set: { form.wrappedValue.dueTime = $0 ? "12:00" : "" })
    }

    static func date(_ form: Binding<DonetickTaskForm>) -> Binding<Date> {
        Binding(get: { formatter("yyyy-MM-dd").date(from: form.wrappedValue.dueDate) ?? .now },
                set: { form.wrappedValue.dueDate = formatter("yyyy-MM-dd").string(from: $0) })
    }

    static func time(_ form: Binding<DonetickTaskForm>) -> Binding<Date> {
        Binding(get: { formatter("HH:mm").date(from: form.wrappedValue.dueTime) ?? .now },
                set: { form.wrappedValue.dueTime = formatter("HH:mm").string(from: $0) })
    }
}
