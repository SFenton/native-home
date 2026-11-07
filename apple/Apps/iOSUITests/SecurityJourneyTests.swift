import XCTest

/// The Security page in the debug gallery (fixture state, recording service caller; nothing reaches the house):
/// the alarm card and its modes with the disarm confirmation, door tile semantics, lock and garage door commands, the
/// mode sheet the Security chip opens, audits and screenshots on iPhone, iPhone Duo and iPad. One signed-in journey
/// opens the real tab read-only (`.agents/pages/security/ios.md`).
final class SecurityJourneyTests: JourneyTestCase {
    private enum Tile {
        /// The alarm card's header: the mode as its value.
        static let alarm = "security.system.state"
        static let frontDoor = "security.tile.\(JourneyExpectations.gallery[.securityFrontDoorLock])"
        static let left = "security.tile.\(JourneyExpectations.gallery[.securityGarageLeft])"
        static let right = "security.tile.\(JourneyExpectations.gallery[.securityGarageRight])"
        static let vehicle = "security.tile.\(JourneyExpectations.gallery[.securityVehicleLock])"
    }

    // MARK: - Helpers

    /// - Parameter fresh: Relaunches the process instead of resetting the resident app (``AppReuse``): the capture test
    ///   terminates the app between poses on purpose.
    private func launch(arguments: [String] = [], environment: [String: String] = [:], fresh: Bool = false) -> XCUIApplication {
        let configured = FentonHomeApp.makeApp()
        configured.launchEnvironment["FENTON_GALLERY"] = "security"
        configured.launchEnvironment.merge(environment) { _, new in new }
        configured.launchArguments += arguments
        let app: XCUIApplication
        if fresh {
            configured.launch()
            app = configured
        } else {
            app = startApp(configured)
        }
        XCTAssertTrue(alarm(in: app).appears(timeout: 30), "Security page did not appear")
        return app
    }

