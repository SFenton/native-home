import HassCore
import HassDesign
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Rename admin to-do

/// Renames an admin to-do with `todo.update_item` `rename` (web `EditTodoItemSheet`).
struct RenameTodoItemSheet {
    var target: AdminTodoEditTarget
    var onSaved: () -> Void = {}




    /// Savable when the item has an identity and the trimmed name is new and not empty.
    static func canSave(target: AdminTodoEditTarget, draft: String) -> Bool {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return target.itemUid != nil && !trimmed.isEmpty && trimmed != target.originalTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }



}
