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
