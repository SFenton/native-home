import XCTest

/// The location permission screen in the debug gallery (`FENTON_GALLERY=location`): the pre-alert steps (one
/// Continue, no Close), the status stages (Close, Open Settings), names, values, targets, and the accessibility
/// audit at the default and AX5 text sizes for every stage, with screenshots, on iPhone, iPhone Duo and iPad
/// (`.agents/pages/settings/location.md`).
@MainActor
final class LocationJourneyTests: JourneyTestCase {
    private func launch(_ stage: String, arguments: [String] = []) -> XCUIApplication {
        let app = FentonHomeApp.makeApp()
        app.launchEnvironment["FENTON_GALLERY"] = "location"
        app.launchEnvironment["FENTON_GALLERY_LOCATION"] = stage
        app.launchArguments += arguments
        app.launch()
        XCTAssertTrue(app.staticTexts["location.title"].appears(timeout: 15), "The location screen did not open")
        return app
    }

    private func lastAction(_ app: XCUIApplication) -> String {
        app.staticTexts["gallery.lastCall"].firstMatch.label
    }

    private func status(_ app: XCUIApplication) -> String {
        element("location.status", in: app).value as? String ?? ""
    }

    /// On the unfolded Duo in landscape the page sheet is centred across the hinge, so the content uses the wider side of it
    /// (`clearsHinge`); elsewhere it is centred as before. The band is the simulator measurement, 455.3 to 495.7 pt.
    func testContentStaysOffTheUnfoldedDuoHinge() {
        let app = launch("not-determined")
        let window = app.windows.firstMatch.frame
        guard FentonHomeApp.family == .iPhoneDuo, window.width > window.height, window.width >= 900 else { return }
        let title = app.staticTexts["location.title"]
        let primary = app.buttons["location.primary"]
        for element in [title, primary] {
            XCTAssertTrue(element.frame.maxX <= 456 || element.frame.minX >= 495, "\(element.identifier) crosses the hinge: \(element.frame)")
        }
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "location-duo-hinge"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// The first screen asks with one Continue and offers no other way out (HIG Privacy, Pre-alert screens).
    func testFirstStepIsAPreAlertScreen() {
        let app = launch("not-determined")
        XCTAssertEqual(app.staticTexts["location.title"].label, "Know When You're Home")
        XCTAssertTrue(app.navigationBars["Location Settings"].exists, "One bar title for the Location view everywhere")
        let statusRow = element("location.status", in: app)
        XCTAssertEqual(statusRow.label, "Location Access")
        XCTAssertEqual(status(app), "Not Set")
        let primary = app.buttons["location.primary"]
        XCTAssertEqual(primary.label, "Continue")
        assertTarget(primary)
        XCTAssertFalse(app.buttons["location.close"].exists, "A pre-alert screen has no Close")
        for symbol in ["figure.walk.arrival", "lock.shield", "battery.75percent"] {
            let point = element("location.point.\(symbol)", in: app)
            XCTAssertTrue(point.exists, symbol)
            XCTAssertFalse(point.label.isEmpty, "\(symbol) reads its title and detail")
        }
        XCTAssertTrue(point(app, "figure.walk.arrival").label.hasPrefix("Arrivals and Departures"))
    }

    private func point(_ app: XCUIApplication, _ symbol: String) -> XCUIElement {
        element("location.point.\(symbol)", in: app)
    }

    /// Continue leads through While Using to Always; each step starts at its own gallery stage (the gallery plays the
    /// system's answer, so `when-in-use` is where the first Continue lands).
    func testLocationContinueFromNotDetermined() {
        let app = launch("not-determined")
        app.buttons["location.primary"].tap()
        XCTAssertEqual(lastAction(app), "Last action: request not-determined")
        XCTAssertTrue(app.staticTexts["Notice When You Leave"].appears(timeout: 5))
        XCTAssertEqual(status(app), "While Using the App")
        XCTAssertFalse(app.buttons["location.close"].exists)
    }

    func testLocationContinueFromWhileUsing() {
        let app = launch("when-in-use")
        app.buttons["location.primary"].tap()
        XCTAssertEqual(lastAction(app), "Last action: request when-in-use")
        XCTAssertTrue(app.staticTexts["Home and Away Are On"].appears(timeout: 5))
        XCTAssertEqual(status(app), "Always")
        XCTAssertFalse(app.buttons["location.primary"].exists, "Nothing left to do")
        XCTAssertTrue(app.buttons["location.close"].exists)
    }

    /// The finished screen gains Close and loses the button.
    func testLocationContinueCloseFromAlways() {
        let app = launch("always")
        XCTAssertTrue(app.staticTexts["Home and Away Are On"].exists)
        XCTAssertFalse(app.buttons["location.primary"].exists, "Nothing left to do")
        let close = app.buttons["location.close"]
        XCTAssertTrue(close.exists)
        XCTAssertEqual(close.label, "Close")
        close.tap()
        XCTAssertEqual(lastAction(app), "Last action: close")
    }

    /// Off and Approximate send the person to Settings, and say why.
    private func assertOpensSettings(_ stage: String, title: String, value: String) {
        let app = launch(stage)
        XCTAssertEqual(app.staticTexts["location.title"].label, title)
        XCTAssertEqual(status(app), value)
        let primary = app.buttons["location.primary"]
        XCTAssertEqual(primary.label, "Open Settings")
        assertTarget(primary)
        primary.tap()
        XCTAssertEqual(lastAction(app), "Last action: open settings")
        XCTAssertTrue(app.buttons["location.close"].exists)
    }

    func testLocationDeniedOpensSettings() {
        assertOpensSettings("denied", title: "Location Is Off", value: "Off")
    }

    func testLocationReducedAccuracyOpensSettings() {
        assertOpensSettings("reduced-accuracy", title: "Precise Location Is Off", value: "Always, Approximate")
    }

    /// While Using after iOS showed its one Always alert: Settings instead of Continue, and Close is back.
    func testWhileUsingAfterTheAlwaysAlertOffersSettings() {
        let app = launch("when-in-use-asked")
        XCTAssertEqual(app.staticTexts["location.title"].label, "Notice When You Leave")
        XCTAssertEqual(status(app), "While Using the App")
        let primary = app.buttons["location.primary"]
        XCTAssertEqual(primary.label, "Open Settings")
        assertTarget(primary)
        let close = app.buttons["location.close"]
        // The system's toolbar Close (`SheetCloseItem`); the bar sizes its hit region, as on every sheet.
        XCTAssertTrue(close.exists, "No longer a pre-alert screen")
        primary.tap()
        XCTAssertEqual(lastAction(app), "Last action: open settings")
    }

    /// A stage passes the audit at the default size and grows at AX5, with a screenshot of each.
    private func assertStagePassesAudit(_ stage: String) throws {
        let app = launch(stage, arguments: [])
        keepScreenshot(app, "location-\(stage)-\(layout)")
        try FentonHomeApp.audit(app) { self.launch(stage, arguments: FentonHomeApp.ax5) }
        let large = launch(stage, arguments: FentonHomeApp.ax5)
        keepScreenshot(large, "location-\(stage)-ax5-\(layout)")
        let primary = large.buttons["location.primary"]
        if primary.exists {
            // Reachable at AX5: the action ends the scrolling content.
            for _ in 0..<12 where !primary.isHittable { large.swipeUp() }
            XCTAssertTrue(primary.isHittable, "\(stage): the action is out of reach at AX5")
        }
        large.terminate()
    }

    func testLocationNotDeterminedPassesAccessibilityAudit() throws { try assertStagePassesAudit("not-determined") }
    func testLocationWhenInUsePassesAccessibilityAudit() throws { try assertStagePassesAudit("when-in-use") }
    func testLocationWhenInUseAskedPassesAccessibilityAudit() throws { try assertStagePassesAudit("when-in-use-asked") }
    func testLocationAlwaysPassesAccessibilityAudit() throws { try assertStagePassesAudit("always") }
    func testLocationDeniedPassesAccessibilityAudit() throws { try assertStagePassesAudit("denied") }
    func testLocationReducedAccuracyPassesAccessibilityAudit() throws { try assertStagePassesAudit("reduced-accuracy") }
}

/// Shadow-mode location after a real sign-in (`.agents/platforms/apple/location.md`): every device offers the permission
/// screen once, as the Location step of the Setup flow, and walks the real system alerts to Always (an iPad reports to its
/// own device but is never linked to a person, 2026-10-27). The launch never
/// registers (a test token keeps `mobile_app` registration off), so nothing reaches Home Assistant.
@MainActor
final class LocationShadowJourneyTests: JourneyTestCase {
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    private func launchSignedIn() throws -> XCUIApplication {
        FentonHomeApp.target().resetAuthorizationStatus(for: .location)
        return try FentonHomeApp.launchSignedIn(environment: ["FENTON_LOCATION": "1"], readyIdentifier: "location.title")
    }

