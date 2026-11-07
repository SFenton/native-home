import XCTest

/// The Food hub page: its tiles and spaces, the suggestion sheet's tab switching (from the gallery route, inside a `TabView` and from
/// the debug launch route), the page audit (one test, no longer embedded in two journeys) and the hub at AX5. The suggestions
/// carousel has its own class (`FoodSuggestionsJourneyTests`). Sources: `FoodHubScreen`, `SuggestedRecipesCarousel`.
@MainActor
final class FoodHubJourneyTests: FoodJourneyTestCase {

    /// The hub's content: suggestions load, the All Recipes tile, and the space tiles with their counts. Step 1 of the split
    /// suggestions-and-spaces journey (`testHubSuggestionsAndSpaces*`); the suggestion sheet is `testHubSuggestionsAndSpacesOpensRecipe`.
    func testHubSuggestionsAndSpacesContent() {
        let app = launch("hub")
        XCTAssertTrue(app.navigationBars["Food & Recipes"].appears(timeout: 15))
        XCTAssertTrue(element("food.suggestion.1", in: app).appears(timeout: 10), "Suggestions did not load")
        expectCall("recipe_query kind=recommendations limit=40", in: app)
        let allRecipes = element("food.allRecipes", in: app)
        assertTarget(allRecipes)
        reveal(element("food.space.cabinet", in: app), in: app)
        let fridge = element("food.space.frigo", in: app)
        XCTAssertTrue("\(fridge.label) \(fridge.value as? String ?? "")".contains("38 Items"), "Fridge tile reads '\(fridge.label)'")
        settleScreen()
        keepScreenshot(app, "food-hub-spaces-\(device)")
    }

    /// The first suggestion opens the recipe sheet. Step 2 of the split suggestions-and-spaces journey; entered from the top of a
    /// fresh hub, so it needs no scroll back.
    func testHubSuggestionsAndSpacesOpensRecipe() {
        let app = launch("hub")
        XCTAssertTrue(app.navigationBars["Food & Recipes"].appears(timeout: 15))
        let first = element("food.suggestion.1", in: app)
        XCTAssertTrue(first.appears(timeout: 10), "Suggestions did not load")
        settleScreen()
        first.tap()
        XCTAssertTrue(element("recipe.tabs", in: app).appears(timeout: 10), "Recipe sheet did not open")
        // The sheet hides the page behind it, call line included, so the recipe_detail call is read from its result: the
        // detail loaded (`testRecipeDetailGeneralTabAudit` reads the call line itself on the Recipes page).
        XCTAssertTrue(element("recipe.scroll", in: app).appears(timeout: 10), "The recipe detail did not load")
    }

    /// The hub page, at the default size and against its AX5 comparison page. It was embedded in the suggestions-and-spaces journey
    /// and the coloured-tiles journey (about 190 s together); audited from the top, because scrolled down the carousel sits half
    /// under the translucent bar and measures ~1.1:1. With the AX5 page: the suggestion cards' clipping reads back element-less.
    func testHubPassesAccessibilityAudit() throws {
        let app = launch("hub")
        XCTAssertTrue(app.navigationBars["Food & Recipes"].appears(timeout: 15))
        XCTAssertTrue(element("food.suggestion.1", in: app).appears(timeout: 10), "Suggestions did not load")
        settleScreen()
        keepScreenshot(app, "food-hub-\(device)")
        try audit(app) { self.launch("hub", arguments: FentonHomeApp.ax5) }
    }

    /// The hub's recipe sheet switches tabs (on iPad a live hub sheet ignored taps on the picker, 2026-10-12).
    func testHubSheetSwitchesTabs() {
        let app = launch("hub")
        let suggestion = element("food.suggestion.2", in: app)
        XCTAssertTrue(suggestion.appears(timeout: 15))
        suggestion.tap()
        let tabs = element("recipe.tabs", in: app)
        XCTAssertTrue(tabs.appears(timeout: 10), "Recipe sheet did not open")
        settleScreen()
        let ingredients = tabs.buttons["Ingredients"]
        ingredients.tap()
        XCTAssertTrue(element("recipe.ingredient.0", in: app).appears(timeout: 10), "The hub's recipe sheet did not switch to Ingredients")
        tabs.buttons["Instructions"].tap()
        XCTAssertTrue(app.staticTexts["Heat the oven to 425°F and zest the lemons."].appears(timeout: 10))
    }

