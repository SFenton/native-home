import HassCore
import HassDesign
import SwiftUI

/// One ingredient: status mark, title with amount, chips, source text and match (web `CheckboxRow` + `IngredientSubtitle`).
struct IngredientRow {
    let detail: RecipeDetail
    let ingredient: RecipeDetail.Ingredient
    var checklist: Bool


    /// The row's mark: a filled check when on hand, a question mark when EverShelf is unsure of the match (and nobody
    /// overrode it), else an empty circle. The spoken value says "Match unsure" for the question mark.
    static func mark(_ ingredient: RecipeDetail.Ingredient, onHand: Bool) -> String {
        if onHand { return "checkmark.circle.fill" }
        if ingredient.overrideAvailability == nil, ingredient.inventoryState == .uncertain { return "questionmark.circle" }
        return "circle"
    }
}

/// "Add to Grocery List", the sheet's one ``PrimaryButtonStyle`` button, with its description (or the reason it is
/// disabled), progress and result (web `RecipeGroceryAction`, which says "Add Missing Ingredients to Groceries"; the
/// owner renamed it on 2026-10-16).
struct GroceryAction {
    let model: RecipeDetailModel

    /// The button's title.
    static let title = "Add to Grocery List"
    /// What the button does, under it while it can run (a disabled button shows its reason instead).
    static let explanation = "Adds the missing ingredients for this recipe to your shopping list."

}
