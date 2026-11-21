import XCTest

/// A page carries the global chrome however it is reached; a sheet or a modal carries none (`.agents/patterns/page-base.md`).
/// The live publication gives every `page-room-*` page the global toolbar, so these journeys check, on the live server:
/// - a room opened from Quick Links on a third tab (Security) shows Back, Quick Links and Profile, and the tab bar stays;
/// - the room with the longest title keeps its large title clear of the Quick Links and Profile circles, at the default size and at
///   AX5 (frames, not pixels). The collapsed title is not covered: Downstairs Hallway's content fits the window, even at AX5, so the
///   page cannot scroll and the title never collapses. The journey records that (`title-collapse-not-reachable`) and would check the
///   collapsed title if a pose ever let it collapse;
/// - a room card's sheet and a status chip's sheet show Close and neither Quick Links nor Profile.
///
/// Live: needs `TEST_RUNNER_FENTON_HASS_*` (the `--env shell` runner passes them through; they are never printed) and skips without them.
/// Read only: it only navigates and opens sheets. Runs on iPhone, iPhone Duo (folded, and unfolded in either pose) and iPad (either
/// orientation; `TEST_RUNNER_FENTON_UITEST_ORIENTATION=landscape` rotates iPad and the unfolded Duo).
@MainActor
final class RoomChromeLiveJourneyTests: RoomLiveJourneyTestCase {
    /// The room whose title is the longest the live Rooms level offers.
    private static let longTitleRoom = "Downstairs Hallway"

    override class var rotatingFamilies: [FentonHomeApp.Family] { [.iPad, .iPhoneDuo] }

    // MARK: - Helpers

    /// Whether the Close button of a sheet is on screen and the global header circles are not.
    private func assertSheetChrome(_ app: XCUIApplication, _ what: String) {
        XCTAssertTrue(sheetIsOpen(app), "\(what): no sheet with Close opened")
        XCTAssertFalse(app.buttons["quickLinks.open"].isHittable, "\(what): the sheet draws Quick Links")
        XCTAssertFalse(app.buttons["nav.profile"].isHittable, "\(what): the sheet draws Profile")
    }

    /// Closes the sheet and waits for the page below to show its chrome again.
    private func closeSheet(_ app: XCUIApplication, _ what: String) {
        app.buttons["server-ui.sheet.close"].tap()
        let end = Date().addingTimeInterval(10)
        while sheetIsOpen(app), Date() < end { usleep(100_000) }
        settleScreen()
        XCTAssertFalse(sheetIsOpen(app), "\(what): Close left the sheet open")
        XCTAssertTrue(app.buttons["quickLinks.open"].appears(timeout: 10) && app.buttons["quickLinks.open"].isHittable,
                      "\(what): the page below lost its Quick Links")
    }

    /// Asserts the landed room draws Back, Quick Links and Profile.
    private func assertRoomChrome(_ app: XCUIApplication, _ what: String) {
        XCTAssertTrue(backButton(app).exists, "\(what): no Back")
        XCTAssertTrue(app.buttons["quickLinks.open"].exists && app.buttons["quickLinks.open"].isHittable, "\(what): no Quick Links")
        XCTAssertTrue(app.buttons["nav.profile"].exists && app.buttons["nav.profile"].isHittable, "\(what): no Profile")
    }

    /// Opens the first room the live Rooms level offers and waits for it to land.
    private func landFirstRoom(_ app: XCUIApplication) {
        openRoom(app)
        waitForLanding(app, "room")
        assertRoomChrome(app, "room")
    }

    /// The frames of the page title's text inside the header band, found by its label (the navigation bar element spans the width and is left out).
    private func titleFrames(_ app: XCUIApplication, _ title: String, above limit: CGFloat) -> [CGRect] {
        guard let snapshot = try? app.snapshot() else { return [] }
        var frames: [CGRect] = []
        func walk(_ node: XCUIElementSnapshot) {
            if node.elementType == .staticText, node.label == title, !node.frame.isEmpty, node.frame.minY < limit { frames.append(node.frame) }
            node.children.forEach(walk)
        }
        walk(snapshot)
        return frames
    }

