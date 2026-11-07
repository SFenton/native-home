import HassCore
import HassDesign
import SwiftUI

// MARK: - Grid

/// The recipe card grid with infinite loading (web `RecipeGrid`): 2+ columns (1+ at accessibility sizes).
struct RecipeGrid {
    let collection: RecipeCollectionModel
    var selectedId: Int?
    var onOpen: (RecipeCard) -> Void

    /// Columns for a width: 160 pt cards, at least two (web). At accessibility text sizes cards are twice
    /// as wide and a phone shows one column, so titles wrap whole words instead of clipping.
    static func columnCount(width: CGFloat, accessibilitySize: Bool) -> Int {
        let metrics = DynamicGridMetrics(width: max(width, 1), minCellWidth: accessibilitySize ? 320 : 160, maxColumns: 8, spacing: HassTokens.Spacing.m)
        return accessibilitySize ? metrics.columns : max(2, metrics.columns)
    }

    /// The line under the large title that names the order: "Sorted by Ingredients Available".
    static func sortSummary(_ sort: RecipeSort) -> String {
        sort == .alphabetical ? "Sorted Alphabetically" : "Sorted by \(sort.title)"
    }


}
