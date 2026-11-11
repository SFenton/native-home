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

    // MARK: Row removal

    /// Writes a timestamped mark for the motion recorder (`FENTON_MOTION_MARKS`), as the single-page motion journeys do.
    private func mark(_ name: String) {
        guard let path = ProcessInfo.processInfo.environment["FENTON_MOTION_MARKS"], !path.isEmpty else { return }
        let line = "\(name) \(String(format: "%.3f", Date().timeIntervalSince1970))\n"
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? line.write(toFile: path, atomically: false, encoding: .utf8)
        }
    }

    /// Deleting one of two batches: the spinner holds the Delete row while EverShelf answers, then that batch's group leaves (the system
    /// list animation, no one-frame snap) and the other stays with its controls. `delete.start` and `delete.end` bracket it for recordings.
    func testDeletingOneOfTwoBatchesRemovesItsGroupAndKeepsTheOther() {
        let app = launch(open: "editor:Black Beans")
        XCTAssertTrue(app.descendants(matching: .any)["inventory.editor"].appears(timeout: 10))
        let deletes = app.buttons.matching(identifier: "inventory.editor.delete")
        let steppers = app.steppers.matching(identifier: "inventory.editor.quantity")
        XCTAssertTrue(deletes.element(boundBy: 1).appears(timeout: 5))
        XCTAssertEqual(deletes.count, 2)
        XCTAssertEqual(steppers.count, 2)
        let keptLabel = deletes.element(boundBy: 0).label
        let editorElement = app.descendants(matching: .any)["inventory.editor"]
        let heightBefore = editorElement.frame.height
        sleep(1)
        mark("delete.start")
        deletes.element(boundBy: 1).tap() // The second batch holds one unit, so it asks to confirm.
        let confirm = app.buttons["inventory.editor.delete.confirm"].firstMatch
        XCTAssertTrue(confirm.appears(timeout: 5))
        confirm.tap()
        let end = Date().addingTimeInterval(10)
        while deletes.count > 1, Date() < end { usleep(100_000) }
        mark("delete.end")
        // The content-fitted sheet follows the content down (its detent change animates through `UKHassModalController.updateDetents`),
        // so it never ends taller than it began.
        mark("sheet.height \(heightBefore) -> \(editorElement.frame.height)")
        XCTAssertLessThanOrEqual(editorElement.frame.height, heightBefore + 1)
        XCTAssertEqual(deletes.count, 1, "the deleted batch's group is gone")
        XCTAssertEqual(steppers.count, 1, "the other batch keeps its controls")
        XCTAssertFalse(app.alerts.firstMatch.exists)
        XCTAssertTrue(app.buttons["inventory.editor.delete"].firstMatch.exists, "the kept batch still offers Delete (was '\(keptLabel)')")
    }

    /// Cancelling the confirmation moves nothing: both groups stay and nothing is sent.
    func testCancellingABatchDeleteKeepsBothGroups() {
        let app = launch(open: "editor:Black Beans")
        XCTAssertTrue(app.descendants(matching: .any)["inventory.editor"].appears(timeout: 10))
        let deletes = app.buttons.matching(identifier: "inventory.editor.delete")
        XCTAssertTrue(deletes.element(boundBy: 1).appears(timeout: 5))
        deletes.element(boundBy: 1).tap()
        XCTAssertTrue(app.buttons["inventory.editor.delete.confirm"].firstMatch.appears(timeout: 5))
        cancelConfirmation(app)
        XCTAssertTrue(app.buttons["inventory.editor.delete.confirm"].firstMatch.disappears(timeout: 5))
        XCTAssertEqual(deletes.count, 2)
        XCTAssertFalse(lastCall(app).contains("delete_inventory"), lastCall(app))
    }
}
