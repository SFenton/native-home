import HassCore
import HassDesign
import SwiftUI


/// Reloads a list when its entity changes or a sheet saved.
struct TodoReloadKey: Hashable {
    var entity: EntityState?
    var version: Int
}

extension TodoPageLayout {
    /// The empty state shows once every list is known and none is drawn, or when no list is visible at all.
    static func showsEmptyState(_ sections: [Section]) -> Bool {
        sections.allSatisfy { $0.isSettled && !$0.isShown }
    }

    /// The Add button's label.
    static func addTitle(_ action: ChoresConfig.AddAction) -> String {
        if case .groceryItem = action { return "Add Groceries" }
        return "Add Task"
    }
}