    /// Taps the system alert button whose label contains `text`.
    private func answerAlert(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        let button = springboard.buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        XCTAssertTrue(button.appears(timeout: 15), "No system alert offering \(text)", file: file, line: line)
        button.tap()
    }

    func testEveryDeviceOffersLocationAfterSignIn() throws {
        let app = try launchSignedIn()
        XCTAssertEqual(app.staticTexts["location.title"].label, "Know When You're Home")
        XCTAssertFalse(app.buttons["location.close"].exists, "A pre-alert screen has no Close")
        keepScreenshot(app, "location-shadow-1-ask-\(layout)")

        app.buttons["location.primary"].tap()
        answerAlert("While Using")
        XCTAssertTrue(app.staticTexts["Notice When You Leave"].appears(timeout: 10))
        XCTAssertEqual(element("location.status", in: app).value as? String, "While Using the App")
        keepScreenshot(app, "location-shadow-2-while-using-\(layout)")

        app.buttons["location.primary"].tap()
        answerAlert("Always")
        XCTAssertTrue(app.staticTexts["Home and Away Are On"].appears(timeout: 10))
        keepScreenshot(app, "location-shadow-3-always-\(layout)")
        let close = app.buttons["location.close"]
        XCTAssertTrue(close.exists)
        close.tap()
        XCTAssertTrue(app.buttons["home.chip.lights"].appears(timeout: 10))
        XCTAssertFalse(app.staticTexts["location.title"].exists)
        keepScreenshot(app, "location-shadow-4-home-\(layout)")
    }
}

/// The Account sheet's Location section after a real sign-in (`.agents/pages/settings/location.md`, Entry points):
/// Share Location shows the permission and opens the permission screen on every device (an iPad too, since 2026-10-27),
/// and there is no Report switch: access off warns that nothing is sent. The launch never registers (a test token and
/// the simulator keep `mobile_app` registration off), so nothing reaches Home Assistant.
@MainActor
final class LocationAccountJourneyTests: JourneyTestCase {
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    /// Signs in with location on; the first launch waits for the after-sign-in offer, later ones skip it.
    private func launchSignedIn(arguments: [String] = [], first: Bool) throws -> XCUIApplication {
        let environment = ["FENTON_LOCATION": "1"]
        return try FentonHomeApp.launchSignedIn(arguments: arguments, environment: environment,
                                                readyIdentifier: first ? "location.title" : nil)
    }

