import XCTest

/// The page title on the iPhone Duo's vertical bar (`.agents/patterns/header-edge-fade.md`, R7 (6); `.agents/design/apple/duo.md`).
/// Owner, 2026-10-29: "Yes, 24 is the right font." Owner, 2026-10-30: "Unfolded portrait should just use the normal iPhone style
/// title. Unfolded landscape/partial landscape should use 24pt". The vertical bar (the folded outer display in both rotations, the
/// inner display in landscape) keeps its title in the bar at a fixed 24 pt semibold and the bar never minimises, so the title is still
/// there after the page scrolls, after a tab switch and after a push and Back. Where the bars are horizontal (iPhone, iPad, the Duo's
/// unfolded portrait) the system's own title applies and the vertical-bar journeys stop at once (no `XCTSkip`: a skip hangs the
/// unfolded Duo's runner).
@MainActor
final class DuoBarTitleJourneyTests: JourneyTestCase {
    /// A medium title at the default text size: 24 pt semibold lays out about 29 pt tall; the system's small inline title is about 18 pt.
    private let mediumHeight: ClosedRange<CGFloat> = 24...36

    /// Set by a journey that rotates the device in-process, so tear-down leaves the pose as it found it.
    private var restoreOrientation: UIDeviceOrientation?

    override func tearDown() {
        super.tearDown()
        if let restoreOrientation { XCUIDevice.shared.orientation = restoreOrientation }
    }

    private func inVerticalBar(_ app: XCUIApplication) -> Bool {
        FentonHomeApp.family == .iPhoneDuo && app.tabBars.count == 0
    }

    private func barTitle(_ title: String, in app: XCUIApplication) -> XCUIElement {
        app.navigationBars.staticTexts[title].firstMatch
    }

    private func assertMediumTitle(_ title: String, in app: XCUIApplication, _ when: String, file: StaticString = #filePath, line: UInt = #line) {
        let element = barTitle(title, in: app)
        XCTAssertTrue(element.waitForExistence(timeout: 5), "No \(title) title \(when)", file: file, line: line)
        XCTAssertTrue(mediumHeight.contains(element.frame.height), "\(title) is not the medium size \(when): \(element.frame)", file: file, line: line)
        XCTAssertGreaterThan(element.frame.minX, 0, "\(title) is off screen \(when)", file: file, line: line)
    }

