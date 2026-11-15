import XCTest

/// The state-styled tile in the debug gallery (`FENTON_GALLERY=state-tile`): a door tile with a disc and a robot tile with none, stepped through
/// their states by `stateTile.set.<tile>.<state>` buttons. Written for iPhone, iPhone Duo and iPad alike: the tile knows no device
/// (`.agents/design/state-styled-tile.md`; `.agents/design/state-styles.md`).
///
/// The arc is drawn but not an accessibility element, so a journey reads what the person using VoiceOver reads: the disc's value and enabled
/// state, and the tile's value. The arc itself, its size and the cross-fade are asserted by `UKHostedStateTileViewTests`.
@MainActor
final class StateTileJourneyTests: JourneyTestCase {
    private let door = "stateTile.door"

    /// Launches (or resets) the gallery. AX5 and the system settings are part of the launch signature and launch fresh (`app-reuse.md`).
    private func launch(door state: String = "closed", arguments: [String] = [], settings: [FentonHomeApp.SystemSetting] = []) -> XCUIApplication {
        let configured = FentonHomeApp.makeApp()
        configured.launchEnvironment["FENTON_GALLERY"] = "state-tile"
        configured.launchEnvironment["FENTON_GALLERY_STATE_TILE_DOOR"] = state
        configured.launchEnvironment.merge(FentonHomeApp.SystemSetting.environment(settings)) { _, new in new }
        configured.launchArguments += arguments
        let app = startApp(configured)
        XCTAssertTrue(element(door, in: app).appears(timeout: 15))
        return app
    }

    private func set(_ state: String, tile: String = "door", in app: XCUIApplication) {
        let button = app.buttons["stateTile.set.\(tile).\(state)"]
        if !button.isHittable { app.swipeUp() }
        button.tap()
    }

    /// Waits for the element's value to read `expected` (the one-second hold of the in-progress look can delay it).
    private func expectValue(_ id: String, _ expected: String, in app: XCUIApplication, timeout: TimeInterval = 6,
                             file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "value == %@", expected)
        let result = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element(id, in: app))], timeout: timeout)
        XCTAssertEqual(result, .completed, "\(id) reads '\(element(id, in: app).value as? String ?? "nil")', expected '\(expected)'", file: file, line: line)
    }

    // MARK: Journeys

    /// Resting to in-progress to resting: while a tap does nothing the disc reads disabled and "in progress"; it takes taps again at rest.
    func testRestingToInProgressToResting() {
        let app = launch()
        let disc = element(door, in: app)
        XCTAssertTrue(disc.isEnabled)
        expectValue(door, "Closed", in: app)
        set("opening", in: app)
        expectValue(door, "Opening, in progress", in: app)
        XCTAssertFalse(disc.isEnabled, "the arc stands in: a tap does nothing")
        set("open", in: app)
        expectValue(door, "Open", in: app, timeout: 8)
        XCTAssertTrue(disc.isEnabled, "the disc returns")
        keepScreenshot(app, "state-tile-resting-\(layout)")
    }

    /// In-progress to in-progress keeps the same disc element: the words change, the slot is not remade.
    func testInProgressToInProgressKeepsTheSameElement() {
        let app = launch()
        set("opening", in: app)
        expectValue(door, "Opening, in progress", in: app)
        let before = element(door, in: app).frame
        set("closing", in: app)
        expectValue(door, "Closing, in progress", in: app, timeout: 8)
        XCTAssertEqual(element(door, in: app).frame, before, "the same disc slot")
        XCTAssertFalse(element(door, in: app).isEnabled)
        keepScreenshot(app, "state-tile-in-progress-\(layout)")
    }

    /// In-progress to error: the arc leaves, the disc returns and takes taps, and the words say error.
    func testInProgressToError() {
        let app = launch()
        set("opening", in: app)
        expectValue(door, "Opening, in progress", in: app)
        set("error", in: app)
        expectValue(door, "Error", in: app, timeout: 8)
        XCTAssertTrue(element(door, in: app).isEnabled)
        keepScreenshot(app, "state-tile-error-\(layout)")
    }

    /// A state with Stop keeps its disc: no arc, so it still takes a tap.
    func testAStateWithStopKeepsItsDisc() {
        let app = launch()
        set("stop", in: app)
        expectValue(door, "Opening, in progress", in: app)
        let disc = element(door, in: app)
        XCTAssertTrue(disc.isEnabled)
        disc.tap()
        expectLastCall("door door", matching: .beginsWith, in: app)
    }

    /// A tile with no disc: the glyph gives way to the compact arc, the value says in progress, and the body still opens its page.
    func testATileWithNoDiscShowsProgressInItsValueAndStillOpens() {
        let app = launch()
        set("returning", tile: "robot", in: app)
        expectValue("stateTile.robot", "Returning, in progress", in: app)
        element("stateTile.robot", in: app).tap()
        expectLastCall("robot opened", matching: .beginsWith, in: app)
        set("paused", tile: "robot", in: app)
        expectValue("stateTile.robot", "Paused, warning", in: app, timeout: 8)
    }

    /// A warning and unknown: the warning's value ends "warning"; unknown dims the disc and ignores taps.
    func testWarningAndUnknown() {
        let app = launch()
        set("warning", in: app)
        expectValue(door, "Open, warning", in: app)
        XCTAssertTrue(element(door, in: app).isEnabled)
        set("unknown", in: app)
        expectValue(door, "Unavailable", in: app)
        XCTAssertFalse(element(door, in: app).isEnabled)
    }

    // MARK: Accessibility

    /// While the arc stands in, the tile is one button that is not enabled and says "in progress"; the disc repeats it so is hidden and the arc is none.
    func testTheArcStandingInReadsAsDisabledAndInProgress() {
        let app = launch(door: "opening")
        let disc = element(door, in: app)
        XCTAssertFalse(disc.isEnabled, "and not-enabled is added")
        XCTAssertEqual(element(door, in: app).value as? String, "Opening, in progress")
        let arcs = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ AND elementType == %d", "Loading", XCUIElement.ElementType.progressIndicator.rawValue))
        XCTAssertEqual(arcs.count, 0, "the arc is not an accessibility element")
    }

    /// At AX5 the tile reads the same (the 66 pt disc and arc are asserted by `UKHostedStateTileViewTests`).
    func testAtAX5TheTileReadsTheSame() {
        let app = launch(door: "opening", arguments: FentonHomeApp.ax5)
        XCTAssertEqual(element(door, in: app).value as? String, "Opening, in progress")
    }

    /// With Reduce Motion the states still read and the disc returns at rest: nothing is carried by motion alone.
    func testReduceMotionKeepsEveryClassReadable() {
        let app = launch(settings: [.reduceMotion])
        for (state, value) in [("opening", "Opening, in progress"), ("error", "Error"), ("warning", "Open, warning"), ("closed", "Closed")] {
            set(state, in: app)
            expectValue(door, value, in: app, timeout: 8)
        }
        XCTAssertTrue(element(door, in: app).isEnabled)
    }

    /// The page passes the audit in the in-progress look, with the AX5 relaunch.
    func testPagePassesAccessibilityAudit() throws {
        let app = launch(door: "opening")
        keepScreenshot(app, "state-tile-audit-\(layout)")
        try FentonHomeApp.audit(app) { self.launch(door: "opening", arguments: FentonHomeApp.ax5) }
    }
}
