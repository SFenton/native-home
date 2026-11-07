import Foundation
@testable import HassCore
import Testing

/// Ports of the web's `recipeDetailFormatting.test.ts` cases.
struct RecipeFormattingTests {
    let us = Locale(identifier: "en_US")

    func ingredient(
        displayName: String = "Butter", sourceText: String? = nil, quantity: Double? = nil, max: Double? = nil, unit: String? = nil, text: String? = nil,
        state: RecipeDetail.InventoryState = .missing, relation: String? = nil, override: RecipeDetail.AvailabilityOverride? = nil,
        optional: Bool? = nil, product: String? = nil, quantityState: RecipeDetail.QuantityState = .known,
        sufficiency: RecipeDetail.QuantitySufficiency = .sufficient, closest: String? = nil, key: String = "ri:0:0000000000000000"
    ) -> RecipeDetail.Ingredient {
        .init(key: key, position: 0, name: displayName.lowercased(), displayName: displayName, sourceText: sourceText, optional: optional,
              closestMatchLabel: closest, overrideAvailability: override, amountQuantity: quantity, amountQuantityMax: max, amountUnit: unit,
              amountText: text, inventoryState: state, inventoryRelation: relation, matchedProductName: product, quantityState: quantityState,
              quantitySufficiency: sufficiency)
    }

    @Test func numbersYieldsAndDurations() {
        #expect(RecipeFormatting.number(1.5, locale: us) == "1.5")
        #expect(RecipeFormatting.number(1234.56789, locale: us) == "1,234.568")
        #expect(RecipeFormatting.yield(quantity: 4, unit: "Servings", locale: us) == "Serves 4")
        #expect(RecipeFormatting.yield(quantity: 12, unit: "cookies", locale: us) == "Makes 12 cookies")
        #expect(RecipeFormatting.yield(quantity: 12, unit: " ", locale: us) == nil)
        #expect(RecipeFormatting.yield(quantity: nil, unit: "cups", locale: us) == nil)
        #expect(RecipeFormatting.duration(seconds: nil) == nil)
        #expect(RecipeFormatting.duration(seconds: 45) == "45 sec")
        #expect(RecipeFormatting.duration(seconds: 1200) == "20 min")
        #expect(RecipeFormatting.duration(seconds: 3600) == "1 hr")
        #expect(RecipeFormatting.duration(seconds: 4500) == "1 hr 15 min")
        #expect(RecipeFormatting.spokenDuration(seconds: nil) == nil)
        #expect(RecipeFormatting.spokenDuration(seconds: 4500)?.contains("15") == true)
        #expect(RecipeFormatting.spokenDuration(seconds: 30)?.contains("30") == true)
    }

    @Test func amountsAndTitles() {
        #expect(RecipeFormatting.amount(ingredient(quantity: 2, max: 3, unit: "cups"), locale: us) == "2–3 cups")
        #expect(RecipeFormatting.amount(ingredient(quantity: 2), locale: us) == "2")
        #expect(RecipeFormatting.amount(ingredient(quantity: 2, text: "a pinch"), locale: us) == "a pinch")
        #expect(RecipeFormatting.amount(ingredient(), locale: us) == nil)
        #expect(RecipeFormatting.title(ingredient(quantity: 2, unit: "tbsp"), locale: us) == "Butter · 2 tbsp")
        #expect(RecipeFormatting.title(ingredient(), locale: us) == "Butter")
    }

