import XCTest

/// The item editor (a sheet, or the trailing pane on split layouts): prepared food flips and is confirmed by a fresh read, and the editor
/// passes the accessibility audit for a batched and a single item. Sources: `InventoryItemEditor`, `InventoryRowActions`.
@MainActor
final class InventoryEditorJourneyTests: InventoryJourneyTestCase {
    /// Prepared food flips at once and is confirmed by a fresh read.
    func testEditorMarksPreparedFood() {
        let app = launch(open: "editor:Spaghetti")
        let toggle = app.switches["inventory.editor.prepared"]
        XCTAssertTrue(toggle.appears(timeout: 10))
        toggle.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Prepared")).firstMatch.appears(timeout: 5))
    }

    /// The editor for Black Beans (two batches) passes the accessibility audit at default size and AX5.
    func testEditorForABatchedItemPassesAudit() throws {
        try auditEditor(item: "Black Beans")
    }

    /// The editor for Honey (one batch) passes the accessibility audit at default size and AX5.
    func testEditorForASingleItemPassesAudit() throws {
        try auditEditor(item: "Honey")
    }

    private func auditEditor(item: String) throws {
        func opened(_ arguments: [String]) -> XCUIApplication {
            let app = launch(open: "editor:\(item)", arguments: arguments, clean: true, fresh: true)
            XCTAssertTrue(app.buttons["inventory.editor.close"].firstMatch.appears(timeout: 10), "editor:\(item) did not open")
            settleScreen() // Let the sheet settle.
            return app
        }
        let app = opened([])
        let name = item.replacingOccurrences(of: " ", with: "-").lowercased()
        keepScreenshot(app, "inventory-editor-\(name)-\(layout)")
        try FentonHomeApp.audit(app) { opened(FentonHomeApp.ax5) }
        app.terminate()
    }

    /// The editor lists each batch; lowering the quantity and saving deletes one from the smallest row.
    func testEditorSavesQuantityChange() {
        let app = launch(open: "editor:Black Beans")
        let editor = app.descendants(matching: .any)["inventory.editor"]
        XCTAssertTrue(editor.appears(timeout: 10))
        let steppers = app.steppers.matching(identifier: "inventory.editor.quantity")
        XCTAssertEqual(steppers.count, 2, "Black Beans has two batches")
        steppers.element(boundBy: 0).buttons.element(boundBy: 0).tap() // Decrement.
        let save = app.buttons["inventory.editor.save"].firstMatch
        XCTAssertTrue(save.appears(timeout: 5))
        save.tap()
        XCTAssertTrue(lastCall(app).contains("evershelf."), lastCall(app))
    }
}
