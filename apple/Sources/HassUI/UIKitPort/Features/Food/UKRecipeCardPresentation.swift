import Foundation
import HassCore

/// Recipe-domain values for the shared image-card component.
struct RecipeCardPresentation {
    let title: String
    let subtitle: String?
    let imageURL: URL?
    let fallbackImageURL: URL?
    let placeholderSymbol: String
    let accessibilityHint: String

    init(recipe: RecipeCard, showCoverage: Bool, placeholderSymbol: String, accessibilityHint: String) {
        title = recipe.title
        subtitle = showCoverage ? recipe.coverageText : nil
        imageURL = recipe.cardImageURL
        fallbackImageURL = recipe.imageURL
        self.placeholderSymbol = placeholderSymbol
        self.accessibilityHint = accessibilityHint
    }
}

/// Values consumed by an ingredient row, independent of the recipe model and its provider.
struct RecipeIngredientPresentation {
    let title: String
    let chips: [String]
    let source: String?
    let match: String?
    let mark: String?
    let onHand: Bool
    let spokenValue: String
    let identifier: String

    init(detail: RecipeDetail, ingredient: RecipeDetail.Ingredient, checklist: Bool) {
        onHand = RecipeFormatting.isOnHand(ingredient)
        title = RecipeFormatting.title(ingredient)
        if checklist {
            chips = RecipeFormatting.chips(detail, ingredient)
            mark = IngredientRow.mark(ingredient, onHand: onHand)
        } else {
            chips = [ingredient.optional == true ? "Optional" : nil,
                     RecipeFormatting.quantityNote(detail, ingredient)].compactMap { $0 }
            mark = nil
        }
        source = RecipeFormatting.sourceDetail(ingredient).map { "Source: \($0)" }
        match = ingredient.closestMatchLabel.map { "Matched as \($0)" }
        spokenValue = RecipeFormatting.spokenValue(detail, ingredient, checklist: checklist)
        identifier = "recipe.ingredient.\(ingredient.position)"
    }

    init(title: String, chips: [String], source: String?, match: String?, mark: String?,
         onHand: Bool, spokenValue: String, identifier: String) {
        self.title = title
        self.chips = chips
        self.source = source
        self.match = match
        self.mark = mark
        self.onHand = onHand
        self.spokenValue = spokenValue
        self.identifier = identifier
    }
}
