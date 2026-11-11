import XCTest

/// What a row asks for: Add to Groceries (the quantity alert, then EverShelf's shopping service and the to-do item) and the single-unit
/// delete from the trailing swipe action. Sources: `InventoryRowActions`, `InventoryPrompt`, `InventoryRow`.
@MainActor
final class InventoryRowActionsJourneyTests: InventoryJourneyTestCase {
    /// Cart asks for a quantity, then sends EverShelf's shopping service and the to-do list item.
    func testAddToGroceriesAsksForQuantity() {
        let app = launch(environment: ["FENTON_GALLERY_HOLD_ADDED": "1"])
        let cart = row(app, "Spaghetti").buttons["inventory.row.cart"]
        XCTAssertTrue(cart.appears(timeout: 10))
        cart.tap()
        // SwiftUI drops identifiers on alert text fields, so find the alert's only field.
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.appears(timeout: 5))
        field.clearAndType("2")
        app.alerts.buttons["Add"].tap(until: { !app.alerts.firstMatch.exists })
        XCTAssertTrue(app.buttons["Added Spaghetti to shopping list"].appears(timeout: 5))
        XCTAssertTrue(lastCall(app).contains("todo.add_item"), lastCall(app))
    }

    /// A single item deletes from its trailing swipe action after a confirmation (direction G rows show only the cart
    /// and the chevron).
    func testDeleteSingleItemConfirms() {
        let app = launch()
        let honey = row(app, "Honey")
        XCTAssertTrue(honey.appears(timeout: 10))
        honey.swipeLeft()
        let swipeDelete = app.buttons["Delete"].firstMatch
        XCTAssertTrue(swipeDelete.appears(timeout: 5))
        swipeDelete.tap()
        XCTAssertTrue(app.staticTexts["Delete Honey?"].appears(timeout: 5))
        XCTAssertTrue(app.staticTexts["It will be removed from the pantry."].exists)
        let confirm = app.buttons["inventory.delete.confirm"].firstMatch
        XCTAssertTrue(confirm.appears(timeout: 5))
        XCTAssertEqual(confirm.label, "Delete Item")
        confirm.tap()
        XCTAssertTrue(app.staticTexts["Honey"].disappears(timeout: 5))
        XCTAssertTrue(lastCall(app).hasPrefix("Last call: evershelf.list_inventory") || lastCall(app).contains("delete_inventory"))
    }

    // MARK: Row removal

    private func openSwipeDelete(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        let target = row(app, name)
        XCTAssertTrue(target.appears(timeout: 10))
        target.swipeLeft()
        let swipeDelete = app.buttons["Delete"].firstMatch
        XCTAssertTrue(swipeDelete.appears(timeout: 5))
        return swipeDelete
    }

    /// Delete leaves its neighbours in place: Honey goes and Spaghetti, above it, stays.
    func testSwipeDeleteRemovesTheRowAndKeepsItsNeighbours() {
        let app = launch()
        openSwipeDelete(app, "Honey").tap()
        let confirm = app.buttons["inventory.delete.confirm"].firstMatch
        XCTAssertTrue(confirm.appears(timeout: 5))
        confirm.tap()
        XCTAssertTrue(row(app, "Honey").disappears(timeout: 5))
        XCTAssertTrue(row(app, "Spaghetti").exists)
        XCTAssertTrue(row(app, "Black Beans").exists)
    }

    /// Cancelling the confirmation closes the swipe and keeps the row, with nothing sent.
    func testCancellingASwipeDeleteKeepsTheRow() {
        let app = launch()
        openSwipeDelete(app, "Honey").tap()
        XCTAssertTrue(app.staticTexts["Delete Honey?"].appears(timeout: 5))
        cancelConfirmation(app)
        XCTAssertTrue(app.staticTexts["Delete Honey?"].disappears(timeout: 5))
        XCTAssertTrue(row(app, "Honey").exists)
        XCTAssertFalse(lastCall(app).contains("delete_inventory"), lastCall(app))
    }

    /// The swipe's Delete spans the whole row, which is at least 44 pt tall (HIG, Touch targets), also at the largest text size. The
    /// button's own frame is the system's label area, so the row is what is measured.
    func testSwipeDeleteIsATouchTargetAtDefaultAndAX5() {
        for ax5 in [false, true] {
            let app = launch(arguments: ax5 ? FentonHomeApp.ax5 : [], fresh: true)
            let button = openSwipeDelete(app, "Honey")
            XCTAssertGreaterThanOrEqual(row(app, "Honey").frame.height, 44, "ax5=\(ax5)")
            XCTAssertTrue(button.isHittable, "ax5=\(ax5)")
            app.terminate()
        }
    }
}
