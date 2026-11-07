import XCTest

/// The Sort and Filter sheets: the expiring filter applies and marks Filter selected, and each sheet passes the accessibility audit.
/// Sources: `InventoryControlSheets`, `InventorySheetContent`, `InventoryListModel+Summary` (the Filter sheet's count line).
@MainActor
final class InventorySheetsJourneyTests: InventoryJourneyTestCase {
    /// The expiring filter keeps only items inside its window and marks Filter as applied.
    func testFilterSheetApplies() {
        let app = launch()
        XCTAssertTrue(app.buttons["fab.inventory.filter"].appears(timeout: 10))
        app.buttons["fab.inventory.filter"].tap()
        XCTAssertTrue(app.buttons["inventory.filter.expired"].appears(timeout: 5))
        app.buttons["inventory.filter.expired"].tap()
        app.buttons["filterSheet.apply"].tap()
        XCTAssertTrue(app.staticTexts["Spaghetti"].disappears(timeout: 5))
        XCTAssertTrue(app.staticTexts["Jasmine Rice"].exists)
        XCTAssertTrue(app.buttons["fab.inventory.filter"].isSelected)
    }

    /// The Sort sheet passes the accessibility audit at default size and AX5.
    func testSortSheetPassesAudit() throws {
        try auditSheet(open: "sort", ready: "inventory.sort.title", screenshot: "sort")
    }

    /// The Filter sheet passes the accessibility audit at default size and AX5.
    func testFilterSheetPassesAudit() throws {
        try auditSheet(open: "filter", ready: "inventory.filter.all", screenshot: "filter")
    }

    private func auditSheet(open: String, ready: String, screenshot: String) throws {
        func opened(_ arguments: [String]) -> XCUIApplication {
            let app = launch(open: open, arguments: arguments, clean: true, fresh: true)
            XCTAssertTrue(app.buttons[ready].firstMatch.appears(timeout: 10), "\(open) did not open")
            settleScreen() // Let the sheet settle.
            return app
        }
        let app = opened([])
        keepScreenshot(app, "inventory-\(screenshot)-\(layout)")
        try FentonHomeApp.audit(app) { opened(FentonHomeApp.ax5) }
        app.terminate()
    }
}
