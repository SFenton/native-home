#if os(iOS)
import HassCore
import HassDesign
import UIKit

/// Adapts the canonical value/closure row to a configured provider; the shell owns the list and confirmation.
@MainActor
enum UKServerUITodoRow {
    static func canEdit(_ item: TodoItem, provider: ServerUITodoProvider) -> Bool {
        provider.configuration.canRename || (provider.configuration.canEditTask &&
            DonetickEditTarget(item: item, listEntityId: provider.configuration.entityId) != nil)
    }

    static func configure(_ row: UKTodoItemRow, item: TodoItem, provider: ServerUITodoProvider,
                          surface: TileSurface, edit: (() -> Void)?,
                          confirmDelete: @escaping (TodoItem, ServerUITodoProvider.DeleteTicket) -> Void,
                          report: @escaping (any Error) -> Void) {
        let undo: (() -> Void)? = provider.controller.offersUndo(item) ? {
            Task {
                do { try await provider.undo(expected: item) }
                catch { report(error) }
            }
        } : nil
        let delete: (() -> Void)? = provider.configuration.canDelete ? {
            do { confirmDelete(item, try provider.deleteTicket(expected: item)) }
            catch { report(error) }
        } : nil
        let editor: (() -> Void)? = canEdit(item, provider: provider) ? edit.map { open in
            {
                do { try provider.validate(expected: item); open() }
                catch { report(error) }
            }
        } : nil
        row.configure(item: item, surface: surface, actions: .init(onToggle: {
            do { try provider.validate(expected: item) }
            catch { report(error); return }
            Task {
                do { try await provider.toggle(expected: item) }
                catch { report(error) }
            }
            if item.status != .completed, provider.configuration.hideCompleted {
                Announcer.announce(TodoItemRow.completionAnnouncement(item.displayTitle))
            }
        }, onEdit: editor, onUndo: undo, onDelete: delete))
    }
}
#endif
