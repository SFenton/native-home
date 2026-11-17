#if os(iOS)
import HassCore
import HassDesign
import UIKit

// MARK: - Actions

/// What a todo row does, shared by the Chores pages and the Summary sheet's chore tabs (``TodoListSection``): one source for the
/// swipes, the context menu and the VoiceOver actions (``TodoRowActions``), the check-off with its announcement, and the delete
/// confirmation.
@MainActor
enum UKTodoListActions {
    /// The actions a row offers.
    static func actions(for item: TodoItem, canEdit: Bool, canDelete: Bool) -> TodoRowActions {
        TodoRowActions(item: item, canEdit: canEdit, canDelete: canDelete)
    }

    /// Checks `item` off (or puts it back); a tick that keeps the row listed in its done look is announced (HIG Undo and redo).
    static func toggle(_ item: TodoItem, in list: ChoresConfig.TodoList, controller: TodoListController) {
        let completing = item.status != .completed
        Task { await controller.toggle(item, completionScript: list.completionScript) }
        if completing, list.hideCompleted { Announcer.announce(TodoItemRow.completionAnnouncement(item.displayTitle)) }
    }

    /// Reopens a task checked off a moment ago (`todo.update_item`, also on the Admin To-Do).
    static func undo(_ item: TodoItem, controller: TodoListController) {
        Task { await controller.undo(item) }
    }

    /// The fill behind a swipe button (``TodoListSection/swipeTint(_:)``).
    static func swipeTint(_ action: TodoRowActions.Action) -> UIColor { UIColor(TodoListSection.swipeTintToken(action)) }

    /// The swipe buttons for an edge: Complete leads in green; Delete (red, outermost) and Edit (blue) trail. A full swipe performs
    /// the first.
    ///
    /// `perform` settles the swipe through `done`: Delete holds the row open under its confirmation and calls `done(true)` as the row
    /// leaves or `done(false)` on cancel (`.agents/patterns/list-row-removal.md`); every other action calls `done(true)` at once.
    static func swipeConfiguration(_ actions: TodoRowActions, item: TodoItem, leading: Bool,
                                   perform: @escaping (TodoRowActions.Action, _ done: @escaping (Bool) -> Void) -> Void) -> UISwipeActionsConfiguration? {
        let list = leading ? actions.leading : actions.trailing
        return UKSwipeAction.configuration(list.map { action in
            UKSwipeAction(action.title, systemImage: action.symbol, tint: swipeTint(action), identifier: "todo.swipe.\(action.rawValue).\(item.identity)", role: action == .delete ? .destructive : .normal) { done in
                perform(action, done)
            }
        })
    }

    /// The long-press menu: every action, leading then trailing.
    static func menu(_ actions: TodoRowActions, perform: @escaping (TodoRowActions.Action) -> Void) -> UIMenu {
        UIMenu(children: actions.all.map { action in
            UIAction(title: action.title, image: UIImage(systemName: action.symbol), attributes: action == .delete ? .destructive : []) { _ in perform(action) }
        })
    }

    /// Asks before deleting a task (``AlertCopy``): one dialog on the page, since a swipe or menu Delete is gone once the swipe
    /// closes.
    static func confirmDelete(_ item: TodoItem, controller: TodoListController, from presenter: UIViewController, source: UKPopoverSource = .none) {
        UKAlerts.confirmationDialog(TodoListSection.deleteSpec(for: item), from: presenter, source: source, confirmIdentifier: "todo.delete.confirm") {
            Task { await controller.remove(item) }
        }
    }
}

// MARK: - Cells

/// A loading list's arc, centred in a 44 pt row (`ArcSpinner(.compact, label: "Loading …")`).
@MainActor
final class UKTodoSpinnerRow: UIView {
    private let spinner: UKArcSpinnerView

    init(label: String) {
        spinner = UKArcSpinnerView(.compact, label: label)
        super.init(frame: .zero)
        spinner.color = UKDesignInk.primary
        spinner.translatesAutoresizingMaskIntoConstraints = false
        addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: centerXAnchor), spinner.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(greaterThanOrEqualToConstant: HassTokens.minTarget),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}
#endif
