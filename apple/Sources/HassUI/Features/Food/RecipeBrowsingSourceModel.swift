import HassCore

/// A retained, injected recipe source for a composition host. It owns no connection or house configuration.
@MainActor
final class RecipeBrowsingSource {
    enum SelectionError: Error, Equatable {
        case commandInFlight
    }

    private let models: FoodModels
    private(set) var selected: RecipeDetailModel?

    init(service: any RecipeServing) {
        models = FoodModels(service: service)
    }

    /// Normal production shares the session's existing recipe models.
    init(models: FoodModels) { self.models = models }

    var collection: RecipeCollectionModel { models.collection }
    var suggestions: SuggestedRecipesModel { models.suggestions }
    var hasPendingIntent: Bool { selected?.grocery == .adding }

    /// Reopening the same recipe retains its tab, draft feedback, and pending command.
    @discardableResult
    func select(_ recipe: RecipeCard) throws -> RecipeDetailModel {
        if let selected, selected.recipe.id == recipe.id { return selected }
        try validateRemoval()
        let detail = models.detailModel(for: recipe)
        selected = detail
        return detail
    }

    /// A host must call this before removing or replacing this source or its selected control.
    func validateRemoval() throws {
        if hasPendingIntent { throw SelectionError.commandInFlight }
    }

    func close() throws {
        try validateRemoval()
        selected = nil
    }
}
