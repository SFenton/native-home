import HassCore
import HassDesign
import SwiftUI

// MARK: - Sheets and their targets

/// The sheets a todo page presents.
enum TodoSheet: Identifiable, Hashable {
    case create
    case editTask(DonetickEditTarget)
    case renameTodo(AdminTodoEditTarget)

    var id: String {
        switch self {
        case .create: "create"
        case let .editTask(target): "edit-\(target.todoEntityId)-\(target.itemUid)"
        case let .renameTodo(target): "rename-\(target.todoEntityId)-\(target.itemUid ?? target.originalTitle)"
        }
    }
}

/// A DoneTick task opened from a list row (web `DonetickTaskEditTarget`).
struct DonetickEditTarget: Hashable, Sendable {
    var itemUid: String
    var taskId: Int
    var todoEntityId: String

    init(itemUid: String, taskId: Int, todoEntityId: String) {
        self.itemUid = itemUid
        self.taskId = taskId
        self.todoEntityId = todoEntityId
    }

    /// The target for a DoneTick row (only rows whose uid carries a task id can be edited), else `nil`. The Chores pages
    /// and the Summary sheet open the same form from it.
    init?(item: TodoItem, listEntityId: String) {
        guard let taskId = item.donetickTaskId, let uid = item.uid else { return nil }
        self.init(itemUid: uid, taskId: taskId, todoEntityId: listEntityId)
    }
}

/// An admin to-do opened for renaming (web `AdminTodoEditTarget`).
struct AdminTodoEditTarget: Hashable, Sendable {
    var itemUid: String?
    var originalTitle: String
    var todoEntityId: String
}
