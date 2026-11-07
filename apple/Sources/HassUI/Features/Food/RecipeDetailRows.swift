import HassCore
import HassDesign
import SwiftUI

// MARK: - Rows of the recipe sheet's inset lists

/// Measurements of the recipe sheet's own rows (ingredients, steps, the source link), matching ``ModuleRow`` so their
/// text starts where ``ModuleList`` insets its hairlines.
enum RecipeRowMetrics {
    /// The glyph column (``ModuleRow``'s).
    static let glyph = ModuleRowMetrics.glyphWidth
    /// Space between the glyph and the text (``ModuleRow``'s).
    static let gap = ModuleRowMetrics.gap
    /// A row's minimum height (direction G, Controls: Lists: 52 pt rows).
    static let minHeight: CGFloat = 52
}
