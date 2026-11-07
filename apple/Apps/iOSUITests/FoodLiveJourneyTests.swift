import XCTest

/// The Food pages against the live EverShelf server (and the signed-in app with fixture recipes). They skip without
/// `TEST_RUNNER_FENTON_HASS_TOKEN`, relaunch the app for each journey (no app reuse: the app signs in) and run in the Live plan only.
@MainActor
final class FoodLiveJourneyTests: FoodJourneyTestCase {
    /// Signs in with the runner's long-lived token and opens a Food page (`FENTON_OPEN_FOOD`). Skips without one.
    private func launchLive(_ route: String, fixtures: Bool = false) throws -> XCUIApplication {
        let environment = ProcessInfo.processInfo.environment
        guard let token = environment["FENTON_HASS_TOKEN"], !token.isEmpty else {
            throw XCTSkip("Set TEST_RUNNER_FENTON_HASS_TOKEN to check the live EverShelf recipe calls")
        }
        let app = FentonHomeApp.makeApp()
        app.launchEnvironment["FENTON_UITEST_RESET"] = "1"
        app.launchEnvironment["FENTON_HASS_TOKEN"] = token
        if let server = environment["FENTON_HASS_SERVER"] { app.launchEnvironment["FENTON_HASS_SERVER"] = server }
        app.launchEnvironment["FENTON_OPEN_FOOD"] = route
        app.launchEnvironment["FENTON_FOOD_DEBUG"] = "1"
        if fixtures { app.launchEnvironment["FENTON_FOOD_FIXTURES"] = "1" }
        app.launch()
        return app
    }

    private func first(_ prefix: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix)).firstMatch
    }

    /// Opens the first live suggestion's recipe sheet (the shared precondition of the recipe steps). Never taps
    /// "Add Missing Ingredients to Groceries".
    private func openLiveRecipe() throws -> XCUIApplication {
        let app = try launchLive("hub")
        let suggestion = first("food.suggestion.", in: app)
        XCTAssertTrue(suggestion.appears(timeout: 45), "No live suggestions")
        settleScreen()
        suggestion.tap()
        XCTAssertTrue(element("recipe.tabs", in: app).appears(timeout: 30), "Recipe detail did not open")
        XCTAssertFalse(element("recipe.error", in: app).exists, "Live recipe detail failed")
        settleScreen()
        return app
    }

    /// Live server, step 1 of the split suggestions-and-detail journey (`testLiveSuggestions*`): suggestions load.
    func testLiveSuggestionsHub() throws {
        let app = try launchLive("hub")
        let suggestion = first("food.suggestion.", in: app)
        XCTAssertTrue(suggestion.appears(timeout: 45), "No live suggestions")
        XCTAssertFalse(element("food.suggestions.error", in: app).exists)
        settleScreen()
        keepScreenshot(app, "food-live-hub-\(device)")
    }

    /// Step 2: a suggestion opens a real detail on its General tab.
    func testLiveSuggestionsRecipeGeneral() throws {
        let app = try openLiveRecipe()
        keepScreenshot(app, "food-live-recipe-general-\(device)")
    }

    /// Step 3: the Ingredients tab lists live ingredients.
    func testLiveSuggestionsIngredientsTab() throws {
        let app = try openLiveRecipe()
        let tabs = element("recipe.tabs", in: app)
        let ingredients = tabs.buttons["Ingredients"]
        diagnose("before Ingredients", app: app, tabs: tabs, segment: ingredients)
        ingredients.tap()
        settleScreen()
        diagnose("after Ingredients", app: app, tabs: tabs, segment: ingredients)
        keepScreenshot(app, "food-live-recipe-ingredients-\(device)")
        XCTAssertTrue(first("recipe.ingredient.", in: app).appears(timeout: 30), "No live ingredients")
    }

    /// Step 4: the Instructions tab.
    func testLiveSuggestionsInstructionsTab() throws {
        let app = try openLiveRecipe()
        element("recipe.tabs", in: app).buttons["Instructions"].tap()
        settleScreen()
        keepScreenshot(app, "food-live-recipe-instructions-\(device)")
    }

    /// Logs the tab picker's state and the hierarchy around a tap (iPad live-sheet investigation, 2026-10-12).
    private func diagnose(_ moment: String, app: XCUIApplication, tabs: XCUIElement, segment: XCUIElement) {
        let count = app.descendants(matching: .any).matching(identifier: "recipe.tabs").count
        let marker = app.staticTexts["recipe.debug"]
        print("FOODDIAG \(moment): pickers=\(count) tabs.frame=\(tabs.frame) segment.exists=\(segment.exists) "
              + "hittable=\(segment.exists && segment.isHittable) frame=\(segment.frame) selected=\(segment.isSelected) "
              + "marker=\(marker.exists ? marker.label : "none")")
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "hierarchy \(moment)"
        tree.lifetime = .keepAlways
        add(tree)
        print("FOODDIAG-TREE \(moment) BEGIN\n\(app.debugDescription)\nFOODDIAG-TREE END")
    }

    /// The signed-in app (Home, tabs, live entity updates) with fixture recipes: the recipe sheet switches tabs.
    /// Separates live recipe data from the signed-in app when the live iPad sheet ignored taps (2026-10-12).
    func testSignedInFixtureSheetSwitchesTabs() throws {
        let app = try launchLive("hub", fixtures: true)
        let suggestion = element("food.suggestion.2", in: app)
        XCTAssertTrue(suggestion.appears(timeout: 45))
        suggestion.tap()
        let tabs = element("recipe.tabs", in: app)
        XCTAssertTrue(tabs.appears(timeout: 15), "Recipe sheet did not open")
        settleScreen()
        let ingredients = tabs.buttons["Ingredients"]
        diagnose("signed-in fixture before", app: app, tabs: tabs, segment: ingredients)
        ingredients.tap()
        settleScreen()
        diagnose("signed-in fixture after", app: app, tabs: tabs, segment: ingredients)
        XCTAssertTrue(element("recipe.ingredient.0", in: app).appears(timeout: 10),
                      "In the signed-in app the fixture recipe sheet did not switch to Ingredients")
    }

    /// Live server: the Recipes grid's first browse page loads.
    func testLiveRecipesGrid() throws {
        let app = try launchLive("recipes")
        let card = first("recipes.card.", in: app)
        XCTAssertTrue(card.appears(timeout: 45), "No live recipes")
        XCTAssertFalse(element("recipes.error", in: app).exists)
        settleScreen()
        keepScreenshot(app, "food-live-recipes-\(device)")
        // A live recipe opened from the grid switches tabs too (compare the hub's sheet).
        card.tap()
        let tabs = element("recipe.tabs", in: app)
        XCTAssertTrue(tabs.appears(timeout: 30), "Recipe detail did not open from the grid")
        settleScreen()
        let ingredients = tabs.buttons["Ingredients"]
        diagnose("grid before Ingredients", app: app, tabs: tabs, segment: ingredients)
        ingredients.tap()
        settleScreen()
        diagnose("grid after Ingredients", app: app, tabs: tabs, segment: ingredients)
        XCTAssertTrue(first("recipe.ingredient.", in: app).appears(timeout: 30), "No live ingredients from the grid")
    }
}
