#if DEBUG
import HassCore
import HassDesign
import Observation
import SwiftUI

// MARK: - Fixture service

/// Answers recipe calls from ``FoodFixtures`` after a short delay, and records each call.
@MainActor
@Observable
final class FixtureRecipeService: RecipeServing {
    enum Mode: String { case normal, error, empty, slow }

    private(set) var lastCall = "None"
    /// Every call, oldest first (tests).
    @ObservationIgnored private(set) var calls: [String] = []
    @ObservationIgnored let mode: Mode
    @ObservationIgnored var delay: Duration

    struct Failure: LocalizedError {
        var errorDescription: String? { "The fixture service is set to fail." }
    }

    init(mode: Mode = .normal, delay: Duration = .milliseconds(300)) {
        self.mode = mode
        self.delay = delay
    }

    func recommendations(limit: Int) async throws -> [RecipeCard] {
        try await answer("recipe_query kind=recommendations limit=\(limit)")
        return mode == .empty ? [] : Array(FoodFixtures.catalog.prefix(limit))
    }

    func browse(_ criteria: RecipeBrowseCriteria, cursor: String?) async throws -> RecipeBrowsePage {
        try await answer("recipe_query kind=browse q=\(criteria.normalizedQuery) sort=\(criteria.sort.rawValue) cursor=\(cursor ?? "-")")
        if mode == .empty { return RecipeBrowsePage(items: []) }
        let query = criteria.normalizedQuery.lowercased()
        var matches = FoodFixtures.catalog.filter { (query.isEmpty || $0.title.lowercased().contains(query)) && criteria.matchesFilters($0) }
        // Ties keep catalog order, so journeys know which cards lead (1, 6, 11, … by availability).
        func ordered<Key: Comparable>(_ key: @escaping (RecipeCard) -> Key) -> (RecipeCard, RecipeCard) -> Bool {
            { key($0) == key($1) ? $0.id < $1.id : key($0) < key($1) }
        }
        switch criteria.sort {
        case .alphabetical: matches.sort(by: ordered(\.title))
        case .expiry: matches.sort(by: ordered { $0.soonestExpiryDays ?? .max })
        case .availability: matches.sort(by: ordered { -$0.coverage })
        }
        let start = Int(cursor ?? "0") ?? 0
        let page = Array(matches.dropFirst(start).prefix(RecipeServiceData.pageSize))
        let next = start + page.count < matches.count ? String(start + page.count) : nil
        return RecipeBrowsePage(items: page, nextCursor: next, hasMore: next != nil, total: matches.count)
    }

    func hydrate(_ criteria: RecipeBrowseCriteria, searchId: String?) async throws -> RecipeHydration {
        try await answer("recipe_hydration query=\(criteria.normalizedQuery)")
        return RecipeHydration(searchId: "", status: "complete", exhausted: true)
    }

    func detail(recipeId: Int) async throws -> RecipeDetail {
        try await answer("recipe_detail recipe_id=\(recipeId)")
        return FoodFixtures.detail(id: recipeId)
    }

    func addToGroceries(recipeId: Int, ingredients: [RecipeDetail.Ingredient], idempotencyKey: String) async throws -> RecipeGroceryResult {
        try await answer("recipe_grocery_add recipe_id=\(recipeId) selections=\(ingredients.map(\.position).map(String.init).joined(separator: ","))")
        return RecipeGroceryResult(
            success: true,
            backend: .init(added: ingredients.count),
            mirror: .init(added: ingredients.count)
        )
    }

    private func answer(_ call: String) async throws {
        lastCall = call
        calls.append(call)
        if mode == .slow { try await Task.sleep(for: .seconds(3600)) }
        try await Task.sleep(for: delay)
        if mode == .error { throw Failure() }
    }
}

// MARK: - Fixtures

/// Fixture recipes, a detail per recipe and EverShelf sensor states.
@MainActor
enum FoodFixtures {
    static let titles = [
        "Lemon Garlic Chicken", "Tomato Basil Soup", "Mushroom Risotto", "Black Bean Tacos", "Spinach Lasagna",
        "Thai Green Curry", "Banana Bread", "Shakshuka", "Chicken Tikka Masala", "Caesar Salad",
        "Beef Stir-Fry", "Pumpkin Pancakes", "Vegetable Paella", "Pesto Pasta", "French Onion Soup",
        "Salmon Teriyaki", "Chili Con Carne", "Greek Lemon Potatoes", "Apple Crumble", "Fried Rice",
    ]

    /// 120 cards: the titles in six numbered rounds so paging has something to load.
    static let catalog: [RecipeCard] = (0..<120).map { index in
        let round = index / titles.count
        let required = 4 + index % 7
        let matched = max(0, required - index % 5)
        return RecipeCard(
            id: index + 1,
            title: round == 0 ? titles[index % titles.count] : "\(titles[index % titles.count]) \(round + 1)",
            source: index % 4 == 0 ? "Cookidoo" : "Spoonacular",
            coverage: Double(matched) / Double(required) * 100,
            matchedRequired: matched,
            requiredTotal: required,
            soonestExpiryDays: index % 3 == 0 ? index % 9 : nil,
            cookable: matched == required
        )
    }

