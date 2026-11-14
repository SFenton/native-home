import Foundation
import HassCore

/// A ``RecipeServing`` whose every answer is a closure the test sets, recording what the Food models asked for.
@MainActor
final class FakeRecipeService: RecipeServing {
    struct BrowseCall: Equatable {
        var criteria: RecipeBrowseCriteria
        var cursor: String?
    }

    struct GroceryCall: Equatable {
        var recipeId: Int
        var keys: [String]
        var idempotencyKey: String
    }

    var recommendationsHandler: (Int) async throws -> [RecipeCard] = { _ in [] }
    var browseHandler: (RecipeBrowseCriteria, String?) async throws -> RecipeBrowsePage = { _, _ in RecipeBrowsePage(items: []) }
    var hydrateHandler: (RecipeBrowseCriteria, String?) async throws -> RecipeHydration = { _, _ in RecipeHydration(searchId: "") }
    var detailHandler: (Int) async throws -> RecipeDetail = { RecipeDetail(id: $0, title: "Recipe") }
    var groceryHandler: (GroceryCall) async throws -> RecipeGroceryResult = { _ in RecipeGroceryResult(success: true) }

    private(set) var recommendationLimits: [Int] = []
    private(set) var browseCalls: [BrowseCall] = []
    private(set) var hydrateCalls: [String?] = []
    private(set) var detailIds: [Int] = []
    private(set) var groceryCalls: [GroceryCall] = []

    func recommendations(limit: Int) async throws -> [RecipeCard] {
        recommendationLimits.append(limit)
        return try await recommendationsHandler(limit)
    }

    func browse(_ criteria: RecipeBrowseCriteria, cursor: String?) async throws -> RecipeBrowsePage {
        browseCalls.append(BrowseCall(criteria: criteria, cursor: cursor))
        return try await browseHandler(criteria, cursor)
    }

    func hydrate(_ criteria: RecipeBrowseCriteria, searchId: String?) async throws -> RecipeHydration {
        hydrateCalls.append(searchId)
        return try await hydrateHandler(criteria, searchId)
    }

    func detail(recipeId: Int) async throws -> RecipeDetail {
        detailIds.append(recipeId)
        return try await detailHandler(recipeId)
    }

    func addToGroceries(recipeId: Int, ingredients: [RecipeDetail.Ingredient], idempotencyKey: String) async throws -> RecipeGroceryResult {
        let call = GroceryCall(recipeId: recipeId, keys: ingredients.map(\.key), idempotencyKey: idempotencyKey)
        groceryCalls.append(call)
        return try await groceryHandler(call)
    }
}

/// A suspension point a test opens to hold a service call in flight, then releases.
@MainActor
final class RecipeGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var waiter: CheckedContinuation<Void, Never>?
    private(set) var isHeld = false

    /// Suspends the caller until ``release()``.
    func hold() async {
        isHeld = true
        waiter?.resume()
        waiter = nil
        await withCheckedContinuation { continuation = $0 }
    }

    /// Waits until a caller is suspended in ``hold()``.
    func waitUntilHeld() async {
        if isHeld { return }
        await withCheckedContinuation { waiter = $0 }
    }

    /// Lets the held caller continue.
    func release() {
        isHeld = false
        continuation?.resume()
        continuation = nil
    }
}

/// An error whose description a model may surface.
struct RecipeTestError: LocalizedError {
    var errorDescription: String?
}

/// Sample cards: `cards(1...3)` are recipes 1, 2 and 3.
func recipeCards(_ ids: ClosedRange<Int>, coverage: Double = 50, expiry: Int? = nil) -> [RecipeCard] {
    ids.map { RecipeCard(id: $0, title: "Recipe \($0)", coverage: coverage, soonestExpiryDays: expiry) }
}