    @Test func inventoryAndQuantity() {
        #expect(RecipeFormatting.inventoryLabel(ingredient(state: .staple)) == "Staple")
        #expect(RecipeFormatting.inventoryLabel(ingredient(state: .missing)) == "Missing from Inventory")
        #expect(RecipeFormatting.inventoryLabel(ingredient(state: .uncertain)) == "Inventory Match Uncertain")
        #expect(RecipeFormatting.inventoryLabel(ingredient(state: .inStock, relation: "Normalized_Name")) == "Exact Inventory Match")
        #expect(RecipeFormatting.inventoryLabel(ingredient(state: .inStock, relation: "category")) == "In Inventory")
        #expect(RecipeFormatting.isOnHand(ingredient(state: .staple)))
        #expect(!RecipeFormatting.isOnHand(ingredient(state: .uncertain)))
        #expect(RecipeFormatting.isOnHand(ingredient(state: .missing, override: .have)))
        #expect(!RecipeFormatting.isOnHand(ingredient(state: .inStock, override: .missing)))

        let known = RecipeDetail(id: 1, title: "T", capabilities: .init(quantities: .known))
        #expect(RecipeFormatting.quantityNote(known, ingredient()) == nil)
        #expect(RecipeFormatting.quantityNote(known, ingredient(sufficiency: .insufficient)) == "Inventory quantity may be insufficient")
        #expect(RecipeFormatting.quantityNote(known, ingredient(sufficiency: .unknown)) == "Quantity sufficiency is unknown")
        #expect(RecipeFormatting.quantityNote(known, ingredient(quantityState: .displayOnly)) == "Source quantity is display-only")
        #expect(RecipeFormatting.quantityNote(RecipeDetail(id: 1, title: "T"), ingredient()) == "Quantity sufficiency is unknown")
    }

