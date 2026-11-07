import XCTest

/// The Inventory pages: how rows group and read their expiry, the trailing quantity and the actions beside the text, the loading arc,
/// the expiry sort's status headers, search, and the accessibility audits of every space and of the empty and error states.
/// Sources: `InventoryScreen`, `InventoryRow`, `InventorySections`, `InventoryPresentation`, `InventoryListModel+Summary`.
@MainActor
final class InventoryListJourneyTests: InventoryJourneyTestCase {
    /// Rows group by name: Black Beans' two batches share one card with a disclosure; expired and undated
    /// items read their state.
    func testPantryRowsGroupAndReadExpiry() {
        let app = launch()
        XCTAssertTrue(row(app, "Black Beans").appears(timeout: 10))
        XCTAssertTrue(app.staticTexts["Jasmine Rice"].exists)
        XCTAssertTrue(app.staticTexts["Honey"].exists)
        XCTAssertFalse(app.staticTexts["Whole Milk"].exists, "Fridge item on the pantry page")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "expired")).firstMatch.exists)
        let beans = row(app, "Black Beans")
        XCTAssertTrue(beans.buttons["Edit Black Beans"].exists)
        XCTAssertFalse(beans.buttons["Delete Black Beans"].exists, "Multi-batch rows delete from the editor")
        // Direction G: every editable row carries the cart and a chevron that opens the editor (mockup n6-inventory).
        XCTAssertTrue(row(app, "Honey").buttons["Edit Honey"].exists)
        XCTAssertFalse(row(app, "Honey").buttons["inventory.row.delete"].exists, "Rows delete from their swipe action")
    }

    /// The design pass (owner, 2026-10-16): the stock count is a trailing number (and part of the row's spoken label),
    /// the expiry line stays short, and the actions stay beside the text on every row.
    func testRowsShowQuantityTrailingAndKeepActionsBesideTheText() {
        let app = launch()
        let beans = row(app, "Black Beans")
        XCTAssertTrue(beans.appears(timeout: 10))
        XCTAssertTrue(beans.staticTexts["Multiple Expiration Dates"].exists, "The subtitle is the expiry alone")
        XCTAssertFalse(app.staticTexts["Quantity 3 · Multiple Expiration Dates"].exists, "The old long subtitle is back")
        let copy = beans.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Black Beans'")).firstMatch
        let cart = beans.buttons["inventory.row.cart"]
        let honeyCart = row(app, "Honey").buttons["inventory.row.cart"]
        // Labels and frames come from one snapshot each, not a request per property.
        let copyShot = try? copy.snapshot()
        let beansFrame = (try? beans.snapshot())?.frame ?? .zero
        let cartShot = try? cart.snapshot()
        let honeyCartFrame = (try? honeyCart.snapshot())?.frame ?? .zero
        XCTAssertTrue(copyShot?.label.contains("Quantity 3") == true, "VoiceOver label is '\(copyShot?.label ?? "")'")
        // The module keeps the page margin; it ran edge to edge once when a margin override replaced the list's own inset.
        let windowWidth = app.windows.firstMatch.frame.width
        XCTAssertGreaterThanOrEqual(beansFrame.minX, 12, "The rows run edge to edge")
        XCTAssertLessThanOrEqual(beansFrame.maxX, windowWidth - 12, "The rows run edge to edge")
        let cartFrame = cartShot?.frame ?? .zero
        XCTAssertFalse(cartFrame.isEmpty, "No cart button")
        // The cart sits at the same x on a two-line and a one-line row, and on the title's line, not under it.
        XCTAssertEqual(cartFrame.minX, honeyCartFrame.minX, accuracy: 2, "Cart buttons do not line up")
        XCTAssertLessThan(cartFrame.minY, (copyShot?.frame ?? .zero).maxY, "Actions wrapped under the text")
        XCTAssertGreaterThanOrEqual(cartFrame.width, 43)
        XCTAssertGreaterThanOrEqual(cartFrame.height, 43)
    }

    /// The page is live at once (owner, 2026-10-24, `proposals/loading-states`): Scan Item shows with the title and an arc
    /// sits where the rows will land; the rows then arrive in place.
    func testPageShowsAnArcThenRows() {
        // Answers take 5 s, so the wait outlasts the simulator's own launch and can be watched.
        let app = launch(environment: ["FENTON_GALLERY_LATENCY_MS": "5000"])
        let arc = app.descendants(matching: .any)["inventory.loading"].firstMatch
        XCTAssertTrue(arc.appears(timeout: 5), "The arc never showed")
        XCTAssertEqual(arc.label, "Loading Pantry")
        XCTAssertFalse(app.descendants(matching: .any)["contentGate.spinner"].firstMatch.exists, "A page-size spinner is back")
        XCTAssertTrue(app.buttons["fab.inventory.scan"].exists, "Scan Item waits for the rows")
        XCTAssertFalse(row(app, "Honey").exists)
        XCTAssertTrue(row(app, "Honey").appears(timeout: 25))
        XCTAssertTrue(arc.disappears(timeout: 3))
    }

    /// A page whose rows never arrive keeps its arc and stays usable.
    func testLoadingStateKeepsTheArcAndScanItem() {
        let app = launch(state: "loading")
        XCTAssertTrue(app.descendants(matching: .any)["inventory.loading"].firstMatch.appears(timeout: 5))
        settleScreen()
        XCTAssertTrue(app.descendants(matching: .any)["inventory.loading"].firstMatch.exists)
        XCTAssertTrue(app.buttons["fab.inventory.scan"].exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'inventory.row.'")).firstMatch.exists)
    }

    /// Sorted by expiration date, rows group under status headers with their counts.
    func testInventoryExpirySortGroupsRowsUnderHeaders() {
        let app = launch(space: "all-food", clean: true, environment: ["FENTON_GALLERY_SORT": "expiry"])
        let expired = app.descendants(matching: .any)["inventory.section.expired"].firstMatch
        XCTAssertTrue(expired.appears(timeout: 15), "No Expired header")
        for id in ["soon", "later"] {
            XCTAssertTrue(app.descendants(matching: .any)["inventory.section.\(id)"].firstMatch.exists, "No \(id) header")
        }
        XCTAssertTrue(expired.label.contains("Expired"), expired.label)
        // Jasmine Rice is the one expired card, listed under that header and above Chicken Soup under Expiring Soon.
        XCTAssertLessThan(row(app, "Jasmine Rice").frame.minY, row(app, "Chicken Soup").frame.minY)
        settleScreen()
        keepScreenshot(app, "inventory-all-food-expiry-\(layout)")
    }

    /// The expiry-sorted All Food page passes the accessibility audit at default size and AX5.
    func testInventoryExpirySortPassesAccessibilityAudit() throws {
        let app = launch(space: "all-food", clean: true, environment: ["FENTON_GALLERY_SORT": "expiry"])
        XCTAssertTrue(app.descendants(matching: .any)["inventory.section.expired"].firstMatch.appears(timeout: 15), "No Expired header")
        settleScreen()
        try FentonHomeApp.audit(app) {
            self.launch(space: "all-food", arguments: FentonHomeApp.ax5, clean: true, environment: ["FENTON_GALLERY_SORT": "expiry"])
        }
    }

    /// Searching filters the page; closing search brings the rows back.
    func testSearchFiltersRows() {
        let app = launch()
        XCTAssertTrue(app.buttons["fab.search"].appears(timeout: 10))
        app.buttons["fab.search"].tap()
        let field = app.textFields["fab.search.field"]
        XCTAssertTrue(field.appears(timeout: 5))
        field.typeText("rice")
        XCTAssertTrue(app.staticTexts["Spaghetti"].disappears(timeout: 5))
        XCTAssertTrue(app.staticTexts["Jasmine Rice"].exists)
        app.buttons["fab.search.close"].tap()
        XCTAssertTrue(app.staticTexts["Spaghetti"].appears(timeout: 5))
    }

    /// One inventory page passes the accessibility audit at default size and AX5, each launch fresh. A pull request audits the one space
    /// `changedEnvironment` names in `contracts/test-map.json` (`FENTON_UITEST_SPACES`, set by `tools/ios_uitest.sh --changed`): the other
    /// spaces' tests skip. The nightly and release runs name no space and audit all six. One test per space, sharing this body.
    private func assertSpacePassesAudit(_ space: String) throws {
        guard !Self.only([space], "FENTON_UITEST_SPACES").isEmpty else { throw XCTSkip("\(space) not selected by FENTON_UITEST_SPACES") }
        let app = launch(space: space, clean: true, fresh: true)
        XCTAssertTrue(app.descendants(matching: .any)["inventory.\(space)"].appears(timeout: 10))
        XCTAssertTrue(app.buttons["fab.inventory.scan"].appears(timeout: 10))
        keepScreenshot(app, "inventory-\(space)-\(layout)")
        try FentonHomeApp.audit(app) { self.launch(space: space, arguments: FentonHomeApp.ax5, clean: true, fresh: true) }
        app.terminate()
    }

    func testInventoryAllFoodPassesAccessibilityAudit() throws { try assertSpacePassesAudit("all-food") }

    func testInventoryPantryPassesAccessibilityAudit() throws { try assertSpacePassesAudit("pantry") }

    func testInventoryFridgePassesAccessibilityAudit() throws { try assertSpacePassesAudit("fridge") }

    func testInventoryFreezerPassesAccessibilityAudit() throws { try assertSpacePassesAudit("freezer") }

    func testInventorySpiceRackPassesAccessibilityAudit() throws { try assertSpacePassesAudit("spice-rack") }

    func testInventoryCabinetPassesAccessibilityAudit() throws { try assertSpacePassesAudit("cabinet") }

    /// The empty page (no items) passes the accessibility audit at default size and AX5.
    func testEmptyStatePassesAudit() throws {
        try auditStatePage("empty")
    }

    /// The failed-load page (error message and Try Again) passes the accessibility audit at default size and AX5.
    func testErrorStatePassesAudit() throws {
        try auditStatePage("error")
    }

    private func auditStatePage(_ state: String) throws {
        let app = launch(state: state, clean: true, fresh: true)
        XCTAssertTrue(app.descendants(matching: .any)["inventory.empty"].appears(timeout: 10))
        keepScreenshot(app, "inventory-\(state)-\(layout)")
        try FentonHomeApp.audit(app) { self.launch(state: state, arguments: FentonHomeApp.ax5, clean: true, fresh: true) }
        app.terminate()
    }
}
