import HassCore
import HassDesign
import SwiftUI

// MARK: - Deleting a task

extension TodoListSection {
    /// How a row's delete behaves on a page.
    enum Deletion: Equatable {
        /// The page can't delete tasks.
        case unavailable
        /// Asks first (``AlertCopy/delete(_:named:detail:)``), on the row.
        case confirm
        /// Deletes at once: grocery items are cheap to re-add (owner, 2026-10-24).
        case immediate
    }

    /// The confirmation for one task.
    static func deleteSpec(for item: TodoItem) -> AlertCopy.Spec {
        AlertCopy.delete("Task", named: item.displayTitle, detail: "This can't be undone.")
    }
}


extension TodoPageLayout {
    /// How a page's rows delete: grocery items go at once (cheap to re-add, and ticking one already clears it); other
    /// deletable lists confirm on the row.
    static func deletion(for page: ChoresConfig.Page) -> TodoListSection.Deletion {
        guard page.deletesItems else { return .unavailable }
        return page.id == ChoresConfig.groceries.id ? .immediate : .confirm
    }
}
