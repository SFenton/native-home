import XCTest

/// Landscape on iPad and the iPhone Duo: the hub goes to two columns and an open recipe fills the trailing half where a split is
/// allowed (unfolded Duo, iPad); the folded Duo keeps the sheet. iPhone is portrait-only, so this skips there and costs nothing on
/// the primary family; it is selected by the files whose layout depends on pose (`.agents/design/apple/split-view.md`).
@MainActor
final class FoodWideLayoutJourneyTests: FoodJourneyTestCase {
    /// Skips on iPhone, else turns the device to landscape (the shared start of every step).
    private func landscape() throws {
        guard FentonHomeApp.family != .iPhone else { throw XCTSkip("iPhone is portrait-only") }
        XCUIDevice.shared.orientation = .landscapeLeft
    }

    /// Opens recipe 6 from the landscape grid.
    private func openRecipe6() -> XCUIApplication {
        let app = launch("recipes")
        waitForGrid(app)
        element("recipes.card.6", in: app).tap()
        XCTAssertTrue(element("recipe.tabs", in: app).appears(timeout: 10))
        settleScreen()
        return app
    }

    /// The hub in landscape, audited. Step 1 of the split landscape journey (`testLandscapeSplit*`).
    func testLandscapeSplitHubAudit() throws {
        try landscape()
        let hub = launch("hub")
        XCTAssertTrue(element("food.suggestion.1", in: hub).appears(timeout: 15))
        settleScreen()
        keepScreenshot(hub, "food-hub-\(device)-landscape")
        try audit(hub)
    }

    /// The Recipes grid in landscape.
    func testLandscapeSplitRecipesGrid() throws {
        try landscape()
        let app = launch("recipes")
        waitForGrid(app)
        keepScreenshot(app, "food-recipes-\(device)-landscape")
    }

    /// An open recipe: the pane (where a split is allowed) follows card selection, closes and reopens; the folded Duo keeps the sheet.
    func testLandscapeSplitPaneSelection() throws {
        try landscape()
        let app = openRecipe6()
        let window = app.windows.firstMatch.frame
        if element("recipe.pane", in: app).exists {
            XCTAssertTrue(element("recipes.card.6", in: app).isSelected)
            // The grid stays usable beside the pane: a card beside it takes a tap and the pane follows it. `isHittable`
            // is not asked: XCUITest reported the first match of a card's identifier (a label-less twin of the button)
            // not hittable although the card took taps (iPad landscape, 2026-10-17).
            let other = element("recipes.card.11", in: app)
            XCTAssertTrue(other.exists, "the grid stays visible beside the pane")
            XCTAssertTrue(window.contains(other.frame), "card 11 lies inside the window: \(other.frame) in \(window)")
            other.tap()
            if !other.wait(for: \.isSelected, toEqual: true, timeout: 5) { add(XCTAttachment(string: app.debugDescription)) }
            XCTAssertTrue(other.isSelected, "a card beside the pane takes the selection")
            XCTAssertTrue(element("recipes.card.6", in: app).wait(for: \.isSelected, toEqual: false, timeout: 5))
            element("recipe.close", in: app).tap()
            XCTAssertTrue(element("recipe.pane", in: app).disappears(timeout: 3), "The pane stayed open")
            element("recipes.card.6", in: app).tap()
            XCTAssertTrue(element("recipe.pane", in: app).appears(timeout: 5))
        } else {
            XCTAssertNotEqual(FentonHomeApp.family, .iPad, "iPad landscape (\(window)) must split")
            XCTAssertTrue(element("recipe.done", in: app).exists)
        }
    }

    /// The open recipe (pane or sheet) in landscape, audited.
    func testLandscapeSplitPaneAudit() throws {
        try landscape()
        let app = openRecipe6()
        keepScreenshot(app, "food-recipe-general-\(device)-landscape")
        try audit(app)
    }
}
