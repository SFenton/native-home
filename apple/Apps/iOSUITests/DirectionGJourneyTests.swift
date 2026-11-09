import XCTest

/// Direction G's foundation in the debug gallery (`FENTON_GALLERY=direction-g`): status chips, tile faces, the
/// light dragger, modules, spinners, the primary button and a sheet with the bottom glass section bar. Names,
/// targets, actions, audits (including the rendered contrast check) and screenshots on iPhone, iPhone Duo and iPad
/// (`.agents/design/direction-g-plan.md`, Phase 1).
@MainActor
final class DirectionGJourneyTests: JourneyTestCase {
    /// Launches (or, with reuse on, resets) the gallery. The page order is `FENTON_GALLERY_DIRECTION_G_ORDER` (the same as the
    /// `-directionGOrder` argument, which the gallery lets the variable override), a gallery setting a reset can change, so the class
    /// keeps one resident app. AX5 (`arguments`) is part of the launch signature and launches fresh (`app-reuse.md`).
    private func launch(order: String? = nil, arguments: [String] = []) -> XCUIApplication {
        let configured = FentonHomeApp.makeApp()
        configured.launchEnvironment["FENTON_GALLERY"] = "direction-g"
        if let order { configured.launchEnvironment["FENTON_GALLERY_DIRECTION_G_ORDER"] = order }
        configured.launchArguments += arguments
        let app = startApp(configured)
        XCTAssertTrue(app.buttons["g.chip.Lights"].appears(timeout: 10))
        return app
    }

    private func lastAction(_ app: XCUIApplication) -> String {
        app.staticTexts["gallery.lastCall"].label
    }

    /// Chips read their title and state, tiles read their state, and every control is at least 44 pt.
    func testChipsAndTilesAreNamedAndLargeEnough() {
        let app = launch()
        // One tree snapshot for every label, value and frame (each is otherwise a request of its own).
        let ids = ["g.chip.Lights", "g.tile.Office Lamp", "g.tile.Living Room Purifier", "g.tile.Garage Door", "g.tile.light"]
        var found: [String: any XCUIElementSnapshot] = [:]
        func walk(_ node: any XCUIElementSnapshot) {
            if ids.contains(node.identifier), found[node.identifier] == nil { found[node.identifier] = node }
            node.children.forEach(walk)
        }
        guard let root = try? app.snapshot() else { return XCTFail("No tree snapshot") }
        walk(root)
        for id in ids {
            let node = found[id]
            XCTAssertNotNil(node, "\(id) missing")
            guard let node else { continue }
            XCTAssertGreaterThanOrEqual(node.frame.width, 43, node.label)
            XCTAssertGreaterThanOrEqual(node.frame.height, 43, node.label)
        }
        XCTAssertEqual(found["g.chip.Lights"]?.label, "Lights, 3 On")
        XCTAssertEqual(found["g.tile.Garage Door"]?.value as? String, "Didn't Respond",
                       "An error tile reads its state, not On or Off")
        XCTAssertEqual(found["g.tile.light"]?.value as? String, "60%")
    }

    /// Tapping a chip and a tile records their actions (the light's taps are ``testLightTogglesRepeatedly``).
    func testChipAndTileTapsAct() {
        let app = launch()
        app.buttons["g.chip.Climate"].tap()
        XCTAssertEqual(lastAction(app), "Last action: chip Climate")
        element("g.tile.Office Lamp", in: app).tap()
        XCTAssertEqual(lastAction(app), "Last action: tile Office Lamp")
    }

    /// The light toggles off and on repeatedly, its face swapping between the lit and off grounds each time.
    func testLightTogglesRepeatedly() {
        let app = launch()
        let light = element("g.tile.light", in: app)
        for expected in ["power false", "power true", "power false", "power true", "power false", "power true"] {
            light.tap()
            XCTAssertEqual(lastAction(app), "Last action: \(expected)")
        }
        XCTAssertEqual(light.value as? String, "100%")
    }

    /// Dragging the light tile sideways sets its brightness.
    func testDraggingTheLightSetsBrightness() {
        let app = launch()
        let tile = element("g.tile.light", in: app)
        let start = tile.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5))
        let end = tile.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertTrue(lastAction(app).hasPrefix("Last action: brightness"), lastAction(app))
    }

    /// The page in its default order, audited with the AX5 relaunch.
    func testPagePassesAccessibilityAuditDefault() throws {
        let app = launch()
        keepScreenshot(app, "direction-g-\(layout)")
        try FentonHomeApp.audit(app) { self.launch(arguments: FentonHomeApp.ax5) }
    }

    /// The modules, spinners and primary buttons, moved to the top so they are audited unscrolled.
    func testPagePassesAccessibilityAuditLowerFirst() throws {
        let lower = launch(order: "lower")
        keepScreenshot(lower, "direction-g-lower-\(layout)")
        try FentonHomeApp.audit(lower) { self.launch(order: "lower", arguments: FentonHomeApp.ax5) }
    }

    /// Opens the gallery's sheet from the primary button, scrolling the page until it is reachable.
    private func openSheet(_ app: XCUIApplication) -> XCUIApplication {
        let primary = app.buttons["g.primary"]
        for _ in 0..<6 where !primary.isHittable { app.swipeUp() }
        primary.tap()
        XCTAssertTrue(app.buttons["sheet.close"].appears(timeout: 5))
        settleScreen() // Let the sheet settle.
        return app
    }

    /// The sheet's section bar is a segmented control along the bottom, and switching sections swaps the tiles.
    func testSheetSectionBarSitsAtTheBottomAndSwitches() {
        let app = openSheet(launch())
        let tabs = app.segmentedControls["g.sheet.tabs"]
        XCTAssertTrue(tabs.exists)
        XCTAssertGreaterThan(tabs.frame.midY, app.windows.firstMatch.frame.midY, "The section bar sits in the bottom half")
        tabs.buttons["Apps"].tap()
        XCTAssertTrue(app.buttons["Netflix"].appears(timeout: 5))
    }

    /// The sheet on its Apps section passes the audit (with the AX5 relaunch to the same section).
    func testSheetSectionBarPassesAccessibilityAudit() throws {
        func openApps(_ app: XCUIApplication) -> XCUIApplication {
            let app = openSheet(app)
            app.segmentedControls["g.sheet.tabs"].buttons["Apps"].tap()
            XCTAssertTrue(app.buttons["Netflix"].appears(timeout: 5))
            return app
        }
        let app = openApps(launch())
        keepScreenshot(app, "direction-g-sheet-\(layout)")
        try FentonHomeApp.audit(app) { openApps(self.launch(arguments: FentonHomeApp.ax5)) }
    }
}
