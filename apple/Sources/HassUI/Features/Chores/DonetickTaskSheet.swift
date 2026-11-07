import HassCore
import HassDesign
import SwiftUI

/// Create or edit a DoneTick task (web `CreateDonetickTaskSheet` + `DonetickTaskFormPage`).
///
/// Creating sends `donetick.create_task_form`; editing loads the task with `donetick.get_task`, saves with
/// `donetick.update_task_form` and can delete it (`todo.remove_item`) after a confirmation.
struct DonetickTaskSheet {
    enum Mode: Hashable {
        case create(defaultAssignee: String)
        case edit(DonetickEditTarget)
    }

    var mode: Mode
    var onSaved: () -> Void = {}
    /// A page pushed into another sheet's navigation stack (Edit Task from Your Summary, owner 2026-10-24,
    /// `sheet-stacking-close`): no stack of its own, a guarded Back in place of Cancel.
    var isPushed = false


    enum Busy { case saving, deleting }



    private var title: String { mode.editTarget == nil ? "New Task" : "Edit Task" }






}
