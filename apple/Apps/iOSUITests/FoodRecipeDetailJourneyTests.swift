import XCTest

/// The recipe detail sheet (and the trailing pane where a split is allowed): tabs, the grocery action, the full-height sheet with
/// centred instructions, the Cookidoo link and AX5. Sources: `RecipeDetailView`, `RecipeDetailRows`, `RecipeSectionHeader`,
/// `RecipeDetailModel`.
@MainActor
final class FoodRecipeDetailJourneyTests: FoodJourneyTestCase {
    /// Opens recipe 6 from the Recipes grid (the shared precondition of the tab steps), with its detail call read.
    private func openRecipe6(arguments: [String] = []) -> XCUIApplication {
        let app = launch("recipes", arguments: arguments)
        waitForGrid(app)
        element("recipes.card.6", in: app).tap()
        XCTAssertTrue(element("recipe.tabs", in: app).appears(timeout: 10))
        return app
    }

    /// The General tab, audited. Step 1 of the split tabs-and-groceries journey (`testRecipeDetail*Tab*`).
    func testRecipeDetailGeneralTabAudit() throws {
        let app = openRecipe6()
        expectCall("recipe_detail recipe_id=6", in: app)
        settleScreen()
        let split = element("recipe.pane", in: app).exists
        let frame = app.windows.firstMatch.frame
        if FentonHomeApp.family == .iPad || frame.width <= frame.height {
            // Unfolded Duo landscape may split; iPad splits exactly in landscape; portrait never does.
            XCTAssertEqual(split, frame.width > frame.height, "the pane shows only where a split is allowed")
        }
        keepScreenshot(app, "food-recipe-general-\(device)")
        try audit(app)
    }

    /// The Ingredients tab, audited before scrolling (rows scrolled half under the sheet's edge measure ~1.1:1).
    func testRecipeDetailIngredientsTabAudit() throws {
        let app = openRecipe6()
        element("recipe.tabs", in: app).buttons["Ingredients"].tap()
        XCTAssertTrue(element("recipe.ingredient.0", in: app).appears(timeout: 5))
        XCTAssertEqual(element("recipe.ingredient.1", in: app).value as? String, "Not on hand", "missing lemons read as not on hand")
        XCTAssertTrue((element("recipe.ingredient.0", in: app).value as? String ?? "").hasPrefix("On hand"), "an ingredient in stock reads as on hand first")
        settleScreen()
        keepScreenshot(app, "food-recipe-ingredients-\(device)")
        try audit(app)
    }

    /// The grocery action on the Ingredients tab.
    func testRecipeDetailIngredientsTabAddsToGroceries() throws {
        let app = openRecipe6()
        element("recipe.tabs", in: app).buttons["Ingredients"].tap()
        XCTAssertTrue(element("recipe.ingredient.0", in: app).appears(timeout: 5))
        settleScreen()
        let add = element("recipe.grocery.add", in: app)
        reveal(add, in: app, swiping: element("recipe.scroll", in: app))
        assertTarget(add)
        // Owner, 2026-10-16: "Add to Grocery List", with what it does under it.
        XCTAssertEqual(add.label, "Add to Grocery List")
        XCTAssertTrue(app.staticTexts["Adds the missing ingredients for this recipe to your shopping list."].exists,
                      "The button's description is missing")
        add.tap()
        expectCall("recipe_grocery_add recipe_id=6 selections=1,4", in: app)
        XCTAssertTrue(element("recipe.grocery.added", in: app).appears(timeout: 10))
    }

    /// The Instructions tab, audited.
    func testRecipeDetailInstructionsTabAudit() throws {
        let app = openRecipe6()
        element("recipe.tabs", in: app).buttons["Instructions"].tap()
        XCTAssertTrue(app.staticTexts["Heat the oven to 425°F and zest the lemons."].appears(timeout: 5))
        keepScreenshot(app, "food-recipe-instructions-\(device)")
        try audit(app)
    }

    /// Owner, 2026-10-16: a recipe opens full screen (the other sheets size to their content), and Instructions that fit
    /// sit in the vertical centre of the sheet.
    func testRecipeIsFullScreenAndInstructionsAreCentred() throws {
        let app = launch("recipes")
        waitForGrid(app)
        element("recipes.card.6", in: app).tap()
        let tabs = element("recipe.tabs", in: app)
        XCTAssertTrue(tabs.appears(timeout: 10))
        settleScreen()
        if !element("recipe.pane", in: app).exists {
            // A sheet: its section bar sits at the bottom of the window, which a half-height sheet would not.
            XCTAssertGreaterThan(tabs.frame.maxY, app.windows.firstMatch.frame.height * 0.85, "The recipe sheet is not full height")
        }
        tabs.buttons["Instructions"].tap()
        let first = app.staticTexts["Heat the oven to 425°F and zest the lemons."]
        XCTAssertTrue(first.appears(timeout: 5))
        settleScreen()
        let scroll = element("recipe.scroll", in: app)
        let last = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Roast for 40 minutes'")).firstMatch
        XCTAssertTrue(last.exists)
        let top = first.frame.minY
        let bottom = last.frame.maxY
        let contentMid = (top + bottom) / 2
        // Short instructions sit around the scroll view's middle, not at its top.
        XCTAssertEqual(contentMid, scroll.frame.midY, accuracy: scroll.frame.height * 0.2,
                       "Instructions are not vertically centred (content \(top)-\(bottom), sheet \(scroll.frame))")
        XCTAssertGreaterThan(top - scroll.frame.minY, 60, "Instructions start at the top of the sheet")
        keepScreenshot(app, "food-recipe-instructions-centred-\(device)")
    }

    func testCookidooRecipeLinksOut() throws {
        let app = launch("recipes")
        waitForGrid(app)
        element("recipes.card.1", in: app).tap()
        XCTAssertTrue(element("recipe.tabs", in: app).appears(timeout: 10))
        element("recipe.tabs", in: app).buttons["Instructions"].tap()
        XCTAssertTrue(element("recipe.openCookidoo", in: app).appears(timeout: 5))
        assertTarget(element("recipe.openCookidoo", in: app))
        keepScreenshot(app, "food-recipe-cookidoo-\(device)")
        try audit(app)
    }

    /// The Recipes grid at AX5. Step 1 of the split AX5 journey (`testRecipe*AtAX5`).
    func testRecipeGridAtAX5() throws {
        let app = launch("recipes", arguments: FentonHomeApp.ax5)
        waitForGrid(app)
        keepScreenshot(app, "food-recipes-\(device)-ax5")
        try audit(app)
    }

    /// Recipe 6's General tab at AX5. Step 2: a fresh AX5 launch and the card tapped.
    func testRecipeDetailAtAX5() throws {
        let app = launch("recipes", arguments: FentonHomeApp.ax5)
        waitForGrid(app)
        // At AX5 the card is partly under the floating bar's circles; scroll it clear first (the audit used to leave it so).
        let card = element("recipes.card.6", in: app)
        let window = app.windows.firstMatch.frame
        for _ in 0..<6 where card.frame.midY > window.height * 0.6 {
            element("recipes.grid", in: app).swipeUp(velocity: .slow)  // a collection view in UIKit
        }
        card.tap()
        XCTAssertTrue(element("recipe.tabs", in: app).appears(timeout: 10))
        settleScreen()
        keepScreenshot(app, "food-recipe-general-\(device)-ax5")
        try audit(app)
    }
}
