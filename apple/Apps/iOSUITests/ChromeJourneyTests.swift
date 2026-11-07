import XCTest

/// Shared chrome on every device (`.agents/patterns/header-edge-fade.md`, `page-backdrop.md`, `modal-sheet.md`,
/// `.agents/design/apple/iphone.md`): section roots carry the menu (where Settings is not a tab), Quick Links and
/// the profile button; modals close with the circle X; screenshots of each page and modal for design review.
@MainActor
final class ChromeJourneyTests: JourneyTestCase {

    private var suffix: String {
        switch FentonHomeApp.family {
        case .iPhone: "iphone"
        case .iPhoneDuo: "duo"
        case .iPad: "ipad"
        }
    }

    /// A tab in the tab bar, or on the folded Duo in its vertical bar.
    /// The label can carry a badge ("Chores, 4 overdue" with live data), so it matches by its leading title.
    private func tab(_ title: String, in app: XCUIApplication) -> XCUIElement {
        app.barItem(title)
    }

    /// Goes to a section through its tab when the bar shows it, else through the menu.
    private func open(_ section: String, title: String, in app: XCUIApplication) {
        let item = tab(title, in: app)
        if item.exists, item.isHittable {
            item.tap()
        } else {
            app.buttons["nav.open"].tap()
            XCTAssertTrue(app.descendants(matching: .any)["nav.flyout"].appears(timeout: 3), "Menu did not open")
            app.buttons["nav.\(section)"].tap()
            // The flyout closes before the next tap: a tap on the menu button while it is still leaving is swallowed.
            XCTAssertTrue(app.descendants(matching: .any)["nav.flyout"].disappears(timeout: 5), "Menu stayed open")
        }
        XCTAssertTrue(app.navigationBars[title].appears(timeout: 5), "\(title) did not appear")
    }

    /// Closes the front modal with its circle-X Close (in the navigation bar, or the folded Duo's vertical bar).
    private func closeModal(_ app: XCUIApplication) {
        let inBar = app.navigationBars.buttons["Close"].firstMatch
        // The folded Duo moves bar items into its vertical bar, which XCUITest reports outside the navigation bar.
        let anywhere = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == 'Close' OR identifier == 'sheet.close'")).firstMatch
        let close = inBar.appears(timeout: 3) ? inBar : anywhere
        XCTAssertTrue(close.appears(timeout: 5), "Modal has no Close")
        close.tap()
        XCTAssertTrue(close.disappears(timeout: 5), "Modal did not close")
    }

    /// Every section root has the profile and Quick Links header buttons (owner, 2026-10-16), and Settings is a tab.
    func testSectionRootsCarryShellItems() throws {
        let app = try FentonHomeApp.launchSignedIn()
        XCTAssertTrue(app.buttons["nav.profile"].appears(timeout: 5), "No profile button")
        XCTAssertGreaterThanOrEqual(app.buttons["nav.profile"].frame.height, 36, "Profile under its glass circle (the 44 pt hit area is `ShellJourneyTests.testHeaderCirclesHaveA44PointHitArea`)")
        XCTAssertTrue(app.buttons["quickLinks.open"].exists, "No Quick Links header button")
        XCTAssertFalse(app.tabBars.buttons["Quick Links"].exists, "Quick Links is a header button, not a tab")
    }

    // MARK: - Captures
    //
    // One test per screen (`testCaptureChrome<Name>`; the glob `ChromeJourneyTests/testCaptureChrome*` recombines the original
    // pass). Each launches signed in and goes straight to its screen, so any one can be recaptured on its own.

    private func launchForCapture() throws -> XCUIApplication {
        let app = try FentonHomeApp.launchSignedIn()
        settleScreen()
        return app
    }

    /// Opens a modal from Home and closes it again after the screenshot.
    private func captureHomeModal(_ app: XCUIApplication, opening control: XCUIElement, as name: String) {
        control.tap()
        settleScreen()
        keepScreenshot(app, name)
        closeModal(app)
    }

    /// Goes to a section root and keeps its screenshot.
    private func captureSection(_ section: String, title: String) throws {
        let app = try launchForCapture()
        open(section, title: title, in: app)
        settleScreen()
        keepScreenshot(app, "chrome-\(section)-\(suffix)")
    }

