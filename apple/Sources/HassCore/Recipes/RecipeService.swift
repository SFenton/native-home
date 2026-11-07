import Foundation

// MARK: - Transport

// Responses come through ``HassServiceResponding`` (`Bedroom/ServiceResponses.swift`, shared with the Bedroom
// pages): `HassConnection.callServiceWithResponse` returns the whole result, and ``RecipeParsing/payload(_:)``
// unwraps its `response`.

// MARK: - Recipes

/// The EverShelf recipe features the Food pages use. ``EverShelfRecipeService`` calls Home Assistant;
/// previews and journeys swap in fixtures.
@MainActor
public protocol RecipeServing: AnyObject, Sendable {
    /// Suggested recipes for the Food hub carousel.
    func recommendations(limit: Int) async throws -> [RecipeCard]
    /// One page of the Recipes grid.
    func browse(_ criteria: RecipeBrowseCriteria, cursor: String?) async throws -> RecipeBrowsePage
    /// Starts (`searchId` nil) or polls a remote-catalog import for a search.
    func hydrate(_ criteria: RecipeBrowseCriteria, searchId: String?) async throws -> RecipeHydration
    /// A recipe's detail.
    func detail(recipeId: Int) async throws -> RecipeDetail
    /// Adds the given ingredients to the grocery list (the grocery `todo` list).
    func addToGroceries(recipeId: Int, ingredients: [RecipeDetail.Ingredient], idempotencyKey: String) async throws -> RecipeGroceryResult
}

/// ``RecipeServing`` over the `evershelf.recipe_*` services
/// (`ha-sfenton-react-dash@9ac2a46:src/components/hass/recipes/recipeService.ts`).
@MainActor
public final class EverShelfRecipeService: RecipeServing {
    private let caller: any HassServiceResponding

    /// The integration's service domain.
    public static let domain = "evershelf"

    /// Creates a service over `caller`.
    public init(caller: any HassServiceResponding) { self.caller = caller }

    public func recommendations(limit: Int) async throws -> [RecipeCard] {
        RecipeParsing.recommendations(try await call("recipe_query", RecipeServiceData.recommendations(limit: limit)))
    }

    public func browse(_ criteria: RecipeBrowseCriteria, cursor: String?) async throws -> RecipeBrowsePage {
        RecipeParsing.browsePage(try await call("recipe_query", RecipeServiceData.browse(criteria, cursor: cursor)))
    }

    public func hydrate(_ criteria: RecipeBrowseCriteria, searchId: String?) async throws -> RecipeHydration {
        let data = searchId.map { ["search_id": $0] as [String: any Sendable] } ?? RecipeServiceData.hydrationStart(criteria)
        return RecipeParsing.hydration(try await call("recipe_hydration", data))
    }

    public func detail(recipeId: Int) async throws -> RecipeDetail {
        try RecipeParsing.detailResult(try await call("recipe_detail", RecipeServiceData.detail(recipeId: recipeId))).get()
    }

    public func addToGroceries(recipeId: Int, ingredients: [RecipeDetail.Ingredient], idempotencyKey: String) async throws -> RecipeGroceryResult {
        let data = RecipeServiceData.groceryAdd(recipeId: recipeId, ingredients: ingredients, idempotencyKey: idempotencyKey)
        return try RecipeParsing.groceryResult(try await call("recipe_grocery_add", data)).get()
    }

    private func call(_ service: String, _ data: [String: any Sendable]) async throws -> JSONValue {
        try await caller.callServiceWithResponse(Self.domain, service, data: data)
    }
}

// MARK: - Request bodies

/// Service data for the `evershelf.recipe_*` calls (web `recipeTypes.ts` `recipe*ServiceData`).
public enum RecipeServiceData {
    /// Grid page size (web `limit: 50`).
    public static let pageSize = 50
    /// The grocery list Home Assistant mirrors recipe adds into.
    public static var groceryTodoEntityId: String { ChoresConfig.groceryEntityId }

    /// `recipe_query` browse body (web `recipeBrowseServiceData`).
    public static func browse(_ criteria: RecipeBrowseCriteria, cursor: String?) -> [String: any Sendable] {
        var data: [String: any Sendable] = [
            "kind": "browse",
            "q": criteria.normalizedQuery,
            "sort": criteria.sort.rawValue,
            "availability_weight": percent(criteria.availabilityWeight),
            "expiry_weight": percent(criteria.expiryWeight),
            "minimum_coverage": percent(criteria.minimumCoverage),
            "limit": pageSize,
        ]
        if let days = criteria.expiringWithinDays { data["expiring_within_days"] = days }
        if let cursor, !cursor.isEmpty { data["cursor"] = cursor }
        return data
    }

    /// `recipe_query` recommendations body (web `recipeRecommendationServiceData`).
    public static func recommendations(limit: Int) -> [String: any Sendable] {
        limit > 0 ? ["kind": "recommendations", "limit": limit] : ["kind": "recommendations"]
    }

    /// `recipe_hydration` start body (web `recipeHydrationStartData`).
    public static func hydrationStart(_ criteria: RecipeBrowseCriteria) -> [String: any Sendable] {
        ["query": criteria.normalizedQuery]
    }

    /// `recipe_detail` body.
    public static func detail(recipeId: Int) -> [String: any Sendable] { ["recipe_id": max(1, recipeId)] }

    /// `recipe_grocery_add` body (web `recipeGroceryServiceData`): at most 100 well-formed selections.
    public static func groceryAdd(recipeId: Int, ingredients: [RecipeDetail.Ingredient], idempotencyKey: String) -> [String: any Sendable] {
        let selections: [[String: any Sendable]] = ingredients
            .filter { $0.key.wholeMatch(of: RecipeParsing.ingredientKeyPattern) != nil && $0.position >= 0 }
            .prefix(RecipeGroceryPolicy.maxSelections)
            .map { ["key": $0.key, "position": $0.position] }
        return [
            "recipe_id": max(1, recipeId),
            "selections": selections,
            "idempotency_key": String(idempotencyKey.prefix(128)),
            "todo_entity_id": groceryTodoEntityId,
        ]
    }

    /// A key that makes a retried grocery add safe to replay (web `recipeDetailIdempotencyKey`).
    public static func idempotencyKey(recipeId: Int, now: Date = .now, uuid: UUID = UUID()) -> String {
        let timestamp = String(Int(now.timeIntervalSince1970 * 1000), radix: 36)
        let raw = "native-recipe:\(max(1, recipeId)):\(timestamp):\(uuid.uuidString.lowercased())"
        return String(String(raw.map { $0.isLetter || $0.isNumber || "._:-".contains($0) ? $0 : "-" }).prefix(128))
    }

    /// Clamps to 0...100 and sends whole numbers as `Int` (the web sends JSON numbers).
    static func percent(_ value: Double) -> any Sendable {
        let clamped = min(100, max(0, value.isFinite ? value : 0))
        return clamped == clamped.rounded() ? Int(clamped) : clamped
    }
}
