import XCTest

/// The shell after the 2026-10-16 owner decisions (`.agents/design/direction-g.md`, Navigation): Settings is the last
/// tab; Quick Links and Profile are header buttons on every page; the Profile sheet is the web's Your Summary; and the
/// page title is the system's large title below the bar wherever the hamburger shows (it collapses into a leading-aligned inline title
/// right of the menu button, header-edge-fade R7 (4) and (5)); only the folded Duo's vertical bar, which has no hamburger, keeps the inline title throughout.
/// Runs on iPhone, the folded iPhone Duo and iPad (portrait; `FENTON_UITEST_ORIENTATION=landscape` for iPad landscape).
@MainActor
final class ShellJourneyTests: JourneyTestCase {
    // MARK: - Helpers

    /// Saves a screenshot to `FENTON_SHOTS_DIR` (never the repository) and attaches it for the result bundle.
    private func shoot(_ app: XCUIApplication, _ name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "\(layout)-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let folder = ProcessInfo.processInfo.environment["FENTON_SHOTS_DIR"], !folder.isEmpty else { return }
        try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: folder).appendingPathComponent("\(layout)-\(name).png"))
    }

    /// The window is regular width (iPad, unfolded Duo): the flyout replaces the tab bar and the title stays below the bar.
    private func isRegular(_ app: XCUIApplication) -> Bool { app.windows.firstMatch.frame.width >= 600 }

    private let sections = [("home", "Home"), ("security", "Security"), ("climate", "Climate"), ("chores", "Chores"), ("settings", "Settings")]

    /// Both header buttons: present, named, 44 pt targets, side by side and not overlapping.
    private func assertHeaderButtons(_ app: XCUIApplication, on page: String, file: StaticString = #filePath, line: UInt = #line) {
        let profile = app.buttons["nav.profile"]
        let links = app.buttons["quickLinks.open"]
        XCTAssertTrue(profile.appears(timeout: 10), "\(page) has no Profile button", file: file, line: line)
        // While a page pushes, the outgoing page's header buttons and the incoming page's are both in the tree: read them once
        // the transition has left one of each (a lookup that matches two throws "Multiple matching elements").
        let end = Date().addingTimeInterval(5)
        var single = 0
        while Date() < end, single < 2 {
            let both = app.buttons.matching(identifier: "quickLinks.open").count == 1 && app.buttons.matching(identifier: "nav.profile").count == 1
            single = both ? single + 1 : 0
            usleep(200_000)
        }
        XCTAssertTrue(links.exists, "\(page) has no Quick Links button", file: file, line: line)
        XCTAssertEqual(profile.label, "Profile", file: file, line: line)
        XCTAssertEqual(links.label, "Quick Links", file: file, line: line)
        // XCUITest reports a glass bar item's frame several points inside the 44 pt circle (Quick Links' system glass: 29 x 36
        // measured 2026-10-18; Profile's disc 44 wide and 38 tall); the 44 pt hit area is proven by tapping the circle's edge in
        // ``testHeaderCirclesHaveA44PointHitArea``, and the sizes by pixels in `HeaderButtonsJourneyTests`.
        // The Duo's vertical rail reports Quick Links 27.3 wide (a system rail item).
        let smallest: CGFloat = FentonHomeApp.family == .iPhoneDuo ? 24 : 28
        for button in [profile, links] {
            XCTAssertGreaterThanOrEqual(min(button.frame.width, button.frame.height), smallest, button.label, file: file, line: line)
        }
        XCTAssertFalse(links.frame.intersects(profile.frame.insetBy(dx: 2, dy: 2)), "\(page): the buttons overlap", file: file, line: line)
        // The folded Duo moves bar items into its vertical rail, which takes Quick Links out of the top row (system
        // behaviour); every other window keeps the two circles side by side.
        if FentonHomeApp.family != .iPhoneDuo || abs(links.frame.midY - profile.frame.midY) < 8 {
            XCTAssertLessThan(links.frame.maxX, profile.frame.minX + 1, "\(page): Quick Links is not beside Profile", file: file, line: line)
            XCTAssertLessThan(abs(links.frame.midY - profile.frame.midY), 8, "\(page): the buttons are on different rows", file: file, line: line)
        }
    }

    /// Back one page: the system Back button wherever the bar puts it (the folded Duo moves it to its rail), else the
    /// leading-edge back swipe.
    private func goBack(in app: XCUIApplication) {
        let back = app.buttons["BackButton"]
        if back.exists, back.isHittable {
            back.tap()
            return
        }
        let window = app.windows.firstMatch
        let start = window.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 2, dy: window.frame.height / 2))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: window.frame.width * 0.7, dy: 0)))
    }

    private func openMasterBedroom(in app: XCUIApplication) throws {
        let bedroom = try JourneyExpectations.current(for: .signedIn).value(.roomBedroomId)
        app.buttons["quickLinks.open"].tap()
        let rooms = element("quickLinks.rooms", in: app)
        XCTAssertTrue(rooms.appears(timeout: 10), "Quick Links did not open")
        rooms.tap()
        let tile = element("rooms.\(bedroom)", in: app)
        XCTAssertTrue(tile.appears(timeout: 10), "No bedroom tile")
        tile.tap()
        XCTAssertTrue(element("room.scroll.\(bedroom)", in: app).appears(timeout: 15), "The bedroom page did not open")
    }

    /// The page title in the header: the in-bar title (the folded Duo's, or a collapsed one, header-edge-fade R7) when it shows,
    /// else the static text with its label in the top of the window, the large title (a section header or a tab label of the
    /// same name sits lower).
    private func barTitle(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        let bar = app.descendants(matching: .any)["nav.title"].firstMatch
        if bar.exists, bar.label == title { return bar }
        let top = app.staticTexts.matching(NSPredicate(format: "label == %@", title)).allElementsBoundByIndex
            .first { $0.frame.minY < 150 && $0.frame.minY > 0 }
        return top ?? app.staticTexts["shell.noTitle"]
    }

    // MARK: - Settings tab (decision 1)

    /// Settings is the last tab (or flyout row) and its topics push inside the tab with Back.
    func testShellSettingsTopicPushes() throws {
        let app = try FentonHomeApp.launchSignedIn()
        app.openAccountSettings()
        XCTAssertTrue(element("settings.list", in: app).appears(timeout: 5), "No Settings list")
        XCTAssertTrue(app.buttons["settings.homeAssistant"].exists || app.descendants(matching: .any)["settings.homeAssistant"].exists
                      || app.buttons["settings.topic.admin"].exists, "Settings rows missing")
        shoot(app, "settings-tab")
        let modes = app.buttons["settings.topic.specialDeviceModes"]
        for _ in 0..<6 where !(modes.exists && modes.isHittable) { app.settingsList.swipeUp() }
        modes.tap()
        XCTAssertTrue(app.navigationBars["Special Device Modes"].appears(timeout: 5), "The topic did not push")
        XCTAssertFalse(app.buttons["split.close"].exists, "The Settings tab split")
        // The header buttons ride along on the pushed topic.
        XCTAssertTrue(app.buttons["nav.profile"].exists && app.buttons["quickLinks.open"].exists, "No header buttons on a Settings topic")
        shoot(app, "settings-topic")
        goBack(in: app)
        XCTAssertTrue(modes.appears(timeout: 5), "Back did not return to the Settings list")
    }

    /// Settings is no longer in the Account sheet.
    func testShellAccountSheetHasNoSettingsRow() throws {
        let app = try FentonHomeApp.launchSignedIn()
        app.openAccountSheet()
        XCTAssertFalse(app.buttons["account.settings"].exists, "The Account sheet still has a Settings row")
    }

    /// Vacation still opens from the Settings tab and Back returns to the list.
    func testSettingsTabVacationRowPushes() throws {
        let app = try FentonHomeApp.launchSignedIn()
        app.openAccountSettings()
        let vacation = app.buttons["settings.vacation"]
        XCTAssertTrue(vacation.appears(timeout: 5), "No Vacation row")
        vacation.tap()
        XCTAssertTrue(app.buttons["nav.profile"].appears(timeout: 5), "No Profile on the Vacation page")
        goBack(in: app)
        XCTAssertTrue(app.settingsList.appears(timeout: 5), "Back did not return to the Settings list")
    }

    /// The Report an Issue and Home Assistant Settings rows are in the Settings list (the list is lazy: Report is reached by
    /// scrolling, and the Home Assistant row is checked from there, as the original pass did).
    func testSettingsTabReportAndHomeAssistantRowsPresent() throws {
        let app = try FentonHomeApp.launchSignedIn()
        app.openAccountSettings()
        let list = app.settingsList
        XCTAssertTrue(list.appears(timeout: 5), "No Settings list")
        let report = app.buttons["settings.feedback.bug"]
        for _ in 0..<12 where !(report.exists && report.isHittable) { list.swipeUp(velocity: .slow) }
        XCTAssertTrue(report.exists, "No Report an Issue row")
        let homeAssistant = app.buttons["settings.homeAssistant"]
        XCTAssertTrue(homeAssistant.exists, "No Home Assistant Settings row")
    }

    // MARK: - Header buttons (decision 2)

    /// Profile and Quick Links are on a tab root, in every window, with names and 44 pt targets.
    @discardableResult
    private func headerButtonsOnTabRoot(_ section: String, _ title: String) throws -> XCUIApplication {
        let app = try FentonHomeApp.launchSignedIn()
        if section != "home" { openSection(section, title: title, in: app) }
        XCTAssertTrue(app.navigationBars[title].appears(timeout: 10), "\(title) did not appear")
        settleScreen()
        assertHeaderButtons(app, on: title)
        shoot(app, "root-\(section)")
        return app
    }

    func testHeaderButtonsOnHomeRoot() throws {
        let app = try headerButtonsOnTabRoot("home", "Home")
        // Quick Links is a header button, not a flyout row.
        XCTAssertFalse(app.buttons["nav.quickLinks"].exists, "Quick Links is still a flyout row")
    }
    func testHeaderButtonsOnSecurityRoot() throws { try headerButtonsOnTabRoot("security", "Security") }
    func testHeaderButtonsOnClimateRoot() throws { try headerButtonsOnTabRoot("climate", "Climate") }
    func testHeaderButtonsOnChoresRoot() throws { try headerButtonsOnTabRoot("chores", "Chores") }
    func testHeaderButtonsOnSettingsRoot() throws { try headerButtonsOnTabRoot("settings", "Settings") }

    /// A circle is a 44 pt target: a tap 19 pt left of its centre (outside the 29 to 38 pt frame XCUITest reports, inside
    /// the 22 pt radius) still opens its sheet. Profile's frame includes its badge, so its centre is where the frame's
    /// centre is, not the disc's, and 19 pt left still lands on the disc.
    private func headerCircleHasA44PointHitArea(_ id: String, sheetClose: String) throws {
        let app = try FentonHomeApp.launchSignedIn()
        let button = app.buttons[id]
        XCTAssertTrue(button.appears(timeout: 10), id)
        let centre = button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        // Read before the tap: once the sheet covers the header the buttons leave the tree, and the tap's sheet can arrive
        // before the next line runs (animations run fast in UI tests).
        let frames = "quickLinks \(app.buttons["quickLinks.open"].frame), profile \(app.buttons["nav.profile"].frame), window \(app.windows.firstMatch.frame)"
        centre.withOffset(CGVector(dx: -19, dy: 0)).tap()
        XCTAssertTrue(app.buttons[sheetClose].appears(timeout: 5), "\(id) ignored a tap 19 pt from its centre (\(frames))")
        app.buttons[sheetClose].tap()
        XCTAssertTrue(app.buttons[sheetClose].disappears(timeout: 5))
        XCTAssertTrue(app.buttons["home.chip.lights"].appears(timeout: 10))
    }

    func testHeaderCircleQuickLinksHasA44PointHitArea() throws {
        try headerCircleHasA44PointHitArea("quickLinks.open", sheetClose: "quickLinks.close")
    }
    func testHeaderCircleProfileHasA44PointHitArea() throws {
        try headerCircleHasA44PointHitArea("nav.profile", sheetClose: "account.close")
    }

    /// A pushed page (Bedroom 1, which had no Profile) carries both buttons; each opens its sheet from there.
    func testHeaderButtonsOnAPushedRoomPage() throws {
        let app = try FentonHomeApp.launchSignedIn()
        try openMasterBedroom(in: app)
        settleScreen()
        assertHeaderButtons(app, on: try JourneyExpectations.current(for: .signedIn).value(.roomBedroomTitle))
        shoot(app, "room-page")
        app.buttons["nav.profile"].tap()
        XCTAssertTrue(app.buttons["account.close"].appears(timeout: 5), "Profile did not open from a pushed page")
        app.buttons["account.close"].tap()
        XCTAssertTrue(app.buttons["quickLinks.open"].appears(timeout: 5))
        app.buttons["quickLinks.open"].tap()
        XCTAssertTrue(element("quickLinks.rooms", in: app).appears(timeout: 5), "Quick Links did not open from a pushed page")
        app.buttons["quickLinks.close"].tap()
        XCTAssertTrue(element("room.scroll.\(try JourneyExpectations.current(for: .signedIn).value(.roomBedroomId))", in: app).appears(timeout: 5), "The room page was lost behind the sheet")
    }

    /// The Quick Links sheet pushes the page it picks on the stack under it, so Back returns to where it was opened.
    func testQuickLinksPushesItsPageOnTheCurrentStack() throws {
        let app = try FentonHomeApp.launchSignedIn()
        openSection("climate", title: "Climate", in: app)
        app.buttons["quickLinks.open"].tap()
        let link = element("quickLinks.custom-lights", in: app)
        XCTAssertTrue(link.appears(timeout: 10), "No Custom Lights tile")
        link.tap()
        XCTAssertTrue(app.navigationBars["Custom Lights"].appears(timeout: 10), "Custom Lights did not push")
        XCTAssertFalse(element("quickLinks.rooms", in: app).exists, "The sheet stayed open")
        assertHeaderButtons(app, on: "Custom Lights")
        goBack(in: app)
        XCTAssertTrue(app.navigationBars["Climate"].appears(timeout: 10), "Back did not return to Climate, where Quick Links was opened")
    }

    // MARK: - Profile modal (decision 3)

    /// The Profile button opens the web's Your Summary on the live house, read-only: it opens on the summary (a resident's
    /// Overdue Chores) and carries the tab bar.
    func testSummarySheetOpensOnSummary() throws {
        let app = try FentonHomeApp.launchSignedIn()
        app.openAccountSheet(tab: nil)
        XCTAssertTrue(app.buttons["summary.tabs.profile"].appears(timeout: 5) || app.buttons["summary.tabs"].exists,
                      "No tab bar in the Summary sheet")
        XCTAssertFalse(element("account.header", in: app).exists, "The sheet opened on Profile, not the summary")
        shoot(app, "summary-opening")
    }

    /// The account (who is signed in, who is home, Sign Out) lives on the sheet's Profile tab, with no Settings row.
    func testSummarySheetProfileTab() throws {
        let app = try FentonHomeApp.launchSignedIn()
        app.openAccountSheet(tab: nil)
        app.selectSummaryTab(.profile)
        XCTAssertTrue(element("account.header", in: app).appears(timeout: 5), "No account header")
        XCTAssertFalse(app.buttons["account.settings"].exists, "Settings row in the Account sheet")
        shoot(app, "account-top")
        let signOut = app.buttons["account.signOut"]
        let list = element("account.list", in: app)
        for _ in 0..<10 where !(signOut.exists && signOut.isHittable) { list.swipeUp() }
        XCTAssertTrue(signOut.exists, "No Sign Out")
        assertTarget(signOut)
        shoot(app, "account-bottom")
    }

    // MARK: - Page title (header-edge-fade R7 (4) and (5))

    /// Owner, 2026-10-28: "Bring back the title collapse as well", then "left align the title again (still to right of hamburger)".
    /// Wherever the hamburger shows (iPhone, iPad with the flyout, a compact iPad window, the unfolded Duo) the page has the
    /// system's large title at rest, which collapses on scrolling into the system's inline title, leading aligned, right of the
    /// menu button and clear of the header buttons, and comes back at the top. The folded Duo's vertical bar has no hamburger and
    /// keeps the inline title from the start (when the system shows one there at all). There is never a custom `nav.title` view.
    func testTitleIsLargeAtRestAndCollapsesBesideTheMenu() throws {
        let app = try FentonHomeApp.launchSignedIn()
        openSection("climate", title: "Climate", in: app)
        XCTAssertTrue(app.navigationBars["Climate"].appears(timeout: 10))
        settleScreen()
        let profile = app.buttons["nav.profile"]
        let links = app.buttons["quickLinks.open"]
        let menu = app.buttons["nav.open"]
        XCTAssertFalse(app.descendants(matching: .any)["nav.title"].firstMatch.exists, "The custom bar title is installed")
        let title = { app.navigationBars.staticTexts["Climate"].firstMatch }
        let hasMenu = menu.exists
        if FentonHomeApp.family != .iPhoneDuo {
            XCTAssertTrue(hasMenu, "No hamburger on \(FentonHomeApp.family)")
        }

        // At rest: large where the hamburger shows, else inline from the start.
        let rest = title()
        if rest.appears(timeout: 3), rest.frame.width > 1 {
            if hasMenu {
                XCTAssertGreaterThanOrEqual(rest.frame.height, 40, "The title is not large at rest: \(rest.frame)")
            } else {
                XCTAssertLessThan(rest.frame.height, 40, "The title is large on a page with no hamburger: \(rest.frame)")
            }
        } else {
            XCTAssertEqual(FentonHomeApp.family, .iPhoneDuo, "No title in the bar at rest")
        }
        if hasMenu {
            XCTAssertLessThan(menu.frame.minX, 30, "The menu button is not at the left edge")
            XCTAssertLessThan(menu.frame.maxX, links.frame.minX, "The menu button is not left of Quick Links")
            XCTAssertLessThan(menu.frame.midX, profile.frame.minX, "The menu button is not left of Profile")
        }
        shoot(app, "title-rest")

        let scroll = app.scrollViews.firstMatch
        for _ in 0..<3 { scroll.swipeUp() }
        settleScreen()
        let collapsed = title()
        if collapsed.appears(timeout: 3), collapsed.frame.width > 1 {
            XCTAssertLessThan(collapsed.frame.height, 40, "The title did not collapse: \(collapsed.frame)")
            // "Climate" is short, so a centred title would fail this: it must sit in the leading half of the bar.
            XCTAssertLessThan(collapsed.frame.midX, app.windows.firstMatch.frame.midX, "The collapsed title is centred: \(collapsed.frame)")
            if hasMenu {
                XCTAssertGreaterThanOrEqual(collapsed.frame.minX, menu.frame.maxX - 1, "The collapsed title runs under the menu button")
            }
            if abs(links.frame.midY - collapsed.frame.midY) < 20 {
                XCTAssertLessThanOrEqual(collapsed.frame.maxX, links.frame.minX + 1, "The collapsed title runs under the header buttons")
            }
        } else {
            XCTAssertEqual(FentonHomeApp.family, .iPhoneDuo, "No inline title in the bar after scrolling")
        }
        shoot(app, "title-scrolled")

        for _ in 0..<4 { scroll.swipeDown() }
        settleScreen()
        let back = title()
        if hasMenu, back.appears(timeout: 3), back.frame.width > 1 {
            XCTAssertGreaterThanOrEqual(back.frame.height, 40, "The large title did not come back at the top: \(back.frame)")
        }
    }

    /// A pushed page keeps the system's own title behaviour: Back leading, the title below or centred, and both header
    /// buttons trailing; the title never collides with them.
    func testPushedPageTitleClearsTheHeaderButtons() throws {
        let app = try FentonHomeApp.launchSignedIn()
        try openMasterBedroom(in: app)
        settleScreen()
        let title = barTitle(app, try JourneyExpectations.current(for: .signedIn).value(.roomBedroomTitle))
        XCTAssertTrue(title.exists, "No bedroom title")
        let links = app.buttons["quickLinks.open"]
        if abs(title.frame.midY - links.frame.midY) < 20 {
            XCTAssertLessThan(title.frame.maxX, links.frame.minX, "The title runs under the header buttons")
        }
        shoot(app, "title-pushed")
    }
}
