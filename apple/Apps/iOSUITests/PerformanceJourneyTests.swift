import XCTest

/// The content gate and the Performance screen in the debug gallery: the spinner-then-content sequence, the
/// screen's semantics, and accessibility audits (default and AX5) on iPhone, iPhone Duo and iPad.
@MainActor
final class PerformanceJourneyTests: JourneyTestCase {
    /// These tests measure animation, so their launches keep it on (``JourneyTestCase/measuresAnimation``).
    override class var measuresAnimation: Bool { true }


    /// `gateDelayMs` stretches the gate demo's load (default 900 ms): the launch alone can outlast it, and the spinner
    /// (which shows 150 ms in) was gone before the first query.
    private func launch(_ mode: String, arguments: [String] = [], gateDelayMs: Int? = nil) -> XCUIApplication {
        let app = FentonHomeApp.makeApp()
        app.launchEnvironment["FENTON_GALLERY"] = "performance"
        app.launchEnvironment["FENTON_GALLERY_PERF"] = mode
        if let gateDelayMs { app.launchEnvironment["FENTON_GALLERY_GATE_DELAY_MS"] = String(gateDelayMs) }
        app.launchArguments += arguments
        app.launch()
        return app
    }

    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "\(name)-\(FentonHomeApp.family)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: - Content gate

    /// Loading hides the content and shows a labeled spinner; once loaded the spinner goes and the content shows.
    /// Reload fades the content out and runs the sequence again.
    func testGateShowsSpinnerThenContent() {
        let app = launch("gate", gateDelayMs: 4000)
        let spinner = element("contentGate.spinner", in: app)
        // A tile is a switch labelled "Item 1" whose subtitle is a child text, "Loaded 0"; the gate hides the tiles from
        // assistive technologies while it loads.
        func tile(loaded generation: Int) -> XCUIElement { app.staticTexts["Loaded \(generation)"].firstMatch }
        XCTAssertTrue(spinner.appears(timeout: 5), "No spinner while loading")
        XCTAssertEqual(spinner.label, "Loading")
        XCTAssertFalse(tile(loaded: 0).exists, "Content is reachable while it is hidden")
        screenshot("gate-loading")

        XCTAssertTrue(tile(loaded: 0).appears(timeout: 10), "Content never appeared")
        XCTAssertTrue(spinner.disappears(timeout: 2), "Spinner stayed after the content appeared")
        screenshot("gate-loaded")

        app.buttons["gate.reload"].tap()
        XCTAssertTrue(spinner.appears(timeout: 3), "Reload did not return to loading")
        XCTAssertTrue(tile(loaded: 1).appears(timeout: 10), "Reloaded content never appeared")
        XCTAssertTrue(spinner.disappears(timeout: 2), "Spinner stayed after the reload")
    }

    // MARK: - Performance screen

    /// Every section shows the seeded measurements; Reset clears scrolling.
    func testPerformanceScreenShowsMeasurements() {
        let app = launch("screen")
        XCTAssertTrue(element("performance.screen", in: app).appears(timeout: 10))
        // The seeded rows arrive with the screen's first refresh, a beat after the list itself.
        let recipes = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Recipes'")).firstMatch
        if !recipes.appears(timeout: 10) { add(XCTAttachment(string: app.debugDescription)) }
        XCTAssertTrue(recipes.exists, "Recipes scroll row missing")
        XCTAssertTrue(app.switches["performance.recording"].exists)
        screenshot("performance-top")
        for _ in 0..<4 { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(app.buttons["performance.export"].appears(timeout: 5), "Export missing")
        screenshot("performance-bottom")
        app.buttons["performance.reset"].tap()
        for _ in 0..<4 { app.collectionViews.firstMatch.swipeDown() }
        XCTAssertTrue(app.staticTexts["Scroll a page to measure it."].appears(timeout: 5), "Reset kept scroll rows")
    }

    func testPerformanceScreenPassesAccessibilityAudit() throws {
        let app = launch("screen")
        XCTAssertTrue(element("performance.screen", in: app).appears(timeout: 10))
        sleep(1)
        try FentonHomeApp.audit(app, ax5Page: { [self] in
            let large = launch("screen", arguments: FentonHomeApp.ax5)
            XCTAssertTrue(element("performance.screen", in: large).appears(timeout: 10))
            return large
        })
    }

    func testPerformanceScreenAtAX5() throws {
        let app = launch("screen", arguments: FentonHomeApp.ax5)
        XCTAssertTrue(element("performance.screen", in: app).appears(timeout: 10))
        sleep(1)
        screenshot("performance-ax5")
        try FentonHomeApp.audit(app)
    }

    func testGatePassesAccessibilityAudit() throws {
        let app = launch("gate")
        XCTAssertTrue(element("gate.content", in: app).appears(timeout: 10))
        XCTAssertTrue(element("contentGate.spinner", in: app).disappears(timeout: 5), "The spinner stayed")
        sleep(1)
        try FentonHomeApp.audit(app)
    }
}