    /// The same check with the pages inside a TabView, as in the live app (the live iPad sheet ignored taps).
    func testHubSheetSwitchesTabsInTabView() {
        let configured = FentonHomeApp.makeApp()
        configured.launchEnvironment["FENTON_GALLERY"] = "food"
        configured.launchEnvironment["FENTON_GALLERY_ROUTE"] = "hub"
        configured.launchEnvironment["FENTON_GALLERY_FOOD_TABS"] = "1"
        let app = startApp(configured)
        let suggestion = element("food.suggestion.2", in: app)
        XCTAssertTrue(suggestion.appears(timeout: 15))
        suggestion.tap()
        let tabs = element("recipe.tabs", in: app)
        XCTAssertTrue(tabs.appears(timeout: 10), "Recipe sheet did not open")
        settleScreen()
        tabs.buttons["Ingredients"].tap()
        XCTAssertTrue(element("recipe.ingredient.0", in: app).appears(timeout: 10),
                      "In a TabView the hub's recipe sheet did not switch to Ingredients")
    }

    /// The hub opened by the debug launch route (FENTON_OPEN_FOOD, a navigationDestination(item:)) with fixture
    /// data: the live iPad journeys open Food this way and their recipe sheet ignored taps (2026-10-12).
    func testLaunchRouteHubSheetSwitchesTabs() {
        let app = FentonHomeApp.makeApp()
        app.launchEnvironment["FENTON_GALLERY"] = "food"
        app.launchEnvironment["FENTON_GALLERY_ROUTE"] = "none"
        app.launchEnvironment["FENTON_OPEN_FOOD"] = "hub"
        app.launch()
        let suggestion = element("food.suggestion.2", in: app)
        XCTAssertTrue(suggestion.appears(timeout: 15))
        suggestion.tap()
        let tabs = element("recipe.tabs", in: app)
        XCTAssertTrue(tabs.appears(timeout: 10), "Recipe sheet did not open")
        settleScreen()
        tabs.buttons["Ingredients"].tap()
        XCTAssertTrue(element("recipe.ingredient.0", in: app).appears(timeout: 10),
                      "From the launch route the hub's recipe sheet did not switch to Ingredients")
    }

    /// Hub tiles are controls of their own: All Recipes pushes the grid, a space tile pushes its inventory page. One test per tile
    /// (`testHubTileOpens*`), each from a fresh launch: the back button's place differs per layout (and in Duo landscape).
    func testHubTileOpensAllRecipes() {
        let app = launch("hub")
        let allRecipes = element("food.allRecipes", in: app)
        XCTAssertTrue(allRecipes.appears(timeout: 15))
        allRecipes.tap()
        XCTAssertTrue(app.navigationBars["Recipes"].appears(timeout: 10), "All Recipes did not open the grid")
        waitForGrid(app)
    }

    func testHubTileOpensFridge() {
        let app = launch("hub")
        let fridge = element("food.space.frigo", in: app)
        XCTAssertTrue(fridge.appears(timeout: 15))
        reveal(fridge, in: app)
        fridge.tap()
        XCTAssertTrue(app.navigationBars["Fridge"].appears(timeout: 10), "The Fridge tile did not open its page")
    }

    func testHubTileOpensAllFood() {
        let app = launch("hub")
        let allFood = element("food.allFood", in: app)
        XCTAssertTrue(allFood.appears(timeout: 15))
        reveal(allFood, in: app)
        allFood.tap()
        XCTAssertTrue(app.navigationBars["All Food"].appears(timeout: 10), "All Food did not open its page")
    }

    /// All Recipes, All Food and the five spaces are filled tiles, each a button with its count line as the value.
    func testHubTilesAreColouredTiles() {
        let app = launch("hub")
        XCTAssertTrue(element("food.suggestion.1", in: app).appears(timeout: 15))
        let allRecipes = element("food.allRecipes", in: app)
        XCTAssertEqual(allRecipes.elementType, .button, "All Recipes is a tile button")
        let allFood = element("food.allFood", in: app)
        reveal(allFood, in: app)
        XCTAssertEqual(allFood.elementType, .button, "All Food is a tile button, not a list row")
        XCTAssertTrue("\(allFood.label) \(allFood.value as? String ?? "")".contains("143 Items"), "All Food reads '\(allFood.label)'")
        assertTarget(allFood)
        let titles = ["dispensa": "Pantry", "frigo": "Fridge", "freezer": "Freezer", "spice_rack": "Spice Rack", "cabinet": "Cabinet"]
        reveal(element("food.space.cabinet", in: app), in: app)
        for (key, title) in titles {
            let tile = element("food.space.\(key)", in: app)
            XCTAssertEqual(tile.label, title)
            assertTarget(tile)
        }
        settleScreen()
        keepScreenshot(app, "food-hub-tiles-\(device)")
    }

    func testHubAtAX5() throws {
        let app = launch("hub", arguments: FentonHomeApp.ax5)
        XCTAssertTrue(element("food.suggestion.1", in: app).appears(timeout: 15))
        settleScreen()
        keepScreenshot(app, "food-hub-\(device)-ax5")
        try audit(app)
    }
}
