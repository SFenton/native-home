import Foundation
@testable import HassCore
import Testing

/// Parses a JSON literal into a ``JSONValue``.
func json(_ text: String) -> JSONValue {
    JSONValue(any: try! JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed]))
}

/// Ports of the web's `recipeTypes.test.ts` cases the native app relies on.
struct RecipeParsingTests {
    // MARK: - Cards and pages

    @Test func cardNormalizesKeysCoverageAndIngredientCounts() throws {
        let card = try #require(RecipeParsing.card(json("""
        {"recipe_id": "12", "name": "  Soup  ", "thumbnail_url": "https://img.example/t.jpg", "image_url": "ftp://bad",
         "coverage": 0.5, "matched_required": 9, "required_total": 6, "soonest_expiry_days": "2.4", "cookable": "yes"}
        """)))
        #expect(card.id == 12)
        #expect(card.title == "Soup")
        #expect(card.dedupeKey == "recipe:12")
        #expect(card.coverage == 50)
        #expect(card.matchedRequired == 6, "matched is capped at the required total")
        #expect(card.soonestExpiryDays == 2)
        #expect(card.cookable)
        #expect(card.thumbnailURL?.absoluteString == "https://img.example/t.jpg")
        #expect(card.imageURL == nil, "only http(s) images")
        #expect(card.cardImageURL == card.thumbnailURL)
        #expect(card.coverageText == "6 of 6 Ingredients")
        #expect(card.source == "Unknown source")
    }

    @Test func cardRejectsMissingIdOrTitle() {
        #expect(RecipeParsing.card(json(#"{"id": 0, "title": "X"}"#)) == nil)
        #expect(RecipeParsing.card(json(#"{"id": 3, "title": "  "}"#)) == nil)
        #expect(RecipeParsing.card(json(#"{"title": "X"}"#)) == nil)
        #expect(RecipeParsing.card(json(#""text""#)) == nil)
        #expect(RecipeParsing.card(json(#"{"id": 2, "title": "X", "coverage": 140}"#))?.coverage == 100)
    }

    @Test func browsePageReadsTheResponseEnvelope() {
        let page = RecipeParsing.browsePage(json("""
        {"response": {"items": [{"id": 1, "title": "A"}, {"id": 2}, {"id": 3, "title": "C"}], "next_cursor": "abc", "total": 90}}
        """))
        #expect(page.items.map(\.id) == [1, 3])
        #expect(page.nextCursor == "abc")
        #expect(page.hasMore, "a cursor implies more when has_more is absent")
        #expect(page.total == 90)

        let last = RecipeParsing.browsePage(json(#"{"recipes": [], "has_more": false, "nextCursor": "x"}"#))
        #expect(!last.hasMore)
        #expect(last.total == 0)
    }

    @Test func recommendationsAndHydration() {
        #expect(RecipeParsing.recommendations(json(#"{"service_response": {"items": [{"id": 4, "title": "D"}]}}"#)).map(\.id) == [4])
        let poll = RecipeParsing.hydration(json(#"{"search_id": "s1", "status": "running", "next_poll_ms": 1500.4, "new_items": [{"id": 9, "title": "I"}]}"#))
        #expect(poll.searchId == "s1")
        #expect(!poll.isComplete)
        #expect(poll.nextPollMilliseconds == 1500)
        #expect(poll.newItems.map(\.id) == [9])
        #expect(RecipeParsing.hydration(json(#"{"search_id": "s1", "status": "Done"}"#)).isComplete)
        #expect(RecipeParsing.hydration(json(#"{"search_id": "s1", "remote_exhausted": true}"#)).isComplete)
        #expect(RecipeParsing.hydration(json(#"{"status": "running"}"#)).isComplete, "no search id means nothing to poll")
        #expect(RecipeParsing.hydration(json(#"{"search_id": "s", "status": "failed"}"#)).isFailed)
    }

    // MARK: - Detail

    static let detailJSON = """
    {"response": {"success": true, "detail": {
      "schema_version": "recipe_detail_v1", "id": 7, "title": "Roast Chicken",
      "source": {"connector": "spoonacular", "label": "Spoonacular", "attribution": "", "canonical_url": "https://example.com/r/7", "locale": "en-US"},
      "images": {"primary": "https://img.example/7.jpg", "thumbnail": "javascript:alert(1)"},
      "general": {"yield": {"quantity": 4, "unit": "servings"}, "prep_time_seconds": 900, "cook_time_seconds": "2700",
                  "difficulty": "Easy", "devices": ["Oven", "oven", ""], "optional_devices": ["Oven", "Thermometer"], "equipment": ["Dish"]},
      "ingredients": [
        {"key": "ri:0:0123456789abcdef", "position": 0, "name": "chicken", "display_name": "Chicken",
         "amount": {"quantity": 1, "unit": "whole"}, "inventory": {"state": "in_stock", "relation": "exact", "matched_product": {"id": 3, "name": "Whole Chicken"},
         "quantity_state": "known", "quantity_sufficiency": "sufficient"}},
        {"key": "ri:1:0123456789abcde0", "position": 1, "name": "lemon", "inventory": {"state": "missing"},
         "user_override": {"availability": "have", "selected_product": {"id": 5, "name": "Lemon"}},
         "closest_match": {"label": "Citrus", "mapping_source": "taxonomy_alias"}, "source_optional": "true"},
        {"key": "bad-key", "position": 2, "name": "dropped"},
        {"key": "ri:3:0123456789abcde1", "position": 1, "name": "duplicate position"}
      ],
      "ingredient_groups": [{"key": "main", "index": 0, "label": "Main", "ingredient_keys": ["ri:0:0123456789abcdef", "ri:1:0123456789abcde0"]}],
      "grocery": {"state_counts": {"missing": 1, "uncertain": 0}},
      "instructions": {"steps": ["Heat oven.", {"text": "Roast."}]},
      "freshness": {"updated_at": "2026-10-01T12:00:00Z", "is_stale": "false"},
      "capabilities": {"general": "full", "ingredients": "checklist", "instructions": "local", "quantities": "known", "grocery_add": true}
    }}}
    """

    @Test func detailNormalizesEverySection() throws {
        let detail = try RecipeParsing.detailResult(json(Self.detailJSON)).get()
        #expect(detail.id == 7)
        #expect(detail.title == "Roast Chicken")
        #expect(detail.source.displayName == "Spoonacular")
        #expect(detail.primaryImageURL?.absoluteString == "https://img.example/7.jpg")
        #expect(detail.thumbnailURL == nil)
        #expect(detail.general.cookTimeSeconds == 2700)
        #expect(detail.general.devices == ["Oven"], "case-insensitive de-dupe, empties dropped")
        #expect(detail.general.optionalDevices == ["Thermometer"], "optional devices drop required ones")
        #expect(detail.ingredients.map(\.position) == [0, 1])
        #expect(detail.ingredientsTruncated, "rows were dropped")
        #expect(detail.ingredients[0].matchedProductName == "Whole Chicken")
        #expect(detail.ingredients[1].overrideAvailability == .have)
        #expect(detail.ingredients[1].overrideProductName == "Lemon")
        #expect(detail.ingredients[1].closestMatchLabel == "Citrus")
        #expect(detail.ingredients[1].optional == true)
        #expect(detail.ingredients[1].displayName == "lemon")
        #expect(detail.ingredientGroups.map(\.label) == ["Main"])
        #expect(detail.grocery.confirmedMissingCount == 1)
        #expect(detail.instructions.available)
        #expect(detail.instructions.groups.first?.steps.map(\.text) == ["Heat oven.", "Roast."])
        #expect(detail.instructions.groups.first?.steps.map(\.number) == [1, 2])
        #expect(detail.freshness.isStale == false)
        #expect(detail.capabilities.groceryAdd)
    }

    @Test func cookidooKeepsInstructionsExternal() throws {
        let detail = try #require(RecipeParsing.detail(json("""
        {"schema_version": "recipe_detail_v1", "id": 2, "title": "T",
         "source": {"connector": "Cookidoo", "canonical_url": "https://cookidoo.example/r/2"},
         "instructions": {"steps": ["secret"], "truncated": true},
         "capabilities": {"instructions": "local"}}
        """)))
        #expect(detail.capabilities.instructions == .externalLink)
        #expect(detail.instructions.groups.isEmpty)
        #expect(!detail.instructions.available)
        #expect(detail.instructions.fallbackURL?.absoluteString == "https://cookidoo.example/r/2")
        #expect(!detail.instructions.truncated)
    }

    @Test func detailRejectsOtherSchemasAndReportsFailures() {
        #expect(RecipeParsing.detail(json(#"{"schema_version": "v2", "id": 1, "title": "T"}"#)) == nil)
        if case let .failure(failure) = RecipeParsing.detailResult(json(#"{"success": false, "error_kind": "unsupported"}"#)) {
            #expect(failure.unsupported)
        } else { Issue.record("expected unsupported") }
        if case let .failure(failure) = RecipeParsing.detailResult(json(#"{"success": false, "error": "unsupported_capability", "message": "Old"}"#)) {
            #expect(failure.unsupported)
            #expect(failure.message == "Old")
        } else { Issue.record("expected unsupported") }
        if case let .failure(failure) = RecipeParsing.detailResult(json(#"{"detail": {}}"#)) {
            #expect(!failure.unsupported)
            #expect(failure.message == "EverShelf returned an invalid recipe detail response.")
        } else { Issue.record("expected invalid") }
        if case .success = RecipeParsing.detailResult(json(#"[]"#)) { Issue.record("arrays are invalid") }
    }

    @Test func ingredientGroupsDropWhenInconsistent() {
        let ingredients = RecipeParsing.ingredients(json("""
        [{"key": "ri:0:0123456789abcdef", "position": 0, "name": "a"}, {"key": "ri:1:0123456789abcde0", "position": 1, "name": "b"}]
        """)).ingredients
        // Out of order references.
        #expect(RecipeParsing.ingredientGroups(json("""
        [{"key": "g", "index": 0, "ingredient_keys": ["ri:1:0123456789abcde0", "ri:0:0123456789abcdef"]}]
        """), ingredients: ingredients).isEmpty)
        // Wrong index.
        #expect(RecipeParsing.ingredientGroups(json(#"[{"key": "g", "index": 1, "ingredient_keys": ["ri:0:0123456789abcdef"]}]"#), ingredients: ingredients).isEmpty)
        // Positions that disagree.
        #expect(RecipeParsing.ingredientGroups(json(#"[{"key": "g", "index": 0, "ingredient_keys": ["ri:0:0123456789abcdef"], "positions": [5]}]"#), ingredients: ingredients).isEmpty)
        // Valid, with positions and a title fallback.
        let groups = RecipeParsing.ingredientGroups(json("""
        [{"key": "g1", "index": 0, "title": "First", "ingredient_keys": ["ri:0:0123456789abcdef"], "positions": [0]},
         {"key": "g2", "index": 1, "ingredient_keys": ["ri:1:0123456789abcde0"]}]
        """), ingredients: ingredients)
        #expect(groups.map(\.label) == ["First", nil])
        #expect(RecipeParsing.ingredients(json(#""nope""#)).unsafe)
        #expect(!RecipeParsing.ingredients(nil).unsafe)
    }

    @Test func instructionGroupsByStepsOrPositions() {
        let flat = ["One", "Two", "Three"]
        let byPosition = RecipeParsing.stepGroups(json("""
        [{"key": "a", "index": 0, "step_positions": [0, 1]}, {"key": "b", "index": 1, "label": "Finish", "step_positions": [2]}]
        """), flatSteps: flat)
        #expect(!byPosition.unsafe)
        #expect(byPosition.groups.map { $0.steps.map(\.number) } == [[1, 2], [3]])
        #expect(byPosition.groups[1].label == "Finish")
        #expect(RecipeParsing.stepGroups(json(#"[{"key": "a", "index": 0, "step_positions": [0]}]"#), flatSteps: flat).unsafe, "positions must cover every step")

        let explicit = RecipeParsing.stepGroups(json("""
        [{"key": "a", "index": 0, "steps": [{"key": "s1", "index": 0, "number": 4, "text": "Go"}, {"key": "s2", "index": 1, "text": "Stop"}]}]
        """), flatSteps: [])
        #expect(explicit.groups.first?.steps.map(\.number) == [4, 2])
        #expect(RecipeParsing.stepGroups(json(#"[{"key": "a", "index": 0, "steps": [{"key": "s1", "index": 3, "text": "x"}]}]"#), flatSteps: []).unsafe)
        #expect(RecipeParsing.stepGroups(json(#""x""#), flatSteps: []).unsafe)
        #expect(!RecipeParsing.stepGroups(json("[]"), flatSteps: []).unsafe)

        let steps = RecipeParsing.steps(json(#"["ok", "", {"text": "fine"}, 5]"#))
        #expect(steps.steps == ["ok", "fine"])
        #expect(steps.unsafe)
    }

    // MARK: - Grocery

    @Test func groceryResultReadsNestedSummaries() throws {
        let result = try RecipeParsing.groceryResult(json("""
        {"response": {"success": true, "summary": {"backend": {"added": 2, "already_listed": 1}, "ha_mirror": {"added": 2, "already_present": 1}},
                      "ha_mirror": {"message": "ok"}}}
        """)).get()
        #expect(result.backend.added == 2)
        #expect(result.backend.alreadyListed == 1)
        #expect(result.mirror?.added == 2)
        #expect(result.mirror?.alreadyPresent == 1)
        #expect(result.mirrorMessage == "ok")

        let partial = try RecipeParsing.groceryResult(json(#"{"success": false, "partial_failure": true, "summary": {"failed": 1}}"#)).get()
        #expect(partial.backend.failed == 1)
        #expect(partial.mirror == nil)
        if case .success = RecipeParsing.groceryResult(json(#"{"success": false, "error": "boom"}"#)) { Issue.record("expected failure") }
        if case .success = RecipeParsing.groceryResult(json(#"5"#)) { Issue.record("expected invalid") }
    }

    // MARK: - Values

    @Test func looseValues() {
        #expect(json(#""on""#).flag == true)
        #expect(json(#""0""#).flag == false)
        #expect(json(#""maybe""#).flag == nil)
        #expect(json("2").flag == true)
        #expect(json(#"" 3.5 ""#).finiteNumber == 3.5)
        #expect(json("[]").finiteNumber == nil)
        #expect(json("4.2").integer(minimum: 0) == nil)
        #expect(json("-1").integer(minimum: 0) == nil)
        #expect(json(#"{"a": null, "b": 1}"#).first("a", "b") == .number(1))
        #expect(json(#"{"a": null}"#).firstPresent("a") == .null)
        #expect(RecipeParsing.httpURL("https://example.com/x") != nil)
        #expect(RecipeParsing.httpURL("mailto:x@example.com") == nil)
        #expect(RecipeParsing.coveragePercent(0.25) == 25)
        #expect(RecipeParsing.coveragePercent(-3) == 0)
    }

    // MARK: - Edge cases

    @Test func minimalDetailFallsBackToEmptySections() throws {
        let detail = try #require(RecipeParsing.detail(json(#"{"schema_version": "recipe_detail_v1", "id": 4, "title": "Toast"}"#)))
        #expect(detail.source.connector == "")
        #expect(detail.ingredients.isEmpty)
        #expect(detail.capabilities.instructions == .none)
        #expect(detail.grocery.confirmedMissingCount == 0)
    }

    @Test func malformedStepsAndIngredientsAreUnsafe() {
        #expect(RecipeParsing.steps(json(#"{"text": "x"}"#)).unsafe, "a non-list is unsafe")
        let long = RecipeParsing.steps(.array([.string(String(repeating: "a", count: 2100))]))
        #expect(long.unsafe)
        #expect(long.steps.first?.count == 2000)
        #expect(RecipeParsing.steps(json("[{\"text\": \"  \"}]")).unsafe)
        #expect(RecipeParsing.ingredient(json(#""salt""#)) == nil)
        #expect(RecipeParsing.ingredients(json(#"{"a": 1}"#)).unsafe)
    }
}