    @Test func sourceDetailDropsTheAmountAndRepeats() {
        #expect(RecipeFormatting.sourceDetail(ingredient(displayName: "Garlic", sourceText: "4 cloves garlic, minced", quantity: 4, unit: "cloves"), locale: us)
            == "garlic, minced")
        #expect(RecipeFormatting.sourceDetail(ingredient(displayName: "Butter", sourceText: "2 tablespoons butter", quantity: 2, unit: "tbsp"), locale: us) == nil)
        #expect(RecipeFormatting.sourceDetail(ingredient(displayName: "Flour", sourceText: "2 cupsful flour", quantity: 2, unit: "cups"), locale: us)
            == "2 cupsful flour", "a prefix that runs into a word is not an amount")
        #expect(RecipeFormatting.sourceDetail(ingredient(sourceText: "  "), locale: us) == nil)
    }

    @Test func chipsAndAccessibility() {
        let detail = RecipeDetail(id: 1, title: "T", capabilities: .init(quantities: .known))
        let row = ingredient(displayName: "Garlic", sourceText: "4 cloves garlic, minced", quantity: 4, unit: "cloves", state: .inStock,
                             override: .missing, optional: true, product: "Garlic Bulb", sufficiency: .insufficient, closest: "Garlic")
        #expect(RecipeFormatting.chips(detail, row) == [
            "In Inventory", "Optional", "Product: Garlic Bulb", "Your override: missing", "Inventory quantity may be insufficient",
        ])
        #expect(RecipeFormatting.accessibilityDetails(detail, row).hasSuffix("Source: garlic, minced. Matched as Garlic"))
        #expect(RecipeFormatting.chips(detail, ingredient(override: .have)) == ["Missing from Inventory", "Your override: have it"])
    }

    @Test func spokenValueCarriesStateAndDetailsNotAHint() {
        let detail = RecipeDetail(id: 1, title: "T", capabilities: .init(quantities: .known))
        let have = ingredient(displayName: "Garlic", sourceText: "4 cloves garlic, minced", quantity: 4, unit: "cloves", state: .inStock)
        #expect(RecipeFormatting.spokenValue(detail, have, checklist: true).hasPrefix("On hand. "))
        #expect(RecipeFormatting.spokenValue(detail, have, checklist: true).contains("Source: garlic, minced"))
        #expect(!RecipeFormatting.spokenValue(detail, have, checklist: false).contains("On hand"))
        #expect(RecipeFormatting.spokenValue(detail, ingredient(), checklist: true).hasPrefix("Not on hand"))
        #expect(RecipeFormatting.spokenValue(detail, ingredient(state: .uncertain), checklist: true).hasPrefix("Match unsure"))
        // The state is not said twice: no "In Inventory" after "On hand", no "Missing from Inventory" or quantity caveat after "Not on hand".
        #expect(RecipeFormatting.spokenValue(detail, ingredient(state: .inStock), checklist: true) == "On hand")
        #expect(RecipeFormatting.spokenValue(detail, ingredient(state: .missing, sufficiency: .insufficient), checklist: true) == "Not on hand")
        #expect(RecipeFormatting.spokenValue(detail, ingredient(state: .missing), checklist: false) == "Missing from Inventory")
        #expect(RecipeFormatting.spokenValue(detail, ingredient(state: .uncertain, override: .have), checklist: true).hasPrefix("On hand"))
    }

    @Test func sectionsGroupAndCollectOrphans() {
        let a = ingredient(displayName: "A", key: "ri:0:000000000000000a")
        let b = ingredient(displayName: "B", key: "ri:1:000000000000000b")
        let c = ingredient(displayName: "C", key: "ri:2:000000000000000c")
        #expect(RecipeFormatting.ingredientSections(RecipeDetail(id: 1, title: "T", ingredients: [a, b])).map(\.heading) == [nil])

        let grouped = RecipeFormatting.ingredientSections(RecipeDetail(id: 1, title: "T", ingredients: [a, b, c], ingredientGroups: [
            .init(key: "g1", label: "Sauce", ingredientKeys: [a.key]),
            .init(key: "g2", label: nil, ingredientKeys: [b.key]),
            .init(key: "empty", label: "Nothing", ingredientKeys: ["ri:9:0000000000000009"]),
        ]))
        #expect(grouped.map(\.heading) == ["Sauce", "Section 2", "Other Ingredients"])
        #expect(grouped.map(\.headingIsGenerated) == [false, true, true])
        #expect(grouped.last?.ingredients.map(\.displayName) == ["C"])

        let lone = RecipeFormatting.ingredientSections(RecipeDetail(id: 1, title: "T", ingredients: [a], ingredientGroups: [
            .init(key: "g", label: nil, ingredientKeys: [a.key]),
        ]))
        #expect(lone.map(\.heading) == [nil])
        #expect(RecipeFormatting.ingredientSections(RecipeDetail(id: 1, title: "T", ingredientGroups: [
            .init(key: "g", label: "X", ingredientKeys: [a.key]),
        ])).map(\.id) == ["flat-ingredients"])
    }

    @Test func factsAndFreshness() {
        let detail = RecipeDetail(
            id: 1, title: "T",
            source: .init(connector: "spoonacular", label: "Spoonacular", locale: "en-US"),
            general: .init(yieldQuantity: 4, yieldUnit: "servings", prepTimeSeconds: 900, cookTimeSeconds: 2700, difficulty: "Easy"),
            freshness: .init(updatedAt: "2026-10-03T12:00:00Z", isStale: false),
            capabilities: .init(general: .full)
        )
        let facts = RecipeFormatting.facts(detail, locale: us)
        #expect(facts.map(\.label) == ["Yield", "Prep Time", "Cook Time", "Difficulty", "Source", "Locale", "Freshness"])
        #expect(facts.first?.value == "Serves 4")
        #expect(facts[1].spokenValue != nil)
        #expect(facts.last?.value.hasPrefix("Current · Oct") == true)

        var bare = detail
        bare.capabilities = .init()
        #expect(RecipeFormatting.facts(bare, locale: us).map(\.label) == ["Source", "Locale", "Freshness"])

        var stale = detail
        stale.freshness = .init(isStale: true)
        #expect(RecipeFormatting.freshness(stale, locale: us) == "Stale")
        stale.freshness = .init(updatedAt: "2026-10-03", isStale: nil)
        #expect(RecipeFormatting.freshness(stale, locale: us)?.hasPrefix("Unknown · Oct") == true)
        stale.freshness = .init()
        #expect(RecipeFormatting.freshness(stale, locale: us) == nil)
        #expect(RecipeFormatting.parseDate("2026-10-03T12:00:00.250Z") != nil)
        #expect(RecipeFormatting.parseDate("nonsense") == nil)
    }
}
