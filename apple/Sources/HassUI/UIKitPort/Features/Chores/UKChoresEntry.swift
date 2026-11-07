#if os(iOS)
import HassCore
import UIKit

// Owned by the Chores lane (`.agents/platforms/apple/uikit-port.md`). The screens of `Features/Chores/`.
extension UKScreens {
    /// The Chores tab (``ChoresScreen``): quick links to Groceries and each list of chores, then the viewer's own chores.
    static func chores(_ context: UKContext) -> UIViewController {
        guard let model = UKChoresPages.liveModel(context) else { return UKPlaceholderViewController(title: "Chores", symbol: "checklist") }
        return UKChoresPages.root(context: context, model: model)
    }

    /// The Grocery List route of Home (`HomeRouteDestination`): the Groceries todo page with its own model.
    static func groceryList(_ context: UKContext) -> UIViewController {
        guard let model = UKChoresPages.liveModel(context) else { return UKPlaceholderViewController(title: "Grocery List", symbol: "cart") }
        return UKChoresPages.page(ChoresConfig.page("groceries") ?? ChoresConfig.groceries, context: context, model: model)
    }

    /// A Chores page a quick link opened, pushed by the section's stack (``ShellRoute/chores(_:)``); in a window that splits the Chores
    /// root shows it as a column instead.
    static func choresPage(_ id: String, context: UKContext) -> UIViewController {
        guard let page = ChoresConfig.page(id) else { return UKPlaceholderViewController(title: "Chores", symbol: "checklist") }
        guard let model = UKChoresPages.liveModel(context) else { return UKPlaceholderViewController(title: page.title, symbol: "checklist") }
        return UKChoresPages.page(page, context: context, model: model)
    }

    /// The admin To-Do page Settings opens (``AdminTodoScreen``), with its own model.
    static func adminTodo(_ context: UKContext) -> UIViewController {
        guard let model = UKChoresPages.liveModel(context) else { return UKPlaceholderViewController(title: "To-Do", symbol: "checklist") }
        return UKChoresPages.page(ChoresConfig.page("to-do") ?? ChoresConfig.adminTodo, context: context, model: model)
    }
}

/// Builds the Chores pages (``ChoresScreen``, ``TodoPageScreen``, ``AdminTodoScreen``).
@MainActor
enum UKChoresPages {
    /// The live ``ChoresModel`` for a signed-in context, refreshing the viewer (``ChoresModelHost``); nil without a connection.
    static func liveModel(_ context: UKContext) -> ChoresModel? {
        guard let connection = context.connection else { return nil }
        let model = ChoresModel.live(connection: connection, session: context.session)
        Task { await model.refreshViewer() }
        return model
    }

    /// The Chores tab's content: the todo page with the quick links as its header; a quick link pushes that page.
    static func root(context: UKContext, model: ChoresModel) -> UKTodoPageViewController {
        weak var page: UKTodoPageViewController?
        let header = UKChoreQuickLinksView(context: context, model: model) { opened in
            // A route: the section's stack pushes it, or the root shows it as a column where the window splits.
            page?.openQuickLink(opened)
        }
        let root = UKTodoPageViewController(context: context, page: ChoresConfig.page("chores") ?? ChoresConfig.chores, model: model, header: header, title: "Chores")
        page = root
        return root
    }

    /// A pushed todo page: Groceries, a resident's chores, Unassigned, Home Improvement, or the admin To-Do (``TodoPageScreen``).
    static func page(_ page: ChoresConfig.Page, context: UKContext, model: ChoresModel) -> UKTodoPageViewController {
        UKTodoPageViewController(context: context, page: page, model: model)
    }
}
#endif
