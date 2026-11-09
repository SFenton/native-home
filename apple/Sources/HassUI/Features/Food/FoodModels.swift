import Foundation
import HassCore
import Observation

// MARK: - Container

/// State for the Food pages, owned by the section's navigation stack (``FoodNavigation``) so the Recipes
/// results, search and filters survive leaving and re-entering the pages (web `useRecipeControls` is scoped
/// per route and survives navigation) and nothing reloads on reopen.
@MainActor
@Observable
final class FoodModels {
    /// The recipe service; set once the stack knows its connection.
    @ObservationIgnored var service: (any RecipeServing)? {
        didSet {
            collection.service = service
            suggestions.service = service
        }
    }

    let collection = RecipeCollectionModel()
    let suggestions = SuggestedRecipesModel()
    /// Details already loaded, shown at once when a recipe is reopened while a fresh copy loads.
    @ObservationIgnored var detailCache: [Int: RecipeDetail] = [:]

    init(service: (any RecipeServing)? = nil) {
        self.service = service
        collection.service = service
        suggestions.service = service
    }

    /// A detail model for `recipe`.
    func detailModel(for recipe: RecipeCard) -> RecipeDetailModel {
        RecipeDetailModel(recipe: recipe, service: service, cached: detailCache[recipe.id]) { [weak self] detail in
            self?.detailCache[detail.id] = detail
        }
    }
}