    /// Waits for the alarm card to read `mode` (its value goes on with when the mode began, "Since 9:30 PM").
    private func expectAlarm(_ mode: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let element = alarm(in: app)
        let predicate = NSPredicate(format: "value BEGINSWITH %@", mode)
        let matched = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: 10) == .completed
        XCTAssertTrue(matched, "Alarm reads '\(element.value ?? "nil")', expected '\(mode)'", file: file, line: line)
    }

    /// The alarm card's header (not a button: the modes under it are).
    private func alarm(in app: XCUIApplication) -> XCUIElement {
        element(Tile.alarm, in: app)
    }

    /// A door tile is an action tile whose disc carries the state, so it is a toggle-styled button (a switch to XCUITest): look
    /// it up by identifier, whatever its type (`.agents/patterns/action-tiles.md`).
    private func tile(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    private func expectCall(_ expected: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let label = app.staticTexts["gallery.lastCall"].firstMatch
        let matched = label.wait(for: \.label, toEqual: "Last call: \(expected)", timeout: 10)
        XCTAssertTrue(matched, "Last call was '\(label.label)'", file: file, line: line)
    }

    private func expectValue(_ element: XCUIElement, _ value: String, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "value == %@", value)
        let matched = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout) == .completed
        XCTAssertTrue(matched, "\(element.label) value is '\(element.value ?? "nil")', expected '\(value)'", file: file, line: line)
    }

    /// Scrolls the page until `element` can be tapped (AX5 and the folded Duo push tiles below the fold).
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let scroll = app.scrollViews["security.scroll"].firstMatch
        // The gallery's Last call bar floats over the foot of the page: a control under it reports hittable, but a tap
        // lands on the bar (the AX5 disarm alert never opened on iPhone, 2026-10-16).
        let bar = app.staticTexts["gallery.lastCall"].firstMatch
        // One element snapshot per drag; `isHittable` only once the frame is above the bar. Three drags that do not move
        // the element end the loop.
        var barTop: CGFloat?
        var lastMinY: CGFloat?
        var stuck = 0
        for _ in 0..<8 {
            let frame = (try? element.snapshot())?.frame
            if let frame, !frame.isEmpty {
                if barTop == nil { barTop = (try? bar.snapshot())?.frame.minY ?? .infinity }
                if frame.maxY <= (barTop ?? .infinity) + 1, element.isHittable { return }
                if let lastMinY, abs(frame.minY - lastMinY) < 1 { stuck += 1 } else { stuck = 0 }
                lastMinY = frame.minY
                if stuck >= 3 { break }
            }
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.75))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -200)))
        }
        XCTAssertTrue(element.isHittable, "\(element) never came into view")
    }

    /// Opens the mode sheet from the Security chip.
    private func openSystemSheet(_ app: XCUIApplication) {
        app.buttons["security.chip.security"].tap()
        let title = app.navigationBars["Security System"]
        XCTAssertTrue(title.appears(timeout: 10), "Security system sheet did not open")
        XCTAssertTrue(app.buttons["Close"].firstMatch.wait(for: \.isHittable, toEqual: true, timeout: 10))
        settleScreen() // Mid-animation frames fail contrast and clipping.
    }

    // MARK: - Door tiles

    /// The alarm card names the mode; every door tile is a named 44 pt+ button whose value is its state.
    func testRowsNameTheirState() {
        let app = launch()
        XCTAssertEqual(alarm(in: app).label, "Security System")
        expectAlarm("Armed Home", in: app)
        XCTAssertNotEqual(alarm(in: app).elementType, .button, "The card header is not a control")
        let expected = [
            (Tile.frontDoor, "Front Door", "Locked"),
            (Tile.left, "Left Door", "Closed"),
            (Tile.right, "Right Door", "Open"),
            (Tile.vehicle, "Doors", "Locked"),
        ]
        for (id, label, value) in expected {
            let element = tile(id, in: app)
            reveal(element, in: app)
            XCTAssertEqual(element.label, label)
            XCTAssertEqual(element.value as? String, value, label)
            assertTarget(element)
        }
        XCTAssertTrue(app.staticTexts["Doors"].exists && app.staticTexts["Mach-E"].exists, "Section headers")
        XCTAssertTrue(app.buttons["security.chip.security"].exists)
        XCTAssertTrue(app.buttons["security.chip.contacts"].exists)
    }

    /// The front door unlocks then locks with explicit services, never `toggle`.
    func testFrontDoorLockSendsExplicitServices() {
        let app = launch()
        let door = tile(Tile.frontDoor, in: app)
        door.tap()
        expectCall("lock.unlock entity_id=\(expectations[.securityFrontDoorLock])", in: app)
        expectValue(door, "Unlocked")
        door.tap()
        expectCall("lock.lock entity_id=\(expectations[.securityFrontDoorLock])", in: app)
        expectValue(door, "Locked")
    }

    /// The open right door: "Sending Close…" at once, then the door's own Closing and Closed.
    func testGarageDoorShowsSendingThenFollowsTheDoor() {
        let app = launch()
        let door = tile(Tile.right, in: app)
        reveal(door, in: app)
        door.tap()
        expectValue(door, "Sending Close…", timeout: 3)
        expectCall("cover.close_cover entity_id=\(expectations[.securityGarageRight])", in: app)
        expectValue(door, "Closing")
        expectValue(door, "Closed")
    }

    /// A failed call shows Error on the tile.
    func testGarageDoorShowsErrorWhenTheCallFails() {
        let app = launch(environment: ["FENTON_GALLERY_FAIL": "1"])
        let door = tile(Tile.left, in: app)
        reveal(door, in: app)
        door.tap()
        expectValue(door, "Error")
    }

    // MARK: - Alarm card

    /// The card's modes show the current one as selected; arming sends at once, disarming asks first and Cancel sends
    /// nothing.
    func testModesArmAtOnceAndDisarmConfirms() {
        let app = launch()
        let home = app.buttons["security.mode.armed_home"]
        XCTAssertTrue(home.isSelected, "The current mode is selected")
        XCTAssertEqual(app.buttons["security.mode.disarmed"].label, "Disarm")
        for mode in ["armed_home", "armed_away", "armed_night", "disarmed"] { assertTarget(app.buttons["security.mode.\(mode)"]) }

        let night = app.buttons["security.mode.armed_night"]
        night.tap()
        expectCall("alarm_control_panel.alarm_arm_night entity_id=\(expectations[.securityAlarm])", in: app)
        XCTAssertTrue(night.wait(for: \.isSelected, toEqual: true, timeout: 5))

        let disarm = app.buttons["security.mode.disarmed"]
        disarm.tap()
        let alert = app.alerts["Disarm the Security System?"]
        XCTAssertTrue(alert.appears(timeout: 5), "Disarming asks first")
        alert.buttons["Cancel"].firstMatch.tap()
        XCTAssertTrue(alert.disappears(timeout: 5))
        expectCall("alarm_control_panel.alarm_arm_night entity_id=\(expectations[.securityAlarm])", in: app)

        disarm.tap()
        XCTAssertTrue(alert.appears(timeout: 5))
        alert.buttons["Disarm"].firstMatch.tap()
        expectCall("alarm_control_panel.alarm_disarm entity_id=\(expectations[.securityAlarm])", in: app)
        XCTAssertTrue(disarm.wait(for: \.isSelected, toEqual: true, timeout: 5))
        expectAlarm("Disarmed", in: app)
    }

    /// The Security chip opens the same card in a sheet, which arms too.
    func testSecurityChipOpensTheModeSheet() {
        let app = launch()
        openSystemSheet(app)
        let sheet = app.navigationBars["Security System"]
        XCTAssertTrue(sheet.exists)
        let away = app.buttons.matching(identifier: "security.mode.armed_away").allElementsBoundByIndex.last { $0.isHittable }
        XCTAssertNotNil(away, "The sheet's Away mode is reachable")
        away?.tap()
        expectCall("alarm_control_panel.alarm_arm_away entity_id=\(expectations[.securityAlarm])", in: app)
        app.buttons["Close"].firstMatch.tap()
        expectAlarm("Armed Away", in: app)
    }

    /// The Contact Sensors chip opens the rooms (web `ContactSheet`), and a room pushes its doors and windows.
    func testContactChipOpensTheList() {
        let app = launch()
        app.buttons["security.chip.contacts"].tap()
        let entryway = app.buttons["overview.contacts.room.Entryway"]
        XCTAssertTrue(entryway.appears(timeout: 10))
        entryway.tap()
        XCTAssertTrue(app.navigationBars["Entryway Contact Sensors"].appears(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["room.entity.binary_sensor.front_door_contact_sensor_contact"].exists)
        app.buttons["Close"].firstMatch.tap()
    }

    // MARK: - Contact Sensors chip

    /// The Contact Sensors chip tells the house apart (owner, 2026-10-16): all closed, open with someone home, open while
    /// away, open while the system is armed. Each state is a distinct chip whose text keeps 4.5:1 as rendered, and the
    /// page passes the audit at default and AX5 size.
    private func checkContactChip(_ scenario: String, reads summary: String) throws {
        let environment = ["FENTON_GALLERY_SCENARIO": scenario, "FENTON_GALLERY_CLEAN": "1"]
        let app = launch(environment: environment)
        let chip = app.buttons["security.chip.contacts"]
        XCTAssertTrue(chip.appears(timeout: 10))
        XCTAssertEqual(chip.label, "Contact Sensors, \(summary)", scenario)
        assertTarget(chip)
        settleScreen() // The colour cross-fade settles before it is measured.
        if let capture = RenderedContrast.Capture.screen(), let ratio = RenderedContrast.ratio(of: chip.frame, in: capture) {
            XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(scenario) chip text measured \(ratio):1")
        }
        keepScreenshot(app, "security-contact-\(scenario)-\(layout)")
        try FentonHomeApp.audit(app) { self.launch(arguments: FentonHomeApp.ax5, environment: environment) }
    }

    func testContactChipAllClosed() throws { try checkContactChip("standard", reads: "All Closed") }
    func testContactChipOpenAtHome() throws { try checkContactChip("openHome", reads: "1 Open") }
    func testContactChipOpenWhileAway() throws { try checkContactChip("openAway", reads: "1 Open") }
    func testContactChipOpenWhileArmed() throws { try checkContactChip("openArmed", reads: "1 Open") }

    // MARK: - Audits

    func testPagePassesAccessibilityAudit() throws {
        let app = launch()
        try FentonHomeApp.audit(app) { self.launch(arguments: FentonHomeApp.ax5) }
    }

    /// Unavailable tiles and modes are disabled and say so, and their text keeps 4.5:1: only the glyphs dim (the
    /// signed-in tab shows this before states arrive).
    func testSecurityUnavailableReadsDisabled() throws {
        let app = launch(environment: Self.unavailable)
        XCTAssertEqual(alarm(in: app).value as? String, "Unavailable")
        XCTAssertFalse(app.buttons["security.mode.armed_home"].isEnabled, "Modes are disabled")
        for id in [Tile.frontDoor, Tile.left, Tile.right] {
            let element = tile(id, in: app)
            reveal(element, in: app)
            XCTAssertEqual(element.value as? String, "Unavailable", id)
            XCTAssertFalse(element.isEnabled, "\(id) is disabled")
        }
    }

    func testSecurityUnavailablePassesAccessibilityAudit() throws {
        let app = launch(environment: Self.unavailable)
        XCTAssertEqual(alarm(in: app).value as? String, "Unavailable")
        try FentonHomeApp.audit(app) { self.launch(arguments: FentonHomeApp.ax5, environment: Self.unavailable) }
        keepScreenshot(app, "security-unavailable-\(layout)")
    }

    private static let unavailable = ["FENTON_GALLERY_SCENARIO": "unavailable"]

    /// A sounding alarm reddens the card; its white and secondary text keep 4.5:1 on the red wash.
    func testTriggeredCardPassesAccessibilityAudit() throws {
        let triggered = ["FENTON_GALLERY_SCENARIO": "triggered"]
        let app = launch(environment: triggered)
        expectAlarm("Alarm Triggered", in: app)
        XCTAssertFalse(app.buttons["security.mode.armed_home"].isSelected, "No mode is selected while triggered")
        try FentonHomeApp.audit(app) { self.launch(arguments: FentonHomeApp.ax5, environment: triggered) }
        keepScreenshot(app, "security-triggered-\(layout)")
    }

    func testSystemSheetPassesAccessibilityAudit() throws {
        let app = launch()
        openSystemSheet(app)
        try FentonHomeApp.audit(app) {
            let large = self.launch(arguments: FentonHomeApp.ax5)
            self.openSystemSheet(large)
            return large
        }
    }

    func testDisarmAlertPassesAccessibilityAudit() throws {
        let app = launch()
        app.buttons["security.mode.disarmed"].firstMatch.tap()
        XCTAssertTrue(app.alerts.firstMatch.appears(timeout: 5))
        settleScreen()
        // The system alert's labels report "partially unsupported"; the AX5 relaunch proves they grow.
        try FentonHomeApp.audit(app) {
            let large = self.launch(arguments: FentonHomeApp.ax5)
            let disarm = large.buttons["security.mode.disarmed"].firstMatch
            self.reveal(disarm, in: large)
            disarm.tap()
            if !large.alerts.firstMatch.appears(timeout: 5) { self.keepScreenshot(large, "disarm-alert-missing-\(self.layout)") }
            XCTAssertTrue(large.alerts.firstMatch.exists, "The disarm alert did not appear at AX5")
            settleScreen()
            return large
        }
    }

    // MARK: - Signed in

    /// The real Security tab, read-only (no control is pressed against the house): tiles exist and the page passes
    /// the audit. Skips without credentials.
    func testSecurityTabLiveReadsTiles() throws {
        // The ids come from the run's own expectations (the private file on the owner's house, DemoHouse on the test
        // instance), never from the gallery's DemoHouse values; without either the journey skips.
        let live = try JourneyExpectations.current(for: .signedIn)
        let doors = try [live.value(.securityFrontDoorLock), live.value(.securityGarageLeft), live.value(.securityGarageRight)]
            .map { "security.tile.\($0)" }
        let vehicle = try "security.tile.\(live.value(.securityVehicleLock))"
        let app = try FentonHomeApp.launchSignedIn()
        showSecurityTab(app)
        XCTAssertTrue(alarm(in: app).appears(timeout: 10), "Alarm card")
        for id in doors {
            // Door tiles are action tiles whose disc carries the state (a switch to XCUITest), so look up by identifier, not as buttons.
            XCTAssertTrue(tile(id, in: app).appears(timeout: 10), id)
        }
        XCTAssertFalse(tile(vehicle, in: app).exists, "Vehicle stays hidden like the web")
    }

    func testSecurityTabLivePassesAccessibilityAudit() throws {
        let app = try FentonHomeApp.launchSignedIn()
        showSecurityTab(app)
        try FentonHomeApp.audit(app) {
            let large = try FentonHomeApp.launchSignedIn(arguments: FentonHomeApp.ax5)
            self.showSecurityTab(large)
            return large
        }
        keepScreenshot(app, "security-live-\(FentonHomeApp.family)")
    }

    private func showSecurityTab(_ app: XCUIApplication) {
        openSection("security", title: "Security", in: app)
        XCTAssertTrue(alarm(in: app).appears(timeout: 10), "Security page did not appear")
    }

    // MARK: - Screenshots

    /// The pose a capture runs in: `.upright` is the family's own pose (iPad: portrait, set first), `.iPadLandscape`
    /// is iPad only and skips elsewhere before any launch.
    private enum Pose { case upright, iPadLandscape }

    private func enter(_ pose: Pose) throws -> String {
        switch pose {
        case .upright:
            guard FentonHomeApp.family == .iPad else { return "current" }
            FentonHomeApp.target().terminate()
            XCUIDevice.shared.orientation = .portrait
            return "portrait"
        case .iPadLandscape:
            try XCTSkipUnless(FentonHomeApp.family == .iPad, "iPad landscape only")
            addTeardownBlock { XCUIDevice.shared.orientation = .portrait }
            FentonHomeApp.target().terminate()
            XCUIDevice.shared.orientation = .landscapeLeft
            return "landscape"
        }
    }

    private func cleanPage() -> XCUIApplication {
        let app = launch(environment: ["FENTON_GALLERY_CLEAN": "1"], fresh: true)
        settleScreen()
        return app
    }

    private func capturePage(_ pose: Pose) throws {
        let suffix = try enter(pose)
        keepScreenshot(cleanPage(), "security-\(suffix)")
    }

    private func captureSystemSheet(_ pose: Pose) throws {
        let suffix = try enter(pose)
        let app = cleanPage()
        openSystemSheet(app)
        keepScreenshot(app, "security-system-\(suffix)")
        app.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Security System"].disappears(timeout: 5))
    }

    private func captureDisarmAlert(_ pose: Pose) throws {
        let suffix = try enter(pose)
        let app = cleanPage()
        app.buttons["security.mode.disarmed"].firstMatch.tap()
        XCTAssertTrue(app.alerts.firstMatch.appears(timeout: 5))
        settleScreen()
        keepScreenshot(app, "security-disarm-\(suffix)")
        app.alerts.firstMatch.buttons["Cancel"].firstMatch.tap()
    }

    private func captureGarageSending(_ pose: Pose) throws {
        let suffix = try enter(pose)
        let app = cleanPage()
        let right = tile(Tile.right, in: app)
        reveal(right, in: app)
        right.tap()
        expectValue(right, "Sending Close…", timeout: 3)
        keepScreenshot(app, "security-garage-sending-\(suffix)")
    }

    private func captureGarageError(_ pose: Pose) throws {
        let suffix = try enter(pose)
        let failing = launch(environment: ["FENTON_GALLERY_CLEAN": "1", "FENTON_GALLERY_FAIL": "1"], fresh: true)
        let door = tile(Tile.left, in: failing)
        reveal(door, in: failing)
        door.tap()
        expectValue(door, "Error")
        keepScreenshot(failing, "security-garage-error-\(suffix)")
    }

    /// The page, the mode sheet, the disarm confirmation, a garage door sending and failing: one test per screen
    /// (`testCaptureSecurity<Name>`), each in the upright pose, plus an `InIPadLandscape` twin that skips off iPad.
    func testCaptureSecurityPage() throws { try capturePage(.upright) }
    func testCaptureSecurityPageInIPadLandscape() throws { try capturePage(.iPadLandscape) }
    func testCaptureSecuritySystemSheet() throws { try captureSystemSheet(.upright) }
    func testCaptureSecuritySystemSheetInIPadLandscape() throws { try captureSystemSheet(.iPadLandscape) }
    func testCaptureSecurityDisarmAlert() throws { try captureDisarmAlert(.upright) }
    func testCaptureSecurityDisarmAlertInIPadLandscape() throws { try captureDisarmAlert(.iPadLandscape) }
    func testCaptureSecurityGarageSending() throws { try captureGarageSending(.upright) }
    func testCaptureSecurityGarageSendingInIPadLandscape() throws { try captureGarageSending(.iPadLandscape) }
    func testCaptureSecurityGarageError() throws { try captureGarageError(.upright) }
    func testCaptureSecurityGarageErrorInIPadLandscape() throws { try captureGarageError(.iPadLandscape) }
}
