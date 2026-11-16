import HassCore
import SwiftUI

// MARK: - Todo drafts

extension TodoPageLayout {
    /// Where the open form shows for a window that does or does not split. The same `sheet` value drives both, so a form
    /// moving between them keeps its identity, and with ``TodoDraftStore`` its draft.
    struct Presentation: Equatable {
        /// The form shown as a sheet.
        var sheet: TodoSheet?
        /// The form shown in the trailing pane.
        var pane: TodoSheet?
    }

    /// The hand-over rule: a splitting window shows the open form in the pane, a single-page one as a sheet.
    static func presentation(open: TodoSheet?, split: Bool) -> Presentation {
        split ? Presentation(sheet: nil, pane: open) : Presentation(sheet: open, pane: nil)
    }

    /// What happens when a form is asked for while the pane shows another.
    enum SwitchDecision: Equatable { case switchNow, confirm }

    /// Replacing the open pane form with another asks first when the open one has unsaved edits; reopening the same form,
    /// an empty pane and a clean form switch at once.
    static func switchDecision(current: TodoSheet?, next: TodoSheet, hasEdits: Bool) -> SwitchDecision {
        guard let current, current != next, hasEdits else { return .switchNow }
        return .confirm
    }

    /// Rows of this page open a form: DoneTick tasks and the admin To-Do; Groceries rows only tick off.
    static func editsItems(_ page: ChoresConfig.Page) -> Bool { page.hasTaskForm || page.editsAdminTodo }

    /// What the trailing pane says while no form is open: pick a row to edit it, or add on a list with nothing to edit.
    static func panePrompt(_ page: ChoresConfig.Page) -> String {
        editsItems(page) ? "Select an item to edit it." : "Add an item with the button below."
    }
}