    /// Signs in again (location already answered, so no offer) and opens the Account sheet.
    private func relaunchToAccount(arguments: [String] = [], first: Bool = false) throws -> XCUIApplication {
        let app = try launchSignedIn(arguments: arguments, first: first)
        app.openAccountSheet()
        return app
    }

    /// Resets the permission and signs in on the after-sign-in offer (the four-tab shell offers it first).
    private func launchAtOffer() throws -> XCUIApplication {
        FentonHomeApp.target().resetAuthorizationStatus(for: .location)
        return try launchSignedIn(first: true)
    }

    /// Declines the system alert and closes the permission screen it leaves ("Location Is Off").
    private func declineAndClose(_ app: XCUIApplication) {
        app.buttons["location.primary"].tap()
        let decline = springboard.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Don'")).firstMatch
        XCTAssertTrue(decline.appears(timeout: 15), "No system location alert")
        decline.tap()
        XCTAssertTrue(app.staticTexts["Location Is Off"].appears(timeout: 10))
        app.buttons["location.close"].tap()
    }

    /// The shared prelude of the Account tests: a declined permission (simulator state, so each test makes its own), then
    /// the Account sheet.
    private func accountWithLocationOff() throws -> XCUIApplication {
        let app = try launchAtOffer()
        declineAndClose(app)
        app.openAccountSheet()
        return app
    }

