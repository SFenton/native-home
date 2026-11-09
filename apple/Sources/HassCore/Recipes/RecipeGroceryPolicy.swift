import Foundation

/// When "Add Missing Ingredients to Groceries" is allowed and what it says
/// (`ha-sfenton-react-dash@9ac2a46:src/components/hass/recipes/recipeGroceryState.ts`).
public enum RecipeGroceryPolicy {
    /// The most ingredients one request may add (web `RECIPE_GROCERY_MAX_SELECTIONS`).
    public static let maxSelections = 100

    /// Shown when the installed integration can't add groceries.
    public static let unsupportedMessage = "The installed EverShelf/ha-evershelf version does not support recipe grocery adding yet."

    /// An ingredient is added when it is effectively missing: EverShelf says missing, or the user overrode
    /// it to missing. A "have" override always wins (web `recipeIngredientIsGroceryEligible`).
    public static func isEligible(_ ingredient: RecipeDetail.Ingredient) -> Bool {
        switch ingredient.overrideAvailability {
        case .have: false
        case .missing: true
        case nil: ingredient.inventoryState == .missing
        }
    }

    /// The ingredients the bulk action would add, minus those already added (web `recipeActionableMissingIngredients`).
    public static func actionableMissing(_ detail: RecipeDetail, added: Set<String> = []) -> [RecipeDetail.Ingredient] {
        detail.ingredients.filter { isEligible($0) && !added.contains($0.key) }
    }

    /// Recipe-wide reasons the feature is off (web `recipeGroceryCapabilityBlockedReason`).
    public static func capabilityBlockedReason(_ detail: RecipeDetail, loading: Bool = false) -> String? {
        if loading { return "Adding missing ingredients…" }
        let blocked = detail.grocery.blockedReason
        if blocked == "ingredients_truncated" || (blocked != "no_ingredients" && detail.ingredientsTruncated) {
            return "Ingredients are truncated, so groceries cannot be added safely."
        }
        if blocked == "no_ingredients" { return "No ingredient data is available, so groceries cannot be added." }
        if detail.capabilities.groceryAddState == .unavailable { return "Adding missing ingredients is temporarily unavailable. Try again later." }
        if detail.capabilities.groceryAddState == .unsupported || detail.capabilities.groceryAddReason == "unsupported" {
            return unsupportedMessage
        }
        if detail.capabilities.ingredients == .none { return "No ingredient data is available, so groceries cannot be added." }
        if !detail.capabilities.groceryAdd { return "Adding missing ingredients is unavailable for this recipe." }
        return nil
    }

    /// Why the bulk action is disabled, or nil when it can run (web `recipeGroceryDisabledReason`).
    public static func disabledReason(_ detail: RecipeDetail, loading: Bool = false, added: Set<String> = []) -> String? {
        if let blocked = capabilityBlockedReason(detail, loading: loading) { return blocked }
        let counts = Counts(detail, added: added)
        if counts.actionable > maxSelections { return "Too many missing ingredients to add in one request." }
        if counts.exhaustedByAdds { return "All missing ingredients have already been added to groceries." }
        if detail.grocery.confirmedMissingCount > 0, counts.actionable == 0 {
            return "All confirmed missing ingredients are marked as available by your overrides."
        }
        if counts.actionable == 0, detail.grocery.uncertainCount > 0 {
            return "EverShelf can't yet tell which of these \(detail.grocery.uncertainCount) ingredients you're missing."
        }
        if counts.actionable == 0 { return "No missing ingredients to add." }
        return nil
    }

    /// Counts behind ``disabledReason(_:loading:added:)`` (web `recipeGroceryActionableCounts`).
    struct Counts {
        var actionable: Int
        var exhaustedByAdds: Bool

        init(_ detail: RecipeDetail, added: Set<String>) {
            let confirmed = detail.ingredients.filter { $0.inventoryState == .missing }
            let suppressed = confirmed.filter { $0.overrideAvailability == .have }.count
            let promoted = detail.ingredients.filter { $0.inventoryState != .missing && $0.overrideAvailability == .missing }.count
            let effective = max(0, detail.grocery.confirmedMissingCount - suppressed) + promoted
            let addedCount = detail.ingredients.filter { RecipeGroceryPolicy.isEligible($0) && added.contains($0.key) }.count
            actionable = max(0, effective - addedCount)
            exhaustedByAdds = effective > 0 && actionable == 0 && addedCount > 0 && suppressed == 0
        }
    }

    /// Whether the add fully succeeded, and the sentence summarizing it (web `groceryFeedback`).
    public static func feedback(_ result: RecipeGroceryResult) -> (success: Bool, message: String) {
        let backend = result.backend
        let backendParts = [
            backend.added > 0 ? "\(backend.added) added" : nil,
            backend.alreadyListed > 0 ? "\(backend.alreadyListed) already listed" : nil,
            backend.nowInStock > 0 ? "\(backend.nowInStock) now in stock" : nil,
            backend.unresolved > 0 ? "\(backend.unresolved) unresolved" : nil,
            backend.failed > 0 ? "\(backend.failed) failed" : nil,
        ].compactMap { $0 }
        let backendText = backendParts.isEmpty ? "EverShelf: no grocery changes." : "EverShelf: \(backendParts.joined(separator: ", "))."
        let success = result.success && !result.outcomesTruncated && backend.failed == 0 && backend.unresolved == 0
            && (result.mirror?.failed ?? 0) == 0
        let backendFailure = backend.failed > 0 || backend.unresolved > 0 || result.outcomesTruncated || result.backendMessage != nil
        let mirrorFailure = (result.mirror?.failed ?? 0) > 0 || result.mirrorMessage != nil
        var parts = [backendText]
        if !result.success, backendFailure { parts.append("EverShelf did not report service success.") }
        if result.outcomesTruncated { parts.append("EverShelf outcome details were truncated.") }
        if let message = result.backendMessage { parts.append("EverShelf message: \(message)") }
        if let mirror = result.mirror {
            let mirrorParts = [
                mirror.added > 0 ? "\(mirror.added) added" : nil,
                mirror.alreadyPresent > 0 ? "\(mirror.alreadyPresent) already present" : nil,
                mirror.skipped > 0 ? "\(mirror.skipped) skipped" : nil,
                mirror.failed > 0 ? "\(mirror.failed) failed" : nil,
            ].compactMap { $0 }
            parts.append(mirrorParts.isEmpty ? "Home Assistant mirror: no grocery changes." : "Home Assistant mirror: \(mirrorParts.joined(separator: ", ")).")
            if !result.success, mirrorFailure { parts.append("Home Assistant mirror did not report service success.") }
            if let message = result.mirrorMessage { parts.append("Home Assistant mirror message: \(message)") }
        } else {
            parts.append("Home Assistant mirror: not reported.")
        }
        if !result.success, !backendFailure, !mirrorFailure { parts.append("Recipe grocery service did not report complete success.") }
        return (success, parts.joined(separator: " "))
    }
}
