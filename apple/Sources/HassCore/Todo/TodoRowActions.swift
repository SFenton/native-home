import Foundation

/// The actions a todo row offers, in one place so the swipe actions, the context menu and the VoiceOver custom actions
/// can never disagree (owner, 2026-10-16: "swipe to edit or delete one way, the opposite way to complete").
///
/// HIG, Lists and tables: the primary, non-destructive action leads (swipe from the leading edge, a full swipe performs
/// it) and the secondary and destructive ones trail, destructive outermost, as in Mail and Reminders. They mirror in
/// right-to-left layouts because SwiftUI's `.leading` and `.trailing` edges do.
public struct TodoRowActions: Equatable, Sendable {
    /// One thing a row can do.
    public enum Action: String, Sendable, CaseIterable {
        /// Check the task off.
        case complete
        /// Put a completed task back.
        case reopen
        /// Open the task's editor.
        case edit
        /// Remove the task, after a confirmation.
        case delete

        /// The action's name in a swipe button, context menu or VoiceOver action list.
        public var title: String {
            switch self {
            case .complete: "Complete"
            case .reopen: "Mark Not Done"
            case .edit: "Edit"
            case .delete: "Delete"
            }
        }

        /// The SF Symbol for the action.
        public var symbol: String {
            switch self {
            case .complete: "checkmark.circle.fill"
            case .reopen: "arrow.uturn.backward.circle"
            case .edit: "square.and.pencil"
            case .delete: "trash"
            }
        }
    }

    /// Swiped in from the leading edge; the first action is the full swipe.
    public var leading: [Action]
    /// Swiped in from the trailing edge, outermost first; the first action is the full swipe.
    public var trailing: [Action]

    /// Every action, leading then trailing: the context menu's and VoiceOver's list.
    public var all: [Action] { leading + trailing }

    /// Creates the actions for an item.
    /// - Parameters:
    ///   - item: The row's task; a completed one offers Mark Not Done instead of Complete.
    ///   - canEdit: Whether the page has an editor for the task.
    ///   - canDelete: Whether the page deletes tasks (``ChoresConfig/Page/deletesItems``).
    public init(item: TodoItem, canEdit: Bool, canDelete: Bool) {
        leading = [item.status == .completed ? .reopen : .complete]
        trailing = (canDelete ? [.delete] : []) + (canEdit ? [.edit] : [])
    }
}