    /// Scrolls the landed page up so a large title collapses into the header.
    private func scrollPageUp(_ app: XCUIApplication) {
        let scroller = app.collectionViews.allElementsBoundByIndex.first { $0.frame.height > 300 } ?? app.scrollViews.firstMatch
        for _ in 0..<2 { scroller.swipeUp(velocity: .slow) }
        settleScreen()
    }

    /// Checks the large title against both circles, then tries to collapse it; a page that fits cannot scroll, which is recorded, not failed.
    private func assertTitleClearOfCircles(_ app: XCUIApplication, _ what: String) {
        func circles() -> [CGRect] { [app.buttons["quickLinks.open"].frame, app.buttons["nav.profile"].frame] }
        func assertClear(_ state: String) {
            let found = circles()
            XCTAssertTrue(found.allSatisfy { !$0.isEmpty }, "\(what) \(state): the header circles are missing")
            let band = (found.map(\.maxY).max() ?? 0) + 4
            let titles = titleFrames(app, Self.longTitleRoom, above: band + 200)
            XCTAssertFalse(titles.isEmpty, "\(what) \(state): no title frame found, nothing was checked")
            for title in titles {
                for circle in found {
                    XCTAssertFalse(title.intersects(circle), "\(what) \(state): the title \(title) overlaps a header circle \(circle)")
                }
            }
        }
        shot(app, "title-large")
        assertClear("large")
        let before = titleFrames(app, Self.longTitleRoom, above: .greatestFiniteMagnitude)
        scrollPageUp(app)
        let collapsed = titleFrames(app, Self.longTitleRoom, above: .greatestFiniteMagnitude) != before
        // A page whose content fits the window cannot scroll, so its title never collapses: the large title is then the only state and is
        // recorded as such (the evidence note names it), not failed.
        let note = XCTAttachment(string: collapsed ? "collapsed: the title moved on scroll" : "collapse not reachable: the page content fits the window")
        note.name = "title-collapse-\(collapsed ? "reached" : "not-reachable")"
        note.lifetime = .keepAlways
        add(note)
        shot(app, "title-collapsed")
        assertRoomChrome(app, "\(what) collapsed")
        assertClear("collapsed")
    }

    /// A tab's bar item: iPad draws the tabs in a top bar whose items `barItem` does not reach, so there the `tab-<id>` button is used.
    private func tabItem(_ app: XCUIApplication, _ id: String, _ title: String) -> XCUIElement {
        family == "ipad" ? app.buttons["tab-\(id)"].firstMatch : app.barItem(title)
    }

    // MARK: - Quick Links from a third tab

    /// The Rooms grid opened from Security lands the room with Back, Quick Links and Profile, and the tab bar stays. The room is homed under Home
    /// (`.agents/patterns/modal-sheet.md`), so Home is the selected tab, as when it is opened from Settings; Security remains in the bar.
    func testARoomFromQuickLinksOnSecurityShowsTheChromeAndKeepsTheTabBar() throws {
        let app = try FentonHomeApp.launchSignedIn(readyIdentifier: "nav.profile")
        XCTAssertTrue(app.navigationBars["Home"].appears(timeout: 10), "The app did not open on Home")
        let security = tabItem(app, "security", "Security")
        if family == "ipad" {
            XCTAssertTrue(security.appears(timeout: 10), "No Security tab in the top bar")
            security.tap()
        } else {
            openSection("security", title: "Security", in: app)
        }
        settleScreen()
        if security.exists { XCTAssertTrue(security.isSelected, "Security did not open") }
        shot(app, "1-security")
        openRoom(app)
        waitForLanding(app, "room from Security")
        shot(app, "2-room-from-security")
        assertRoomChrome(app, "room from Security")
        XCTAssertTrue(security.exists, "The tab bar lost Security")
        XCTAssertTrue(tabItem(app, "home", "Home").exists, "The tab bar lost Home")
        assertLandedUnderHome(app, "room from Security")
        let home = tabItem(app, "home", "Home")
        XCTAssertTrue(home.exists && home.isSelected, "room from Security: Home is not the selected tab")

        backButton(app).tap()
        settleScreen()
        shot(app, "3-after-back")
        XCTAssertTrue(security.exists, "Back left no tab bar")
        XCTAssertFalse(sheetIsOpen(app), "Back left a sheet open")
    }

