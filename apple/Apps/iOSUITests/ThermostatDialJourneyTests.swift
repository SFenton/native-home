import XCTest

/// The shared thermostat dial in the debug gallery: drag, tap, VoiceOver semantics, audits and
/// screenshots on iPhone, iPhone Duo and iPad (`.agents/patterns/thermostat-dial.md`).
@MainActor
final class ThermostatDialJourneyTests: JourneyTestCase {

    private func launch(arguments: [String] = []) -> XCUIApplication {
        // The gallery has no switches; each test is a reset of the class's resident app (`app-reuse.md`). AX5 (`arguments`) launches
        // fresh by signature.
        let configured = FentonHomeApp.makeApp()
        configured.launchEnvironment["FENTON_GALLERY"] = "thermostat-dial"
        configured.launchArguments += arguments
        let app = startApp(configured)
        XCTAssertTrue(app.staticTexts["gallery.lastCommit"].appears(timeout: 10))
        return app
    }

    private func card(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["gallery.thermostat.\(id)"].firstMatch
    }

    private func handle(_ name: String, in card: XCUIElement) -> XCUIElement {
        card.descendants(matching: .any)["thermostatDial.handle.\(name)"].firstMatch
    }

    /// Scrolls until all of `element` is on screen (or the page ends). The gallery grid is lazy, so a card
    /// far below may not exist until scrolled near. Drags along the leading edge, outside every dial, so
    /// the scroll never grabs a handle.
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        let window = app.windows.firstMatch
        let bottom = window.frame.maxY - 24
        let windowHeight = window.frame.height
        // One snapshot per look (existence and frame together); `isHittable` is asked only once the frame is clear of the bottom.
        func frame() -> CGRect? { (try? element.snapshot())?.frame }
        for _ in 0..<12 {
            let before = frame()
            if let before, before.maxY <= bottom, element.isHittable { break }
            let distance = before.map { $0.maxY - bottom + 24 } ?? windowHeight
            let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.75))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(
                CGVector(dx: 0, dy: -Swift.min(Swift.max(distance, 60), windowHeight * 0.45))))
            if let before, let after = frame(), after.minY == before.minY { break } // The page ended.
        }
        XCTAssertTrue(element.isHittable, "\(element) never came into view")
    }

    private func lastCommit(_ app: XCUIApplication) -> String { app.staticTexts["gallery.lastCommit"].label }

    // MARK: - Semantics

    /// Each handle is a named, adjustable, 44 pt+ element; the readout is one element with name, action
    /// and current temperature; the unavailable dial has no handles.
    func testHandlesAndReadoutAreAccessible() {
        let app = launch()
        let heating = card("heating", in: app)
        let target = handle("target", in: heating)
        XCTAssertTrue(target.appears(timeout: 5))
        if let facts = try? target.snapshot() { // label, value and size in one read
            XCTAssertEqual(facts.label, "Living Room target temperature")
            XCTAssertEqual(facts.value as? String, "72 degrees")
            XCTAssertGreaterThanOrEqual(facts.frame.width, 43)
            XCTAssertGreaterThanOrEqual(facts.frame.height, 43)
        } else { XCTFail("No snapshot of the target handle") }
        let readout = heating.descendants(matching: .any)["thermostatDial.readout"].firstMatch
        XCTAssertEqual(readout.label, "Living Room thermostat, Heating, currently 68.5°F")

        let range = card("range", in: app)
        scrollTo(range, in: app)
        XCTAssertEqual(handle("low", in: range).label, "Whole Home heat to")
        XCTAssertEqual(handle("high", in: range).label, "Whole Home cool to")

        let unavailable = card("unavailable", in: app)
        scrollTo(unavailable, in: app)
        XCTAssertFalse(unavailable.descendants(matching: .any)["thermostatDial.handle.target"].exists)
    }

    // MARK: - Interaction

    /// Dragging the single handle to the top of the ring commits the middle of the range (70°).
    func testDraggingTheHandleCommitsOnRelease() {
        let app = launch()
        let heating = card("heating", in: app)
        let target = handle("target", in: heating)
        XCTAssertTrue(target.appears(timeout: 5))
        let dial = heating.descendants(matching: .any)["thermostatDial"].firstMatch
        let top = dial.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12))
        target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.1, thenDragTo: top)
        XCTAssertTrue(app.staticTexts["gallery.lastCommit"].wait(for: \.label, toEqual: "Last commit: heating single 70", timeout: 3),
                      lastCommit(app))
        XCTAssertEqual(target.value as? String, "70 degrees")
    }

    // VoiceOver's adjustable action (swipe up/down on a handle) is covered by the hosted
    // `Apps/iOSTests/ThermostatDialAccessibilityTests`: XCUITest can only adjust slider elements.

    /// Tapping the ring past the cool-to handle moves that handle there.
    func testTappingTheRingMovesTheNearestHandle() {
        let app = launch()
        let range = card("range", in: app)
        scrollTo(range, in: app)
        let dial = range.descendants(matching: .any)["thermostatDial"].firstMatch
        // Right side of the ring, level with the centre: 86.5° on a 45–95 ring.
        // The ring is a square of the shorter side, centred in the dial's frame (the folded Duo's is 402 x 340 pt, wider than tall).
        let dialFrame = dial.frame
        let side = min(dialFrame.width, dialFrame.height)
        dial.coordinate(withNormalizedOffset: CGVector(dx: 0.5 + 0.453 * (side - 40) / dialFrame.width, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["gallery.lastCommit"].wait(for: \.label, toEqual: "Last commit: range range 68-86.5", timeout: 3),
                      lastCommit(app))
    }

    // MARK: - Audits and screenshots

    /// The iPad's two poses used to be one test; each is its own now. ``upright`` sets portrait on an iPad and leaves the
    /// phones and the Duo as they are; ``iPadLandscape`` is the iPad-only, layout-relevant pose (skipped elsewhere).
    private enum Pose { case upright, iPadLandscape }

    /// Full accessibility audit (with the AX5 relaunch) in one orientation, plus a screenshot of each fixture for the PR.
    private func auditAndCapture(pose: Pose) throws {
        let orientation: String
        switch pose {
        case .upright:
            if FentonHomeApp.family == .iPad { XCUIDevice.shared.orientation = .portrait }
            orientation = "portrait"
        case .iPadLandscape:
            guard FentonHomeApp.family == .iPad else { throw XCTSkip("iPad only") }
            XCUIDevice.shared.orientation = .landscapeLeft
            settleScreen()
            orientation = "landscape"
        }
        let app = launch()
        try FentonHomeApp.audit(app) {
            let large = self.launch(arguments: FentonHomeApp.ax5)
            settleScreen()
            return large
        }
        let fresh = launch()
        for id in ["heating", "range", "cooling", "off", "unavailable"] {
            scrollTo(card(id, in: fresh), in: fresh)
            settleScreen()
            keepScreenshot(fresh, "thermostat-\(orientation)-\(id)")
        }
    }

    func testGalleryAuditsAndScreenshots() throws { try auditAndCapture(pose: .upright) }

    func testGalleryAuditsAndScreenshotsInIPadLandscape() throws { try auditAndCapture(pose: .iPadLandscape) }
}
