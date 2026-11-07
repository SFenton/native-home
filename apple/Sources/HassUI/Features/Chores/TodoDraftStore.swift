import HassCore
import SwiftUI

// MARK: - Todo drafts

/// The unsaved drafts of a todo page's forms, held by the page and keyed by form identity (``TodoSheet/id``), so a form
/// keeps its draft when it moves between the trailing pane and a sheet as the window starts or stops splitting (a Duo
/// folded or unfolded, an iPad rotated). Discard, Save and Close clear the entry.
@MainActor
final class TodoDraftStore {
    /// What one form has typed.
    enum Draft: Equatable {
        /// A single text field: Add Grocery's item, Rename's name.
        case text(String)
        /// Add Admin To-Do's text and chosen images.
        case admin(task: String, images: [AdminTodoUpload.Image])
        /// A DoneTick task form, the form it opened with (for the changed-fields diff) and the task's name.
        case donetick(form: DonetickTaskForm, initial: DonetickTaskForm, name: String)
    }

    private var drafts: [String: Draft] = [:]

    /// The draft for a form, if it has one.
    func draft(for id: String) -> Draft? { drafts[id] }

    /// Keeps `draft` for a form.
    func save(_ draft: Draft, for id: String) { drafts[id] = draft }

    /// Drops a form's draft (it was saved, discarded or closed).
    func clear(_ id: String) { drafts[id] = nil }

    /// Whether any form holds a draft.
    var isEmpty: Bool { drafts.isEmpty }
}

/// A form's view of the page's store: its own entry. Without a store (a form outside a todo page) it does nothing.
@MainActor
struct TodoDraftHandle {
    var store: TodoDraftStore?
    var key: String?

    /// The saved draft for this form.
    var draft: TodoDraftStore.Draft? {
        guard let store, let key else { return nil }
        return store.draft(for: key)
    }

    /// Saves this form's draft.
    func save(_ draft: TodoDraftStore.Draft) {
        guard let store, let key else { return }
        store.save(draft, for: key)
    }
}

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
