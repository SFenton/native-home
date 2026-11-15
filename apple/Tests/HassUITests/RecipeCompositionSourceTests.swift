import Foundation
import HassCore
@testable import HassUI
import Testing

@MainActor
private final class RecipeCompositionFixture: RecipeServing {
    let card = RecipeCard(id: 1, title: "Soup")
    private(set) var criteria: [RecipeBrowseCriteria] = []
    private(set) var groceryCalls = 0

    func recommendations(limit: Int) async throws -> [RecipeCard] { [card] }
    func browse(_ criteria: RecipeBrowseCriteria, cursor: String?) async throws -> RecipeBrowsePage {
        self.criteria.append(criteria)
        return RecipeBrowsePage(items: [card])
    }
    func hydrate(_ criteria: RecipeBrowseCriteria, searchId: String?) async throws -> RecipeHydration {
        RecipeHydration(searchId: "")
    }
    func detail(recipeId: Int) async throws -> RecipeDetail {
        RecipeDetail(id: recipeId, title: "Soup",
                     ingredients: [.init(key: "ri:0:0000000000000000", position: 0, name: "Bean", inventoryState: .missing)],
                     grocery: .init(confirmedMissingCount: 1),
                     capabilities: .init(ingredients: .checklist, groceryAdd: true))
    }
    func addToGroceries(recipeId: Int, ingredients: [RecipeDetail.Ingredient], idempotencyKey: String) async throws -> RecipeGroceryResult {
        groceryCalls += 1
        return RecipeGroceryResult(success: true, backend: .init(added: ingredients.count))
    }
}

@MainActor
struct RecipeCompositionSourceTests {
    @Test func browsingUsesTheInjectedProviderAndRetainsControls() async throws {
        let service = RecipeCompositionFixture()
        let source = RecipeBrowsingSource(service: service)
        source.suggestions.appear()
        source.collection.appear()
        await source.suggestions.settle()
        await source.collection.settle()
        #expect(source.suggestions.items == [service.card])
        #expect(source.collection.items == [service.card])

        source.collection.apply(sort: .alphabetical)
        var filters = RecipeFilters.defaults
        filters.minimumCoverage = 50
        source.collection.apply(filters: filters)
        await source.collection.settle()
        #expect(service.criteria.last?.sort == .alphabetical)
        #expect(service.criteria.last?.minimumCoverage == 50)
        #expect(source.collection.filters == filters)

        let detail = try source.select(service.card)
        detail.tab = .instructions
        #expect(try source.select(service.card) === detail)
        #expect(source.selected?.tab == .instructions)
        try source.close()
        #expect(source.selected == nil)
    }

    @Test func aPendingCommandPinsItsRecipeUntilItCompletes() async throws {
        let service = RecipeCompositionFixture()
        let source = RecipeBrowsingSource(service: service)
        let detail = try source.select(service.card)
        detail.load()
        await detail.settle()
        detail.addMissingToGroceries()
        #expect(source.hasPendingIntent)
        #expect(throws: RecipeBrowsingSource.SelectionError.commandInFlight) { try source.close() }
        #expect(throws: RecipeBrowsingSource.SelectionError.commandInFlight) {
            try source.select(RecipeCard(id: 2, title: "Other"))
        }
        #expect(try source.select(service.card) === detail)
        await detail.settle()
        #expect(service.groceryCalls == 1)
        #expect(!source.hasPendingIntent)
        try source.close()
    }

    @Test func ingredientAndCardProjectionsRetainCanonicalValues() {
        let ingredient = RecipeDetail.Ingredient(key: "ri:0:0000000000000000", position: 0, name: "Bean",
            sourceText: "Bean, drained", optional: true, closestMatchLabel: "Beans",
            inventoryState: .uncertain, quantityState: .known, quantitySufficiency: .sufficient)
        let detail = RecipeDetail(id: 1, title: "Soup", ingredients: [ingredient], capabilities: .init(quantities: .known))
        let checklist = RecipeIngredientPresentation(detail: detail, ingredient: ingredient, checklist: true)
        #expect(checklist.mark == "questionmark.circle")
        #expect(checklist.chips == ["Inventory Match Uncertain", "Optional"])
        #expect(checklist.source == "Source: Bean, drained")
        #expect(checklist.match == "Matched as Beans")
        #expect(checklist.spokenValue.hasPrefix("Match unsure"))
        let names = RecipeIngredientPresentation(detail: detail, ingredient: ingredient, checklist: false)
        #expect(names.mark == nil)
        #expect(names.chips == ["Optional"])

        let image = URL(string: "https://example.invalid/full.jpg")!
        let thumbnail = URL(string: "https://example.invalid/thumb.jpg")!
        let card = RecipeCard(id: 1, title: "Soup", imageURL: image, thumbnailURL: thumbnail, matchedRequired: 2, requiredTotal: 3)
        let values = RecipeCardPresentation(recipe: card, showCoverage: true, placeholderSymbol: "photo", accessibilityHint: "Read")
        #expect(values.subtitle == "2 of 3 Ingredients")
        #expect(values.imageURL == thumbnail)
        #expect(values.fallbackImageURL == image)
        #expect(values.placeholderSymbol == "photo")
        #expect(RecipeCardPresentation(recipe: card, showCoverage: false, placeholderSymbol: "photo", accessibilityHint: "Read").subtitle == nil)
    }
}