    /// The offer comes first; declining the system alert leaves Location Is Off.
    func testLocationAccountOfferAndDeclineAlert() throws {
        let app = try launchAtOffer()
        keepScreenshot(app, "location-account-0-offer-\(layout)")
        declineAndClose(app)
    }

    /// Share Location shows the permission, has no Report switch, and access off warns that nothing is sent.
    func testLocationAccountRowAndWarning() throws {
        let app = try accountWithLocationOff()
        let row = app.buttons["account.location"]
        XCTAssertTrue(row.appears(timeout: 5), "No Share Location row")
        XCTAssertEqual(row.label, "Share Location")
        XCTAssertEqual(row.value as? String, "Off")
        XCTAssertGreaterThanOrEqual(row.frame.height, 44)
        XCTAssertFalse(app.switches["account.location.report"].exists, "Reporting has no switch: it follows the permission")
        let warning = app.descendants(matching: .any)["account.location.warning"]
        XCTAssertTrue(warning.appears(timeout: 5), "Access off says nothing is sent")
        XCTAssertTrue(warning.label.hasPrefix("Warning: Location access is off"), warning.label)
        keepScreenshot(app, "location-account-1-off-\(layout)")
    }

    /// The Account sheet with the warning passes the audit at the default size and AX5.
    func testLocationAccountSheetAudit() throws {
        let app = try accountWithLocationOff()
        XCTAssertTrue(app.descendants(matching: .any)["account.location.warning"].appears(timeout: 5))
        try FentonHomeApp.audit(app) { try self.relaunchToAccount(arguments: FentonHomeApp.ax5) }
        let large = try relaunchToAccount(arguments: FentonHomeApp.ax5)
        keepScreenshot(large, "location-account-2-armed-ax5-\(layout)")
        large.terminate()
    }

    /// Share Location opens the permission screen at its current stage; Close comes back to Account.
    func testLocationAccountShareLocationScreen() throws {
        let app = try accountWithLocationOff()
        app.buttons["account.location"].tap()
        XCTAssertTrue(app.staticTexts["location.title"].appears(timeout: 5), "Share Location did not open")
        XCTAssertEqual(app.staticTexts["location.title"].label, "Location Is Off")
        XCTAssertTrue(app.navigationBars["Location Settings"].exists, "The pushed page takes the same title")
        keepScreenshot(app, "location-account-3-screen-\(layout)")
        app.buttons["location.close"].tap()
        XCTAssertTrue(app.buttons["account.location"].appears(timeout: 5))
    }

    /// A sign-out the server can't confirm shows the alert and stays signed in (a stub: `FENTON_SIGNOUT_FAIL`).
    func testFailedSignOutShowsTheAlertAndStaysSignedIn() throws {
        let app = try FentonHomeApp.launchSignedIn(environment: ["FENTON_SIGNOUT_FAIL": "1"])
        app.openAccountSheet()
        let signOut = app.buttons["account.signOut"]
        XCTAssertTrue(signOut.appears(timeout: 5))
        signOut.tap()
        app.buttons["account.signOut.confirm"].firstMatch.tap()
        XCTAssertTrue(app.alerts["Sign Out couldn't complete. Try again."].appears(timeout: 5), "No failure alert")
        app.alerts["Sign Out couldn't complete. Try again."].buttons["OK"].firstMatch.tap()
        XCTAssertTrue(app.buttons["account.signOut"].exists, "Still signed in")
    }
}
