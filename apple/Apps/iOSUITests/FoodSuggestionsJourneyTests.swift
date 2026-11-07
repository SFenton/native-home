import XCTest

/// The Food hub's Suggested Recipes carousel: paging by swipe, and what it shows while the suggestions load, are slow or fail
/// (the tiles stay usable around it). Sources: `SuggestedRecipesCarousel`, `SuggestedRecipesModel`, the hub page that holds it.
@MainActor
final class FoodSuggestionsJourneyTests: FoodJourneyTestCase {
    /// Swiping the suggestions pages them: the dots follow, nothing opens, and swiping back returns to the first page.
    func testSuggestionsPageBySwipe() throws {
        let app = launch("hub")
        let first = element("food.suggestion.1", in: app)
        XCTAssertTrue(first.appears(timeout: 15), "Suggestions did not load")
        let dots = element("food.suggestions.pages", in: app)
        XCTAssertTrue(dots.appears(timeout: 5))
        XCTAssertTrue((dots.value as? String ?? "").hasPrefix("Page 1 of"), "\(String(describing: dots.value))")
        for _ in 0..<3 where !first.isHittable { app.swipeDown() }
        let section = element("food.suggestions", in: app)
        section.swipeLeft()
        XCTAssertTrue(waitFor(dots, "NOT (value BEGINSWITH %@)", "Page 1 of"), "The dots stayed on \(String(describing: dots.value))")
        XCTAssertFalse(element("recipe.tabs", in: app).exists, "Swiping opened a recipe")
        // A fast swipe can carry past a page, so swipe back until the first.
        for _ in 0..<5 where !((dots.value as? String ?? "").hasPrefix("Page 1 of")) {
            section.swipeRight()
            settleScreen()
        }
        XCTAssertTrue(waitFor(dots, "value BEGINSWITH %@", "Page 1 of"), "The dots stayed on \(String(describing: dots.value))")
    }

    /// The hub shows its tiles at once (owner, 2026-10-24, `proposals/loading-states`): only the suggestions carousel
    /// waits, with an arc, and the cards arrive in place.
    func testHubShowsTilesWhileOnlyTheSuggestionsWait() throws {
        // Answers take 5 s, so the wait outlasts the simulator's own launch and can be watched.
        let app = launch("hub", environment: ["FENTON_GALLERY_FOOD_DELAY_MS": "5000"])
        XCTAssertTrue(element("food.allRecipes", in: app).appears(timeout: 10), "The tiles did not show at once")
        XCTAssertTrue(element("food.allFood", in: app).exists, "The tiles wait for the suggestions")
        XCTAssertFalse(element("contentGate.spinner", in: app).exists, "A page-size spinner is back")
        let arc = element("food.suggestions.loading", in: app)
        XCTAssertTrue(arc.exists, "The carousel shows no arc while it waits")
        XCTAssertEqual(arc.label, "Finding suggestions")
        XCTAssertTrue(element("food.suggestion.1", in: app).appears(timeout: 20), "The hub never loaded")
        XCTAssertTrue(arc.disappears(timeout: 3), "The arc stayed once the cards showed")
    }

    /// While the suggestions never arrive the tiles stay usable and the carousel keeps its arc.
    func testHubStaysUsableWhileSuggestionsLoad() {
        let app = launch("hub", mode: "slow")
        XCTAssertTrue(element("food.allRecipes", in: app).appears(timeout: 5))
        settleScreen()
        XCTAssertTrue(element("food.suggestions.loading", in: app).exists)
        XCTAssertTrue(element("food.allRecipes", in: app).isHittable)
        XCTAssertFalse(element("contentGate.spinner", in: app).exists)
    }

    func testHubFailureOffersRetry() {
        let app = launch("hub", mode: "error")
        XCTAssertTrue(element("food.suggestions.error", in: app).appears(timeout: 15))
        XCTAssertTrue(element("food.allRecipes", in: app).exists, "navigation stays available when suggestions fail")
    }
}
