import XCTest

/// The Recipes grid page: search, sort and filter applied through their sheets, the page audit, the error and empty pages (one
/// audit test each) and infinite loading. The sort and filter sheets' own audits are `FoodRecipeSheetsJourneyTests`. Sources:
/// `RecipesScreen`, `RecipeGrid`, `RecipeCollectionModel`, `RecipeFilters`.
@MainActor
final class FoodRecipesJourneyTests: FoodJourneyTestCase {
    /// The Sort sheet applies. Step 1 of the split sort-filter-search journey (`testRecipes*Applies`, `testRecipesSearchEmpties`);
    /// it also carries the first page's call line, the grid screenshot and the floating buttons' target sizes.
    func testRecipesSortApplies() throws {
        let app = launch("recipes")
        waitForGrid(app)
        // The first page, whatever has loaded after it: iPad shows enough cards that the next page (cursor=50) is asked for
        // before this reads the line.
        expectCall("recipe_query kind=browse q= sort=availability cursor=", in: app)
        keepScreenshot(app, "food-recipes-\(device)")

        for id in ["fab.sort", "fab.filter", "fab.search"] { assertTarget(element(id, in: app)) }

        element("fab.sort", in: app).tap()
        XCTAssertTrue(app.navigationBars["Sort Recipes"].appears(timeout: 5))
        XCTAssertFalse(app.buttons["filterSheet.apply"].isEnabled, "Apply waits for a change")
        element("recipes.sort.alphabetical", in: app).tap()
        XCTAssertTrue(element("recipes.sort.alphabetical", in: app).isSelected)
        settleScreen()
        keepScreenshot(app, "food-recipes-sort-\(device)")
        // The sheets' audits (with their AX5 comparison pages) are the `testSortSheetPassesAccessibilityAudit*` and
        // `testFilterSheetPassesAccessibilityAudit*` tests. An audit with an AX5 page relaunches the app at AX5 and the gallery
        // hides its Last call line at accessibility sizes, so this journey never audits half way through.
        app.buttons["filterSheet.apply"].tap()
        expectCall("recipe_query kind=browse q= sort=alphabetical", in: app)
        XCTAssertTrue(element("fab.sort", in: app).isSelected, "an applied sort marks the button")
    }

    /// The Filter sheet applies. Its query carries the alphabetical sort the Sort step applies, so the sort is applied first here
    /// as setup (the sort's own assertions live in `testRecipesSortApplies`).
    func testRecipesFilterApplies() throws {
        let app = launch("recipes")
        waitForGrid(app)
        element("fab.sort", in: app).tap()
        XCTAssertTrue(app.buttons["filterSheet.apply"].appears(timeout: 5))
        element("recipes.sort.alphabetical", in: app).tap()
        app.buttons["filterSheet.apply"].tap()
        XCTAssertTrue(element("fab.sort", in: app).wait(for: \.isSelected, toEqual: true, timeout: 5))
        expectCall("recipe_query kind=browse q= sort=alphabetical", in: app)

        element("fab.filter", in: app).tap()
        XCTAssertTrue(app.navigationBars["Filter Recipes"].appears(timeout: 5))
        XCTAssertFalse(element("recipes.filter.horizon", in: app).isEnabled, "the horizon waits for the toggle")
        element("recipes.filter.expiringOnly", in: app).switches.firstMatch.tap()
        let horizon = element("recipes.filter.horizon", in: app)
        XCTAssertTrue(horizon.wait(for: \.isEnabled, toEqual: true, timeout: 5), "the toggle enables the horizon")
        horizon.buttons["30 Days"].tap()
        XCTAssertTrue(app.staticTexts["Use ingredients expiring within the next month."].appears(timeout: 5),
                      "the footer explains the chosen horizon")
        settleScreen()
        keepScreenshot(app, "food-recipes-filter-\(device)")
        app.buttons["filterSheet.apply"].tap()
        expectCall("recipe_query kind=browse q= sort=alphabetical", in: app)
        XCTAssertTrue(element("fab.filter", in: app).wait(for: \.isSelected, toEqual: true, timeout: 5), "applied filters mark the button")
    }

    /// Searching for nothing shows the empty page and closes cleanly.
    func testRecipesSearchEmpties() throws {
        let app = launch("recipes")
        waitForGrid(app)
        element("fab.search", in: app).tap()
        let field = element("fab.search.field", in: app)
        XCTAssertTrue(field.appears(timeout: 5))
        field.typeText("zzz")
        XCTAssertTrue(element("recipes.empty", in: app).appears(timeout: 10))
        expectCall("recipe_hydration query=zzz", in: app)
        element("fab.search.close", in: app).tap()
        XCTAssertFalse(field.exists)
    }

    /// The Recipes page itself, at the default size and against its AX5 comparison page.
    func testRecipesPagePassesAccessibilityAudit() throws {
        let app = launch("recipes")
        waitForGrid(app)
        try audit(app) { self.launch("recipes", arguments: FentonHomeApp.ax5) }
    }

    /// The error page: Retry is a 44 pt target and the audit carries its AX5 comparison page (the floating search pill reads as
    /// element-less "Text clipped" at larger sizes on every Recipes page, and only the same page's growth at AX5, the audit's
    /// evidence, clears it).
    func testRecipesErrorPassesAccessibilityAudit() throws {
        let failing = launch("recipes", mode: "error")
        XCTAssertTrue(element("recipes.error", in: failing).appears(timeout: 15))
        assertTarget(element("recipes.retry", in: failing))
        keepScreenshot(failing, "food-recipes-error-\(device)")
        try audit(failing) {
            let large = self.launch("recipes", mode: "error", arguments: FentonHomeApp.ax5)
            XCTAssertTrue(self.element("recipes.error", in: large).appears(timeout: 15))
            settleScreen()
            return large
        }
    }

    /// The empty page, with its AX5 comparison page (see ``testRecipesErrorPassesAccessibilityAudit``).
    func testRecipesEmptyPassesAccessibilityAudit() throws {
        let empty = launch("recipes", mode: "empty")
        XCTAssertTrue(element("recipes.empty", in: empty).appears(timeout: 15))
        keepScreenshot(empty, "food-recipes-empty-\(device)")
        try audit(empty) {
            let large = self.launch("recipes", mode: "empty", arguments: FentonHomeApp.ax5)
            XCTAssertTrue(self.element("recipes.empty", in: large).appears(timeout: 15))
            settleScreen()
            return large
        }
    }

    func testRecipesLoadMoreOnScroll() {
        let app = launch("recipes")
        waitForGrid(app)
        let last = element("recipes.card.120", in: app)
        let grid = element("recipes.grid", in: app)
        for _ in 0..<100 where !last.exists { grid.swipeUp(velocity: .fast) }
        XCTAssertTrue(last.exists, "infinite scroll stopped early")
        expectCall("recipe_query kind=browse q= sort=availability cursor=100", in: app)
    }
}