    /// A detail for `id`: every fourth recipe is a Cookidoo recipe with external instructions and no metadata.
    static func detail(id: Int) -> RecipeDetail {
        let card = catalog.first { $0.id == id } ?? catalog[0]
        let cookidoo = id % 4 == 1
        func key(_ position: Int) -> String {
            let hex = String(id * 100 + position, radix: 16)
            return "ri:\(position):" + String(repeating: "0", count: max(0, 16 - hex.count)) + hex
        }
        let ingredients: [RecipeDetail.Ingredient] = [
            .init(key: key(0), position: 0, name: "chicken thighs", displayName: "Chicken thighs", amountQuantity: 6, amountUnit: "pieces",
                  inventoryState: .inStock, inventoryRelation: "exact", matchedProductName: "Chicken Thighs", quantityState: .known, quantitySufficiency: .sufficient),
            .init(key: key(1), position: 1, name: "lemon", displayName: "Lemons", amountQuantity: 2, inventoryState: .missing, quantityState: .known, quantitySufficiency: .insufficient),
            .init(key: key(2), position: 2, name: "garlic", displayName: "Garlic", sourceText: "4 cloves garlic, minced", closestMatchLabel: "Garlic bulb",
                  amountQuantity: 4, amountUnit: "cloves", inventoryState: .uncertain),
            .init(key: key(3), position: 3, name: "olive oil", displayName: "Olive oil", amountQuantity: 2, amountUnit: "tbsp", inventoryState: .staple),
            .init(key: key(4), position: 4, name: "thyme", displayName: "Fresh thyme", optional: true, amountText: "a few sprigs", inventoryState: .missing),
            .init(key: key(5), position: 5, name: "butter", displayName: "Butter", overrideAvailability: .have, amountQuantity: 1, amountQuantityMax: 2, amountUnit: "tbsp",
                  inventoryState: .missing),
        ]
        return RecipeDetail(
            id: card.id,
            title: card.title,
            source: .init(connector: cookidoo ? "cookidoo" : "spoonacular", label: cookidoo ? "Cookidoo" : "Spoonacular",
                          canonicalURL: URL(string: "https://example.com/recipes/\(card.id)"), locale: "en-US"),
            general: cookidoo ? .init() : .init(
                yieldQuantity: 4, yieldUnit: "servings", prepTimeSeconds: 900, cookTimeSeconds: 2700, totalTimeSeconds: 3600,
                difficulty: "Easy", primaryCategory: "Main course", devices: ["Oven"], equipment: ["Baking dish", "Zester"]
            ),
            ingredients: ingredients,
            ingredientGroups: [
                .init(key: "main", label: "Chicken", ingredientKeys: [key(0), key(1), key(2)]),
                .init(key: "finish", label: "To finish", ingredientKeys: [key(3), key(4), key(5)]),
            ],
            grocery: .init(confirmedMissingCount: 3, uncertainCount: 1),
            instructions: cookidoo
                ? .init(fallbackURL: URL(string: "https://cookidoo.example.com/recipes/\(card.id)"))
                : .init(available: true, groups: [
                    .init(key: "prep", label: nil, steps: [
                        .init(key: "s1", number: 1, text: "Heat the oven to 425°F and zest the lemons."),
                        .init(key: "s2", number: 2, text: "Toss the chicken with garlic, olive oil, lemon juice and zest."),
                        .init(key: "s3", number: 3, text: "Roast for 40 minutes, basting halfway, then rest with butter and thyme."),
                    ]),
                ]),
            freshness: .init(updatedAt: "2026-10-01T12:00:00Z", isStale: false),
            capabilities: .init(
                general: cookidoo ? .none : .full, ingredients: .checklist, instructions: cookidoo ? .externalLink : .local,
                quantities: .known, groceryAdd: true
            )
        )
    }

    /// EverShelf sensors for the hub's tiles.
    static func store() -> EntityStore {
        let store = EntityStore()
        let today = Date.now.formatted(.iso8601.year().month().day())
        store.replaceAll([
            EntityState(entityId: FoodConfig.totalItemsEntityId, state: "143"),
            EntityState(entityId: FoodConfig.expiringSoonEntityId, state: "4", attributes: [
                "expiring_list": .array([
                    .object(["location": .string("frigo"), "days_remaining": .number(2)]),
                    .object(["location": .string("frigo"), "days_remaining": .number(5)]),
                    .object(["location": .string("dispensa"), "expiry_date": .string(today)]),
                    .object(["location": .string("freezer"), "days_remaining": .number(6)]),
                ]),
            ]),
            EntityState(entityId: "sensor.demo_sensor_12", state: "61"),
            EntityState(entityId: "sensor.demo_sensor_13", state: "38"),
            EntityState(entityId: "sensor.demo_sensor_14", state: "22"),
            EntityState(entityId: "sensor.demo_kitchen_1", state: "17"),
            EntityState(entityId: "sensor.demo_kitchen_2", state: "5"),
        ])
        return store
    }
}
#endif
