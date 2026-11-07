import XCTest

/// The Pantry page against the real EverShelf server (signed in); the Live plan only. It skips without credentials.
@MainActor
final class InventoryLiveJourneyTests: InventoryJourneyTestCase {
    /// Signed in against the real server, `FENTON_OPEN_INVENTORY=pantry` pushes the Pantry page from Home.
    /// Item names are redacted under `FENTON_REDACT_PRIVATE=1`. Skips without credentials.
    func testLivePantryOpensFromHome() throws {
        let app = try FentonHomeApp.launchSignedIn(environment: ["FENTON_OPEN_INVENTORY": "pantry"], readyIdentifier: "inventory.pantry")
        let loaded = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'inventory.row.' OR identifier == 'inventory.empty'")).firstMatch
        XCTAssertTrue(loaded.appears(timeout: 30), "Pantry rows did not load")
        settleScreen()
        keepScreenshot(app, "inventory-live-pantry-\(layout)")
    }
}
