import Foundation
@testable import HassCore
import Testing

/// Ports of the web's `recipeGroceryState.test.ts` and `groceryFeedback` cases.
struct RecipeGroceryPolicyTests {
    static func ingredient(_ position: Int, _ state: RecipeDetail.InventoryState, override: RecipeDetail.AvailabilityOverride? = nil) -> RecipeDetail.Ingredient {
        let hex = String(position, radix: 16)
        return .init(key: "ri:\(position):" + String(repeating: "0", count: 16 - hex.count) + hex, position: position, name: "item \(position)",
                     overrideAvailability: override, inventoryState: state)
    }

    static func detail(
        _ ingredients: [RecipeDetail.Ingredient], missing: Int? = nil, uncertain: Int = 0, blocked: String? = nil, truncated: Bool = false,
        capabilities: RecipeDetail.Capabilities = .init(ingredients: .checklist, groceryAdd: true)
    ) -> RecipeDetail {
        RecipeDetail(
            id: 1, title: "T", ingredients: ingredients, ingredientsTruncated: truncated,
            grocery: .init(confirmedMissingCount: missing ?? ingredients.filter { $0.inventoryState == .missing }.count, uncertainCount: uncertain, blockedReason: blocked),
            capabilities: capabilities
        )
    }

    @Test func eligibilityHonorsOverrides() {
        #expect(RecipeGroceryPolicy.isEligible(Self.ingredient(0, .missing)))
        #expect(!RecipeGroceryPolicy.isEligible(Self.ingredient(0, .missing, override: .have)))
        #expect(RecipeGroceryPolicy.isEligible(Self.ingredient(0, .inStock, override: .missing)))
        #expect(!RecipeGroceryPolicy.isEligible(Self.ingredient(0, .uncertain)))
        let detail = Self.detail([Self.ingredient(0, .missing), Self.ingredient(1, .inStock), Self.ingredient(2, .staple, override: .missing)])
        #expect(RecipeGroceryPolicy.actionableMissing(detail).map(\.position) == [0, 2])
        #expect(RecipeGroceryPolicy.actionableMissing(detail, added: [detail.ingredients[0].key]).map(\.position) == [2])
    }

    @Test func capabilityReasonsInWebOrder() {
        let rows = [Self.ingredient(0, .missing)]
        #expect(RecipeGroceryPolicy.capabilityBlockedReason(Self.detail(rows), loading: true) == "Adding missing ingredients…")
        #expect(RecipeGroceryPolicy.capabilityBlockedReason(Self.detail(rows, truncated: true))?.hasPrefix("Ingredients are truncated") == true)
        #expect(RecipeGroceryPolicy.capabilityBlockedReason(Self.detail(rows, blocked: "ingredients_truncated"))?.hasPrefix("Ingredients are truncated") == true)
        #expect(RecipeGroceryPolicy.capabilityBlockedReason(Self.detail(rows, blocked: "no_ingredients", truncated: true))?.hasPrefix("No ingredient data") == true)
        #expect(RecipeGroceryPolicy.capabilityBlockedReason(Self.detail(rows, capabilities: .init(ingredients: .checklist, groceryAdd: true, groceryAddState: .unavailable)))?
            .contains("temporarily unavailable") == true)
        #expect(RecipeGroceryPolicy.capabilityBlockedReason(Self.detail(rows, capabilities: .init(ingredients: .checklist, groceryAdd: true, groceryAddState: .unsupported)))
            == RecipeGroceryPolicy.unsupportedMessage)
        #expect(RecipeGroceryPolicy.capabilityBlockedReason(Self.detail(rows, capabilities: .init(ingredients: .checklist, groceryAddReason: "unsupported")))
            == RecipeGroceryPolicy.unsupportedMessage)
        #expect(RecipeGroceryPolicy.capabilityBlockedReason(Self.detail(rows, capabilities: .init(groceryAdd: true)))?.hasPrefix("No ingredient data") == true)
        #expect(RecipeGroceryPolicy.capabilityBlockedReason(Self.detail(rows, capabilities: .init(ingredients: .checklist)))
            == "Adding missing ingredients is unavailable for this recipe.")
        #expect(RecipeGroceryPolicy.capabilityBlockedReason(Self.detail(rows)) == nil)
    }

    @Test func disabledReasonsFromCounts() {
        let missing = Self.ingredient(0, .missing)
        #expect(RecipeGroceryPolicy.disabledReason(Self.detail([missing])) == nil)
        #expect(RecipeGroceryPolicy.disabledReason(Self.detail([missing]), loading: true) == "Adding missing ingredients…")
        #expect(RecipeGroceryPolicy.disabledReason(Self.detail([missing]), added: [missing.key])
            == "All missing ingredients have already been added to groceries.")
        #expect(RecipeGroceryPolicy.disabledReason(Self.detail([Self.ingredient(0, .missing, override: .have)]))
            == "All confirmed missing ingredients are marked as available by your overrides.")
        #expect(RecipeGroceryPolicy.disabledReason(Self.detail([Self.ingredient(0, .uncertain)], uncertain: 1))
            == "EverShelf can't yet tell which of these 1 ingredients you're missing.")
        #expect(RecipeGroceryPolicy.disabledReason(Self.detail([Self.ingredient(0, .inStock)])) == "No missing ingredients to add.")
        #expect(RecipeGroceryPolicy.disabledReason(Self.detail([missing], missing: 101)) == "Too many missing ingredients to add in one request.")
        #expect(RecipeGroceryPolicy.disabledReason(Self.detail([Self.ingredient(0, .inStock, override: .missing)])) == nil, "a missing override promotes the row")
    }

    @Test func feedbackSummarizesBothLists() {
        let full = RecipeGroceryPolicy.feedback(.init(success: true, backend: .init(added: 2, alreadyListed: 1), mirror: .init(added: 2, alreadyPresent: 1)))
        #expect(full.success)
        #expect(full.message == "EverShelf: 2 added, 1 already listed. Home Assistant mirror: 2 added, 1 already present.")

        let none = RecipeGroceryPolicy.feedback(.init(success: true))
        #expect(none.success)
        #expect(none.message == "EverShelf: no grocery changes. Home Assistant mirror: not reported.")

        let partial = RecipeGroceryPolicy.feedback(.init(
            success: false, outcomesTruncated: true, backend: .init(nowInStock: 1, unresolved: 1, failed: 2), backendMessage: "Timeout",
            mirror: .init(skipped: 1, failed: 1), mirrorMessage: "Offline"
        ))
        #expect(!partial.success)
        #expect(partial.message == "EverShelf: 1 now in stock, 1 unresolved, 2 failed. EverShelf did not report service success. "
            + "EverShelf outcome details were truncated. EverShelf message: Timeout Home Assistant mirror: 1 skipped, 1 failed. "
            + "Home Assistant mirror did not report service success. Home Assistant mirror message: Offline")

        let vague = RecipeGroceryPolicy.feedback(.init(success: false, mirror: .init()))
        #expect(!vague.success)
        #expect(vague.message.hasSuffix("Home Assistant mirror: no grocery changes. Recipe grocery service did not report complete success."))
    }
}