    private func scrollHome(_ app: XCUIApplication) {
        let scroll = app.scrollViews["home.scroll"].firstMatch
        scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            .press(forDuration: 0.05, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)))
        settleScreen()
    }

    private func goBack(in app: XCUIApplication) {
        let back = app.buttons["BackButton"]
        if back.exists, back.isHittable { back.tap(); return }
        let window = app.windows.firstMatch
        let start = window.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 2, dy: window.frame.height / 2))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: window.frame.width * 0.7, dy: 0)))
    }

    /// The title is medium at rest, and still there after scrolling, after a tab switch, and back on the scrolled Home.
    func testTheTitleStaysMediumWhileScrollingAndSwitchingTabs() throws {
        let app = try FentonHomeApp.launchSignedIn()
        guard inVerticalBar(app) else { return }
        settleScreen()
        assertMediumTitle("Home", in: app, "at rest")
        scrollHome(app)
        assertMediumTitle("Home", in: app, "after scrolling")
        openSection("security", title: "Security", in: app)
        assertMediumTitle("Security", in: app, "after switching tabs")
        openSection("home", title: "Home", in: app)
        assertMediumTitle("Home", in: app, "back on the scrolled Home")
    }

    /// A pushed page names itself in the bar, and the page under it has its title again after Back.
    func testTheTitleSurvivesPushAndBack() throws {
        let app = try FentonHomeApp.launchSignedIn()
        guard inVerticalBar(app) else { return }
        openSection("settings", title: "Settings", in: app)
        assertMediumTitle("Settings", in: app, "on Settings")
        let topic = element("settings.topic.admin", in: app)
        XCTAssertTrue(topic.waitForExistence(timeout: 10), "No Admin row")
        if !topic.isHittable { app.scrollViews["settings.list"].swipeUp() }
        topic.tap()
        assertMediumTitle("Admin", in: app, "on the pushed page")
        goBack(in: app)
        assertMediumTitle("Settings", in: app, "after Back")
    }

    /// Accessibility: at the largest text size the title is still one line, inside the window.
    func testTheTitleDoesNotWrapOrClipAtAccessibilityTextSize() throws {
        let app = try FentonHomeApp.launchSignedIn(arguments: FentonHomeApp.ax5)
        guard inVerticalBar(app) else { return }
        settleScreen()
        let title = barTitle("Home", in: app)
        XCTAssertTrue(title.waitForExistence(timeout: 5), "No Home title at AX5")
        XCTAssertLessThanOrEqual(title.frame.height, 48, "The title wrapped at AX5: \(title.frame)")
        XCTAssertGreaterThanOrEqual(title.frame.minX, 0)
        XCTAssertLessThanOrEqual(title.frame.maxX, app.windows.firstMatch.frame.maxX, "The title runs off the screen at AX5")
        scrollHome(app)
        XCTAssertTrue(barTitle("Home", in: app).exists, "The title is gone after scrolling at AX5")
    }

    // MARK: - Unfolded portrait keeps the iPhone's title

    /// The system's large title at rest: the navigation bar named for the page holds a static text much taller than the inline title
    /// and wide enough to read (a title with no room measured 7 pt wide).
    private func assertLargeTitle(_ title: String, in app: XCUIApplication, _ when: String, file: StaticString = #filePath, line: UInt = #line) {
        let bar = app.navigationBars[title]
        XCTAssertTrue(bar.waitForExistence(timeout: 8), "No \(title) navigation bar \(when)", file: file, line: line)
        let titleText = bar.staticTexts[title].firstMatch
        XCTAssertTrue(titleText.waitForExistence(timeout: 5), "No \(title) title text \(when)", file: file, line: line)
        XCTAssertGreaterThan(titleText.frame.width, 30, "The \(title) title has no room \(when): \(titleText.frame)", file: file, line: line)
        XCTAssertGreaterThan(titleText.frame.height, 36, "\(title) is not the large title \(when): \(titleText.frame)", file: file, line: line)
    }

    private func waitForTabBar(_ app: XCUIApplication) -> Bool {
        let tabs = app.tabBars.firstMatch
        return tabs.waitForExistence(timeout: 10)
    }

    /// Unfolded landscape is 24 pt in the vertical bar; rotating to portrait gives the iPhone's large title (and its collapse into the
    /// inline title), and rotating back gives 24 pt again. The pose is changed in-process (`XCUIDevice.orientation`), so it also covers the
    /// page surviving the flip. Stops at once on every other pose.
    func testRotatingTheUnfoldedDuoSwitchesBetweenTheTwoTitles() throws {
        let app = try FentonHomeApp.launchSignedIn()
        let window = app.windows.firstMatch.frame
        // The unfolded inner display (both sides longer than 600 pt) in either orientation; folded poses and other families stop here.
        guard FentonHomeApp.family == .iPhoneDuo, min(window.width, window.height) > 600 else { return }
        restoreOrientation = window.width > window.height ? .landscapeLeft : .portrait
        if window.width <= window.height {
            XCUIDevice.shared.orientation = .landscapeLeft
            let deadline = Date().addingTimeInterval(10)
            while app.tabBars.count > 0, Date() < deadline { usleep(250_000) }
        }
        // An unfolded display that started in portrait may not follow the in-process rotation (see below): nothing to compare then.
        guard inVerticalBar(app) else {
            let note = XCTAttachment(string: "The unfolded Duo did not rotate in-process to landscape; the rotation journey has nothing to compare.")
            note.lifetime = .keepAlways
            add(note)
            return
        }
        settleScreen()
        assertMediumTitle("Home", in: app, "in unfolded landscape")
        XCUIDevice.shared.orientation = .portrait
        // The simulator's inner display does not always follow an in-process rotation (observed on Xcode 27.1: the window stays
        // landscape; Device Hub's Rotate control does turn it). Without a turn there is nothing to compare, so the journey records
        // that and stops; `testUnfoldedPortraitColdLaunchHasTheLargeTitle` and the captures cover portrait.
        guard waitForTabBar(app) else {
            let note = XCTAttachment(string: "The unfolded Duo did not rotate in-process; rotation journey stopped after the landscape check.")
            note.lifetime = .keepAlways
            add(note)
            return
        }
        settleScreen()
        assertLargeTitle("Home", in: app, "after rotating to unfolded portrait")
        scrollHome(app)
        let inline = app.navigationBars["Home"].staticTexts["Home"].firstMatch
        XCTAssertTrue(inline.waitForExistence(timeout: 5), "No inline title after scrolling in unfolded portrait")
        XCTAssertGreaterThan(inline.frame.width, 30, "The inline title has no room: \(inline.frame)")
        XCUIDevice.shared.orientation = .landscapeLeft
        let deadline = Date().addingTimeInterval(10)
        while app.tabBars.count > 0, Date() < deadline { usleep(250_000) }
        settleScreen()
        assertMediumTitle("Home", in: app, "after rotating back to unfolded landscape")
    }

    /// Cold launch in unfolded portrait: Home, one tab and one push all have the iPhone's large title (a push beside Back).
    func testUnfoldedPortraitColdLaunchHasTheLargeTitle() throws {
        let app = try FentonHomeApp.launchSignedIn()
        guard FentonHomeApp.family == .iPhoneDuo, app.tabBars.count > 0 else { return }
        settleScreen()
        assertLargeTitle("Home", in: app, "at rest")
        openSection("security", title: "Security", in: app)
        assertLargeTitle("Security", in: app, "after switching tabs")
        openSection("settings", title: "Settings", in: app)
        let topic = element("settings.topic.admin", in: app)
        XCTAssertTrue(topic.waitForExistence(timeout: 10), "No Admin row")
        if !topic.isHittable { app.scrollViews["settings.list"].swipeUp() }
        topic.tap()
        XCTAssertTrue(app.navigationBars.staticTexts["Admin"].firstMatch.waitForExistence(timeout: 8), "No Admin title on the pushed page")
    }
}
