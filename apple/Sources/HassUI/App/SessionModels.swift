import HassCore
import SwiftUI

/// The models that must outlive the pages that show them, for the life of the signed-in session (design:
/// `.agents/design/motion.md` §3, "A screen animates in only when it had nothing to show").
///
/// A page pushed from a `NavigationStack` is built again on every push, and so was its `@State`: the Food hub and the inventory
/// pages made their models anew each time, reloaded, and ran their loading gate (a spinner of at least a second) on every visit.
/// Held here, a revisit finds its results already loaded and shows them at once; a stale copy refreshes quietly behind them.
/// `MainTabView` owns one instance, so signing out drops it.
@MainActor
final class SessionModels {
    /// The Food hub's models: Suggested Recipes and the Recipes results.
    let food = FoodModels()
    private var inventory: InventoryModels?

    /// The inventory pages' models, made on first use for this connection.
    func inventory(for connection: HassConnection) -> InventoryModels {
        if let inventory { return inventory }
        let created = InventoryModels(client: EverShelfClient(caller: connection))
        inventory = created
        return created
    }
}
