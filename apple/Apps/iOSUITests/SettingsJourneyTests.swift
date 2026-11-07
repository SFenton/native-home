import XCTest

/// Profile → Account → Settings → Home Assistant settings modal: audit, account details, the signed-in web pages
/// and Sign Out, on every device family.
@MainActor
final class SettingsJourneyTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
        // `FENTON_UITEST_ORIENTATION=landscape` runs the journeys in iPad landscape (XCUIDevice can't
        // rotate the iPhone Duo; set its pose in Device Hub instead).
        if FentonHomeApp.family == .iPad, ProcessInfo.processInfo.environment["FENTON_UITEST_ORIENTATION"] == "landscape" {
            XCUIDevice.shared.orientation = .landscapeLeft
        }
    }

    override func tearDown() {
        if FentonHomeApp.family == .iPad { XCUIDevice.shared.orientation = .portrait }
    }

    /// Goes to Settings, the last tab (owner, 2026-10-16).
    private func goToSettings(_ app: XCUIApplication) {
        app.openAccountSettings()
    }

    /// Selects Settings and waits for its Home Assistant row, scrolled into view: it ends the topic list,
    /// below the fold on iPhone, and a `List` only exposes rows it has laid out.
    private func showSettingsTab(_ app: XCUIApplication) {
        goToSettings(app)
        XCTAssertTrue(app.navigationBars["Settings"].appears(timeout: 5))
        XCTAssertTrue(homeAssistantRow(app).exists)
    }

    /// The Home Assistant row, scrolled into view: it sits below the household topics, which push it off
    /// screen at AX5, and a `List` only exposes rows it has laid out.
    private func homeAssistantRow(_ app: XCUIApplication) -> XCUIElement {
        let row = app.buttons["settings.homeAssistant"]
        // Wait for the list, not a topic: at AX5 the first rows fill the sheet, so the admin topic isn't laid out yet
        // and waiting on it skipped the scroll (folded Duo, 2026-10-14).
        guard app.descendants(matching: .any)["settings.list"].appears(timeout: 5) || row.exists else { return row }
        for _ in 0..<12 where !(row.exists && row.isHittable) {
            app.settingsList.swipeUp(velocity: .slow)
        }
        if !row.exists { _ = row.appears(timeout: 2) }
        return row
    }

    /// Scrolls the modal until `element` can be tapped (the folded iPhone Duo's form is taller than
    /// its screen, and a `Form` only exposes rows it has laid out).
    @discardableResult
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) -> XCUIElement {
        for _ in 0..<6 where !(element.exists && element.isHittable) {
            app.settingsList.swipeUp()
        }
        return element
    }

    /// Done, scrolled back into view (the folded iPhone Duo hides the bar while the form is scrolled).
    private func doneButton(_ app: XCUIApplication) -> XCUIElement {
        let done = app.buttons["haSettings.done"]
        for _ in 0..<6 where !(done.exists && done.isHittable) { app.collectionViews.firstMatch.swipeDown() }
        return done
    }

    /// The Sign Out row, scrolled into view.
    private func signOutRow(_ app: XCUIApplication) -> XCUIElement {
        reveal(app.buttons["haSettings.signOut"], in: app)
    }

    /// Back from a web page: the bar's back button, which the folded iPhone Duo moves to its rail.
    private func goBack(_ app: XCUIApplication) {
        let back = app.buttons["BackButton"].firstMatch
        if back.exists { back.tap() } else { app.navigationBars.buttons.element(boundBy: 0).tap() }
    }

    /// Opens the modal from a signed-in launch.
    private func openSettings(_ app: XCUIApplication) {
        showSettingsTab(app)
        let row = app.buttons["settings.homeAssistant"]
        XCTAssertTrue(row.exists)
        XCTAssertGreaterThanOrEqual(row.frame.height, 43)
        row.tap()
        XCTAssertTrue(app.buttons["haSettings.done"].appears(timeout: 5))
        settleScreen() // Let the full-screen modal finish presenting.
    }

    /// A `LabeledContent` row by identifier once its label or value shows `text` (the row merges both).
    private func row(_ app: XCUIApplication, _ identifier: String, showing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier)
            .matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", text, text)).firstMatch
    }

    /// The sign-out confirmation's destructive button (the system nests a duplicate inside it).
    private func confirmButton(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(identifier: "haSettings.signOut.confirm").firstMatch
    }

    /// Cancels the confirmation: its Cancel button where the system draws one (iPad action sheets
    /// drop it, and iOS 27 anchors it as a popover that cancels on an outside tap).
    private func cancelSignOut(_ app: XCUIApplication) {
        let cancel = app.buttons["Cancel"].firstMatch
        if cancel.exists && cancel.isHittable {
            cancel.tap()
        } else {
            // An outside tap, just above the popover (below it when it sits near the top), clear of the bar's Done.
            // Not the dismiss region's own tap: inside the Account sheet there are several, and the first is the
            // sheet's, oversized around the window, so its centre fell on the popover and kept it open (iPad and
            // folded Duo, 2026-10-14).
            let popover = app.popovers.firstMatch.exists ? app.popovers.firstMatch.frame : confirmButton(app).frame
            let window = app.windows.firstMatch.frame
            let y = popover.minY > 80 ? popover.minY - 40 : min(popover.maxY + 40, window.maxY - 20)
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: popover.midX, dy: y)).tap()
        }
        XCTAssertTrue(confirmButton(app).disappears(timeout: 5), "Sign-out confirmation did not close")
    }

    /// The list scrolled back to its top: scrolled to the Home Assistant row, topics fade under the header and the audit
    /// reports that faded text as element-less contrast issues it can't attribute.
    private func scrollToTop(_ app: XCUIApplication) {
        let top = app.buttons["settings.vacation"]
        for _ in 0..<12 where !(top.exists && top.isHittable) { app.settingsList.swipeDown(velocity: .fast) }
        settleScreen()
    }

    func testSettingsTabPassesAccessibilityAudit() throws {
        let app = try FentonHomeApp.launchSignedIn()
        showSettingsTab(app)
        scrollToTop(app)
        try FentonHomeApp.audit(app) {
            let large = try FentonHomeApp.launchSignedIn(arguments: FentonHomeApp.ax5)
            self.showSettingsTab(large)
            self.scrollToTop(large)
            return large
        }
    }

    /// Opens the modal and waits for the live connection and account: the shared precondition of the modal audit.
    private func openLoadedSettings(_ app: XCUIApplication) {
        openSettings(app)
        XCTAssertTrue(row(app, "haSettings.status", showing: "Connected").appears(timeout: 15), "Connection row not live")
        XCTAssertTrue(app.descendants(matching: .any)["haSettings.role"].appears(timeout: 10), "Account did not load")
    }

    func testHaSettingsShowsServerAndAccount() throws {
        let app = try FentonHomeApp.launchSignedIn()
        openLoadedSettings(app)
        XCTAssertTrue(signOutRow(app).exists)
    }

    func testHaSettingsPassesAccessibilityAudit() throws {
        let app = try FentonHomeApp.launchSignedIn()
        openLoadedSettings(app)
        XCTAssertTrue(signOutRow(app).exists) // Audited scrolled to the Sign Out row, as before the split.
        try FentonHomeApp.audit(app) {
            let large = try FentonHomeApp.launchSignedIn(arguments: FentonHomeApp.ax5)
            self.openSettings(large)
            return large
        }
    }

    func testHaSettingsDoneClosesModal() throws {
        let app = try FentonHomeApp.launchSignedIn()
        openSettings(app)
        doneButton(app).tap()
        XCTAssertTrue(app.buttons["settings.homeAssistant"].appears(timeout: 5))
    }

    /// Home Assistant's own Settings page opens signed in (no web login form) and Back returns.
    func testHomeAssistantSettingsOpensSignedIn() throws {
        let app = try FentonHomeApp.launchSignedIn()
        openSettings(app)
        let open = app.buttons["haSettings.open.settings"]
        XCTAssertTrue(open.appears(timeout: 10))
        open.tap()
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.appears(timeout: 15))
        // The frontend's Settings dashboard lists Devices & services once signed in.
        // Any element: WebKit exposes the entry as a link labelled "Devices & services …" (iPad, 2026-10-14), and
        // `containing` only matched a text with a matching child.
        let signedIn = web.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] 'Devices'")).firstMatch
        XCTAssertTrue(signedIn.appears(timeout: 30), "Home Assistant Settings did not open signed in")
        XCTAssertFalse(web.secureTextFields.firstMatch.exists, "Web login form shown")
        goBack(app)
        XCTAssertTrue(app.buttons["haSettings.done"].appears(timeout: 5))
    }

    /// Opens the modal and the sign-out confirmation: the shared precondition of the sign-out tests.
    private func presentSignOutConfirmation(_ app: XCUIApplication) {
        openSettings(app)
        signOutRow(app).tap()
        XCTAssertTrue(confirmButton(app).appears(timeout: 5))
    }

    /// Cancel keeps the session and the modal.
    func testSignOutCancelKeepsModal() throws {
        let app = try FentonHomeApp.launchSignedIn()
        presentSignOutConfirmation(app)
        cancelSignOut(app)
        XCTAssertTrue(app.buttons["haSettings.signOut"].appears(timeout: 5), "Cancel left the modal")
    }

    /// The confirmation, presented, passes the audit.
    func testSignOutConfirmationPassesAudit() throws {
        let app = try FentonHomeApp.launchSignedIn()
        presentSignOutConfirmation(app)
        settleScreen() // Let the confirmation finish presenting.
        try FentonHomeApp.audit(app)
    }

    /// Confirming returns to sign-in. Last of the three: it ends the session (each test launches its own).
    func testSignOutConfirmReturnsToSignIn() throws {
        let app = try FentonHomeApp.launchSignedIn()
        presentSignOutConfirmation(app)
        confirmButton(app).tap()
        XCTAssertTrue(app.textFields["login.username"].appears(timeout: 10), "Sign-in did not appear")
    }

    /// The pose a capture runs in: ``upright`` leaves phones and the Duo as they are (setting the orientation on an unfolded
    /// Duo hangs the runner, devices.md) and sets portrait on an iPad; ``iPadLandscape`` is iPad only (skipped elsewhere).
    enum Pose { case upright, iPadLandscape }

    /// Sets `pose` before the launch (rotating with the web page up crashed the iPad simulator's backboardd; rotate from a
    /// fresh launch) and returns the screenshot suffix.
    private func enter(_ pose: Pose) throws -> String {
        switch pose {
        case .upright:
            if FentonHomeApp.family == .iPad { XCUIDevice.shared.orientation = .portrait }
            return FentonHomeApp.family == .iPad ? "portrait" : "current"
        case .iPadLandscape:
            guard FentonHomeApp.family == .iPad else { throw XCTSkip("iPad only") }
            FentonHomeApp.target().terminate()
            XCUIDevice.shared.orientation = .landscapeLeft
            return "landscape"
        }
    }

    private func captureSettingsTab(_ pose: Pose) throws {
        let suffix = try enter(pose)
        let app = try FentonHomeApp.launchSignedIn()
        showSettingsTab(app)
        keepScreenshot(app, "settings-\(suffix)")
    }

    private func captureHaSettingsModal(_ pose: Pose) throws {
        let suffix = try enter(pose)
        let app = try FentonHomeApp.launchSignedIn()
        openSettings(app)
        _ = app.descendants(matching: .any)["haSettings.role"].appears(timeout: 10)
        keepScreenshot(app, "ha-settings-\(suffix)")
    }

    private func captureSignOutConfirm(_ pose: Pose) throws {
        let suffix = try enter(pose)
        let app = try FentonHomeApp.launchSignedIn()
        openSettings(app)
        _ = app.descendants(matching: .any)["haSettings.role"].appears(timeout: 10)
        signOutRow(app).tap()
        XCTAssertTrue(confirmButton(app).appears(timeout: 5))
        settleScreen()
        keepScreenshot(app, "ha-signout-\(suffix)")
    }

    private func captureWebConfigPage(_ pose: Pose) throws {
        let suffix = try enter(pose)
        let app = try FentonHomeApp.launchSignedIn()
        openSettings(app)
        reveal(app.buttons["haSettings.open.settings"], in: app).tap()
        _ = app.webViews.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'Devices'")).firstMatch
            .appears(timeout: 30)
        settleScreen()
        keepScreenshot(app, "ha-web-config-\(suffix)")
    }

    // Screenshots of the Settings tab, the modal, the sign-out confirmation and the web page; iPad also captures landscape.
    func testCaptureSettingsTab() throws { try captureSettingsTab(.upright) }
    func testCaptureSettingsTabInIPadLandscape() throws { try captureSettingsTab(.iPadLandscape) }
    func testCaptureSettingsHaSettingsModal() throws { try captureHaSettingsModal(.upright) }
    func testCaptureSettingsHaSettingsModalInIPadLandscape() throws { try captureHaSettingsModal(.iPadLandscape) }
    func testCaptureSettingsSignOutConfirm() throws { try captureSignOutConfirm(.upright) }
    func testCaptureSettingsSignOutConfirmInIPadLandscape() throws { try captureSignOutConfirm(.iPadLandscape) }
    func testCaptureSettingsWebConfigPage() throws { try captureWebConfigPage(.upright) }
    func testCaptureSettingsWebConfigPageInIPadLandscape() throws { try captureWebConfigPage(.iPadLandscape) }
}
