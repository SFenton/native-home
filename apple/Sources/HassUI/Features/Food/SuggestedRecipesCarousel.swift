import HassCore
import HassDesign
import SwiftUI

/// The hub's Suggested Recipes: five swipeable pages of compact recipe cards (web `SuggestedRecipeCarousel` +
/// `CardCarousel`). Columns follow the width like the web (min 2, cards up to 220 pt, max 10); three rows
/// on narrow windows and two on wide ones. Empty slots keep their place while loading.
///
/// Direction G (mockup n6 Food & Recipes): the section's 20 Bold header has no page count (owner, 2026-10-30),
/// and page dots sit under the cards.
struct SuggestedRecipesCarousel {
    /// The section header.
    var title = "Suggested Recipes"
    let model: SuggestedRecipesModel
    /// Clip pages to the carousel's own width. Set it when the carousel shares a row with other content (the
    /// hub's split columns): unclipped, the next page drew under the neighboring column.
    var clipsPages = false
    var onOpen: (RecipeCard) -> Void

    /// Web `RECOMMENDATION_PAGE_COUNT`.
    static let pageCount = 5
    static let spacing: CGFloat = 10

    /// Columns and rows for a width (web `recommendationLayout`). At accessibility text sizes cards are
    /// twice as wide (one column on iPhone) and pages hold two rows, so titles wrap instead of truncating.
    static func layout(width: CGFloat, accessibilitySize: Bool = false) -> (columns: Int, rows: Int) {
        if accessibilitySize {
            return (min(10, max(1, Int(((width + spacing) / (440 + spacing)).rounded(.down)))), 2)
        }
        let columns = max(2, Int(((width + spacing) / (220 + spacing)).rounded(.up)))
        return (min(10, columns), width >= 900 ? 2 : 3)
    }







}
