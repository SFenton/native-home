import HassCore
import HassDesign
import SwiftUI

/// An inventory page: All Food, Pantry, Fridge, Freezer, Spice Rack or Cabinet
/// (web `EverShelfInventoryPanel`; spec `.agents/pages/inventory/spec.md`).
///
/// Rows come from `evershelf.list_inventory`, on one dense module under the large title and a "41 Items • 3 Expiring
/// Soon" line (direction G mockup n6-inventory). Search, Sort, Filter and Scan Item form the page's bottom toolbar.
/// Rows open the item editor: as a sheet, or in the trailing half where the window may split (iPad landscape,
/// unfolded iPhone Duo landscape).
struct InventoryScreen {
    var models: InventoryModels
    /// A sheet or editor to open once rows load (debug gallery and journeys).
    var launch: InventoryLaunch?

    @Environment(\.horizontalSizeClass) private var sizeClass

    /// The widest the rows run (HIG Layout: readable content width). On an iPad in portrait the list is the whole window
    /// and its rows put the name and the cart a thousand points apart; the margins center a 720 pt measure instead.
    static let readableWidth: CGFloat = 720

    /// The list's side margin for a column `width` wide: the page margin while the column is narrower than the readable
    /// measure, else whatever centres the measure. (`contentMargins` replaces the list's own inset, so a narrow column must
    /// keep the page margin or its modules run edge to edge.)
    static func sideMargin(forWidth width: CGFloat) -> CGFloat {
        max(HassTokens.Spacing.l, (width - readableWidth) / 2)
    }











}

extension InventoryEditorModel: @MainActor Identifiable {
    public var id: String { itemId }
}
