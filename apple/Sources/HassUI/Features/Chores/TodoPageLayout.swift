import HassCore
import HassDesign
import SwiftUI

// MARK: - Layout policy

/// Which lists a page shows, separated from the view so it can be unit tested.
enum TodoPageLayout {
    /// Space above the first row of a page's list. The list is inset-grouped, so its first row is masked to the group's
    /// rounded top corners even with a clear background; a row with no top inset draws its first glyph inside that arc and
    /// loses part of it (the Q of "Quick Links", 2026-10-26). Every first row takes at least this.
    static let leadingRowTopInset = HassTokens.Spacing.m

    /// The page's side margin in the stack layout: where the inset-grouped list put the modules' edges (16 pt).
    static let horizontalMargin = HassTokens.Spacing.l
    /// The same in a regular-width window, where the inset-grouped list's margin is 20 pt (measured on the iPad, 2026-10-27).
    static let regularHorizontalMargin: CGFloat = 20

    /// The stack layout's side margin for a window.
    static func sideMargin(regularWidth: Bool) -> CGFloat { regularWidth ? regularHorizontalMargin : horizontalMargin }

    /// One list as the page sees it.
    struct Section: Identifiable {
        var list: ChoresConfig.TodoList
        var controller: TodoListController
        /// The list has (or may have) open items, so it is drawn.
        var isShown: Bool
        /// Whether the list is known: loaded or cached, or its entity says it is empty.
        var isSettled: Bool
        var id: String { list.entityId }
    }

    /// The page's lists the viewer can see, with whether each is drawn (web `TodoSection` visibility).
    @MainActor
    static func sections(for page: ChoresConfig.Page, viewerUserId: String?, store: EntityStore, todos: TodoStore) -> [Section] {
        page.lists.compactMap { section(for: $0, viewerUserId: viewerUserId, store: store, todos: todos) }
    }

    /// One list as the page sees it, or `nil` when the viewer doesn't see it. The Summary sheet's chore tabs read their
    /// lists through this too, so a list shows and hides by the same rule on every surface.
    @MainActor
    static func section(for list: ChoresConfig.TodoList, viewerUserId: String?, store: EntityStore, todos: TodoStore) -> Section? {
        let entity = store.entity(list.entityId).state
        let controller = todos.controller(for: list.entityId)
        // A row just ticked keeps its list (and its Undo) on screen though the open count already reads zero.
        let keepsOpen = !controller.recentlyCompleted.isEmpty
        guard list.isVisible(to: viewerUserId, openItems: entity, keepsOpen: keepsOpen) else { return nil }
        // The entity's state is its open-item count; zero hides the list before any fetch.
        let mayHaveItems = keepsOpen || (entity.map { $0.isUnavailable || ($0.numericState ?? 0) > 0 } ?? true)
        if !mayHaveItems { return Section(list: list, controller: controller, isShown: false, isSettled: true) }
        guard controller.items != nil else { return Section(list: list, controller: controller, isShown: true, isSettled: false) }
        let hasItems = !controller.visibleItems(hideCompleted: list.hideCompleted).isEmpty
        return Section(list: list, controller: controller, isShown: hasItems, isSettled: true)
    }

    /// How tall the sheet a form opens in is (owner, 2026-10-30): the task form, New Task and Edit Task alike, opens at one
    /// pre-determined size (the large detent on an iPhone, the form sheet's own size on a regular width) and never resizes, so
    /// the loading arc, the fade to the form and the form itself all sit in the same frame, as in the web dashboard's fixed
    /// 820 pt modal (`ha-sfenton-react-dash@7c4ebf9:src/components/hass/CreateDonetickTaskSheet.tsx:7-12`). The one-field prompts
    /// (a grocery, a rename, an admin to-do) stay content-fitted.
    static func sheetHeight(_ sheet: TodoSheet, addAction: ChoresConfig.AddAction) -> HassSheetHeight {
        switch sheet {
        case .editTask: .full
        case .create:
            if case .assignedTask = addAction { .full } else { .fitted }
        case .renameTodo: .fitted
        }
    }

    #if DEBUG
    /// `FENTON_GALLERY_OPEN=edit-task|new-task`: the form a gallery opens as soon as the page appears (screenshots and the loading
    /// sequence). Edit Task opens a fixture task (use `FENTON_GALLERY_TODO_PAGE=alexs-chores`).
    static func galleryLaunchSheet(page: ChoresConfig.Page) -> TodoSheet? {
        switch ProcessInfo.processInfo.environment["FENTON_GALLERY_OPEN"] {
        case "edit-task":
            guard let list = page.lists.first else { return nil }
            return .editTask(DonetickEditTarget(itemUid: "15--fixture", taskId: 15, todoEntityId: list.entityId))
        case "new-task": return .create
        default: return nil
        }
    }
    #endif
}
