import XCTest

/// The Add Item sheet: its three steps, the manual entry path, and an accessibility audit of each step. Sources: `ScanItemSheet`,
/// `ScanCamera`, `ScanProductHeader`, `CameraStatusPill`.
@MainActor
final class InventoryScanJourneyTests: InventoryJourneyTestCase {
    /// Opens Add Item and walks to `step` (1 scan, 2 expiry, 3 review), scrolled back to the top and settled.
    private func atStep(_ step: Int, _ arguments: [String]) -> XCUIApplication {
        let app = launch(open: "scan", arguments: arguments, clean: true, fresh: true)
        XCTAssertTrue(app.buttons["scan.cancel"].appears(timeout: 10))
        reveal(app.buttons["scan.simulate"], in: app)
        if step >= 2 {
            app.buttons["scan.simulate"].tap(until: { app.textFields["scan.name"].exists })
            // At AX5 the step's buttons scroll with the form. Forward stays disabled while the lookup runs;
            // tap until the expiry step shows.
            reveal(app.buttons["scan.forward"], in: app)
                .tap(until: { app.descendants(matching: .any)["scan.expiry"].exists },
                     stillOn: { app.descendants(matching: .any)["scan.barcode"].exists })
            reveal(app.buttons["scan.manualExpiry"], in: app)
        }
        if step >= 3 {
            reveal(app.buttons["scan.manualExpiry"], in: app)
                .tap(until: { app.switches["scan.hasExpiry"].exists || app.buttons["scan.quick.1-month"].exists })
            reveal(app.buttons["scan.quick.1-month"], in: app).tap()
            reveal(app.buttons["scan.forward"], in: app)
                .tap(until: { app.descendants(matching: .any)["scan.review"].exists },
                     stillOn: { app.descendants(matching: .any)["scan.expiry"].exists })
            XCTAssertTrue(app.descendants(matching: .any)["scan.review"].appears(timeout: 5))
        }
        // Back to the top: audited mid-scroll, a header faded under the sheet's bar reads as low contrast.
        if step >= 2 {
            let form = app.collectionViews.matching(NSPredicate(format: "identifier BEGINSWITH 'scan.'")).firstMatch
            for _ in 0..<4 where form.exists {
                // Only while the form is scrolled: at the top, a drag down closes a content-height sheet (the folded Duo's
                // default-size pass audited the Pantry page behind it, 2026-10-17). The first row sitting at or below the
                // form's top edge means it is at the top (a lazy form drops rows that scrolled away).
                let first = form.cells.firstMatch
                if first.exists, first.frame.minY >= form.frame.minY { break }
                form.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.2))
                    .press(forDuration: 0.05, thenDragTo: form.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.9)))
            }
        }
        settleScreen()
        return app
    }

    /// The first Add Item step (scan the barcode) passes the accessibility audit at default size and AX5.
    func testScanStepOnePassesAudit() throws {
        try auditScanStep(1)
    }

    /// The second Add Item step (the product is read, pick the expiry) passes the accessibility audit at default size and AX5.
    func testScanStepTwoPassesAudit() throws {
        try auditScanStep(2)
    }

    /// The third Add Item step (review and add) passes the accessibility audit at default size and AX5.
    func testScanStepThreePassesAudit() throws {
        try auditScanStep(3)
    }

    private func auditScanStep(_ step: Int) throws {
        let app = atStep(step, [])
        keepScreenshot(app, "inventory-scan-step\(step)-\(layout)")
        try FentonHomeApp.audit(app) { self.atStep(step, FentonHomeApp.ax5) }
        app.terminate()
    }

    /// Manual entry: type a name, pick a quick date, review.
    func testManualEntryFlow() {
        let app = launch(open: "scan")
        XCTAssertTrue(app.buttons["scan.cancel"].appears(timeout: 10))
        let name = app.textFields["scan.name"]
        reveal(app.buttons["scan.manualName"], in: app).tap(until: { name.exists })
        XCTAssertTrue(name.appears(timeout: 5))
        name.tap()
        name.typeText("Oat Milk")
        app.buttons["scan.forward"].tap(until: { app.descendants(matching: .any)["scan.expiry"].exists },
                                        stillOn: { app.descendants(matching: .any)["scan.barcode"].exists })
        reveal(app.buttons["scan.manualExpiry"], in: app).tap(until: { app.buttons["scan.quick.1-week"].exists })
        reveal(app.buttons["scan.quick.1-week"], in: app).tap()
        XCTAssertTrue(app.buttons["scan.quick.1-week"].isSelected)
        app.buttons["scan.forward"].tap(until: { app.descendants(matching: .any)["scan.review"].exists },
                                        stillOn: { app.descendants(matching: .any)["scan.expiry"].exists })
        XCTAssertTrue(app.buttons["scan.add"].appears(timeout: 5))
        // The review is a collection view: on a short window (the folded Duo) the location rows are built only once scrolled to.
        let dispensa = reveal(app.buttons["scan.location.dispensa"], in: app)
        XCTAssertTrue(dispensa.isSelected || reveal(app.buttons["scan.location.frigo"], in: app).isSelected)
    }

    /// Scan, read the date, review and add: the item lands in the pantry.
    func testScanFlowAddsItem() {
        // All Food: the fixture's location suggestion files Greek Yogurt in the fridge, not the pantry.
        let app = launch(space: "all-food", open: "scan")
        XCTAssertTrue(app.buttons["scan.cancel"].appears(timeout: 10))
        let name = app.textFields["scan.name"]
        reveal(app.buttons["scan.simulate"], in: app).tap(until: { name.exists })
        XCTAssertTrue(name.appears(timeout: 5))
        XCTAssertEqual(name.value as? String, "Greek Yogurt")
        // Each step's button is retried until its step shows: taps landing mid-transition are dropped.
        let step = { (id: String) in app.descendants(matching: .any)["scan.\(id)"].exists }
        app.buttons["scan.forward"].tap(until: { step("expiry") }, stillOn: { step("barcode") })

        reveal(app.buttons["scan.simulate"], in: app).tap(until: { app.buttons["scan.forward"].label == "Next" })
        app.buttons["scan.forward"].tap(until: { step("review") }, stillOn: { step("expiry") })

        XCTAssertTrue(app.buttons["scan.add"].appears(timeout: 5))
        app.buttons["scan.add"].tap(until: { app.buttons["scan.done"].exists })
        XCTAssertTrue(app.buttons["scan.done"].appears(timeout: 10))
        app.buttons["scan.done"].tap(until: { !app.buttons["scan.done"].exists })
        XCTAssertTrue(app.staticTexts["Greek Yogurt"].appears(timeout: 10), "Added row missing from All Food")
    }
}
