import HassCore
import HassDesign
import SwiftUI

/// One todo list as a `List` section: an optional header row, any error, and its open items as checkable rows on one
/// module (web `TodoSection` + `TodoListPanel`; direction G mockups n5: an inset list on the wallpaper, as in Reminders).
///
/// The page is a real `List` because swipe actions need one before iOS 27 (owner, 2026-10-16; the Inventory pages do the
/// same). Each row draws its share of the module with ``ModuleRowBackground``, so the rows read as one card.
struct TodoListSection {
    var list: ChoresConfig.TodoList
    var controller: TodoListController
    /// The row's edit action, or `nil` when the row can't be edited.
    var editor: (TodoItem) -> (() -> Void)? = { _ in nil }
    /// Whether rows can be deleted, and whether that asks first.
    var deletion: Deletion = .unavailable




    /// Whether any open row shows an overdue span, which is drawn in orange or red.
    static func hasLateItem(_ items: [TodoItem], now: Date) -> Bool {
        items.contains { item in
            guard item.status != .completed, let tone = item.dueLabel(now: now)?.tone else { return false }
            return tone != .future
        }
    }
}