    /// Home at the top.
    func testCaptureChromeHomeTop() throws {
        let app = try launchForCapture()
        keepScreenshot(app, "chrome-home-top-\(suffix)")
    }

    /// Home scrolled a little: the system's own scroll-edge effect and bar material sit behind the header (pages, owner 2026-10-28).
    func testCaptureChromeHomeScrolled() throws {
        let app = try launchForCapture()
        let scroll = app.scrollViews["home.scroll"].firstMatch
        scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            .press(forDuration: 0.05, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)))
        settleScreen()
        keepScreenshot(app, "chrome-home-scrolled-\(suffix)")
    }

    /// The Security chip's modal.
    func testCaptureChromeSecurityChipModal() throws {
        let app = try launchForCapture()
        captureHomeModal(app, opening: app.buttons["home.chip.security"], as: "chrome-modal-security-\(suffix)")
    }

    /// The front-door camera modal (skipped where the house shows no camera tile).
    func testCaptureChromeCameraModal() throws {
        let app = try launchForCapture()
        let camera = app.buttons["home.camera.front_door"]
        guard camera.appears(timeout: 5) else { throw XCTSkip("No front-door camera tile") }
        captureHomeModal(app, opening: camera, as: "chrome-modal-camera-\(suffix)")
    }

    /// The Profile modal over Home.
    func testCaptureChromeProfileModal() throws {
        let app = try launchForCapture()
        app.openAccountSheet()
        settleScreen()
        keepScreenshot(app, "chrome-modal-profile-\(suffix)")
    }

    /// The Quick Links sheet.
    func testCaptureChromeQuickLinks() throws {
        let app = try launchForCapture()
        app.buttons["quickLinks.open"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["quickLinks.rooms"].appears(timeout: 5))
        settleScreen()
        keepScreenshot(app, "chrome-quick-links-\(suffix)")
    }

    func testCaptureChromeSecurityTab() throws { try captureSection("security", title: "Security") }
    func testCaptureChromeClimateTab() throws { try captureSection("climate", title: "Climate") }
    func testCaptureChromeChoresTab() throws { try captureSection("chores", title: "Chores") }
    func testCaptureChromeSettingsTab() throws { try captureSection("settings", title: "Settings") }

    /// The navigation flyout over Settings (the page the original pass was on).
    func testCaptureChromeNavFlyout() throws {
        let app = try launchForCapture()
        guard app.buttons["nav.open"].exists else { throw XCTSkip("No hamburger in this window") }
        open("settings", title: "Settings", in: app)
        settleScreen() // The page has finished switching: a menu tap during the switch is lost (iPad).
        app.buttons["nav.open"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["nav.flyout"].appears(timeout: 3))
        settleScreen()
        keepScreenshot(app, "chrome-menu-\(suffix)")
    }

    /// The Account sheet over Settings (the page the original pass was on).
    func testCaptureChromeAccountSheet() throws {
        let app = try launchForCapture()
        open("settings", title: "Settings", in: app)
        app.openAccountSheet()
        settleScreen()
        keepScreenshot(app, "chrome-account-\(suffix)")
    }

    // MARK: - Audits

    /// Home with the new toolbar items and pill chips, audit clean (AX5 included).
    func testChromeHomePassesAccessibilityAudit() throws {
        let app = try FentonHomeApp.launchSignedIn()
        settleScreen()
        try FentonHomeApp.audit(app) {
            let large = try FentonHomeApp.launchSignedIn(arguments: FentonHomeApp.ax5)
            settleScreen()
            return large
        }
    }

    /// The Quick Links page, audit clean (AX5 included).
    func testChromeQuickLinksPassesAccessibilityAudit() throws {
        let app = try FentonHomeApp.launchSignedIn()
        app.buttons["quickLinks.open"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["quickLinks.rooms"].appears(timeout: 5))
        settleScreen()
        try FentonHomeApp.audit(app) {
            let large = try FentonHomeApp.launchSignedIn(arguments: FentonHomeApp.ax5)
            large.buttons["quickLinks.open"].tap()
            XCTAssertTrue(large.descendants(matching: .any)["quickLinks.rooms"].appears(timeout: 5))
            settleScreen()
            return large
        }
    }
}