    // MARK: - Long title

    /// Downstairs Hallway at the default size: the large title and the two circles do not overlap. The collapsed title is not reachable (the content fits).
    func testTheLongestRoomTitleClearsTheCirclesAtTheDefaultSize() throws {
        let app = try FentonHomeApp.launchSignedIn(readyIdentifier: "nav.profile")
        XCTAssertTrue(app.navigationBars["Home"].appears(timeout: 10), "The app did not open on Home")
        openRoom(app, named: Self.longTitleRoom)
        waitForLanding(app, Self.longTitleRoom)
        assertRoomChrome(app, Self.longTitleRoom)
        assertTitleClearOfCircles(app, "default size")
    }

    /// The same at AX5, where the content still fits, so only the large title is checked.
    func testTheLongestRoomTitleClearsTheCirclesAtAX5() throws {
        let app = try FentonHomeApp.launchSignedIn(arguments: FentonHomeApp.ax5, readyIdentifier: "nav.profile")
        XCTAssertTrue(app.navigationBars["Home"].appears(timeout: 10), "The app did not open on Home")
        openRoom(app, named: Self.longTitleRoom)
        waitForLanding(app, "\(Self.longTitleRoom) at AX5")
        assertRoomChrome(app, "\(Self.longTitleRoom) at AX5")
        assertTitleClearOfCircles(app, "AX5")
    }

    // MARK: - Sheets

    /// A room card's sheet shows Close and neither Quick Links nor Profile; closing it brings the page's chrome back.
    func testARoomCardSheetShowsCloseOnly() throws {
        let app = try FentonHomeApp.launchSignedIn(readyIdentifier: "nav.profile")
        XCTAssertTrue(app.navigationBars["Home"].appears(timeout: 10), "The app did not open on Home")
        landFirstRoom(app)
        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'room.card.'")).firstMatch
        XCTAssertTrue(card.appears(timeout: 10), "The room offers no card")
        if !(card.exists && card.isHittable) { scrollTo(card, in: app) }
        shot(app, "1-room-with-card")
        card.tap()
        let end = Date().addingTimeInterval(10)
        while !sheetIsOpen(app), Date() < end { usleep(100_000) }
        settleScreen()
        shot(app, "2-card-sheet")
        assertSheetChrome(app, "room card sheet")
        closeSheet(app, "room card sheet")
        shot(app, "3-after-close")
    }

    /// A status chip's sheet shows Close and neither Quick Links nor Profile. The chip is the first device button below the title
    /// (the chip rail sits above the sections).
    func testAStatusChipSheetShowsCloseOnly() throws {
        let app = try FentonHomeApp.launchSignedIn(readyIdentifier: "nav.profile")
        XCTAssertTrue(app.navigationBars["Home"].appears(timeout: 10), "The app did not open on Home")
        landFirstRoom(app)
        let chips = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'device-node-'")).allElementsBoundByIndex
            .filter { $0.exists && $0.isHittable }
            .sorted { $0.frame.minY == $1.frame.minY ? $0.frame.minX < $1.frame.minX : $0.frame.minY < $1.frame.minY }
        XCTAssertFalse(chips.isEmpty, "The room offers no status chip")
        shot(app, "1-room-with-chips")
        chips[0].tap()
        let end = Date().addingTimeInterval(10)
        while !sheetIsOpen(app), Date() < end { usleep(100_000) }
        settleScreen()
        shot(app, "2-chip-sheet")
        assertSheetChrome(app, "status chip sheet")
        closeSheet(app, "status chip sheet")
        shot(app, "3-after-close")
    }
}
