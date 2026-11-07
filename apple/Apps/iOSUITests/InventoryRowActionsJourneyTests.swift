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
}
