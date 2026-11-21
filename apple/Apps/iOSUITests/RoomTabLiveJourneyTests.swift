import XCTest

/// A homed page opens under its home tab (`.agents/patterns/modal-sheet.md`): from Settings, Quick Links, the Rooms tile and a
/// room, the sheet closes and the room lands on top of Home's stack, with Back and the same chrome as the room opened from Home (the live publication decides whether a room page draws Quick Links and Profile); Back leads to the page below it on Home
/// and Settings is where it was left, with no sheet. A second room appends to Home's stack, and Food, authored under Home, lands there too.
///
/// Live: needs `TEST_RUNNER_FENTON_HASS_*` (the `--env shell` runner passes them through; they are never printed) and skips without them. No room
/// name or entity id lives in the repository: the rooms are the first two room tiles the live Rooms level offers, found by what they are (a tile
/// that is not the sheet's own chrome) and compared by the identifier and title they carry at run time. It is read only: it only navigates. Runs on
/// iPhone, iPhone Duo and iPad.
@MainActor
final class RoomTabLiveJourneyTests: RoomLiveJourneyTestCase {
    // MARK: - Journey

    /// A room from Quick Links on Settings lands on Home; Back shows the page below on Home; Settings is as it was.
    func testARoomFromQuickLinksOnSettingsLandsUnderHomeAndBackStaysOnHome() throws {
        let app = try launchOnSettings()
        shot(app, "1-settings")
        openQuickLinks(app)
        shot(app, "2-quick-links")
        let rooms = tile("quick-link-rooms", in: app)
        XCTAssertTrue(rooms.exists, "Quick Links has no Rooms tile")
        rooms.tap()
        settleScreen()
        dump(app, "rooms-level")
        XCTAssertTrue(sheetIsOpen(app), "The Rooms tile closed the sheet")
        shot(app, "3-rooms-level")
        let room = roomTiles(app).first
        XCTAssertNotNil(room, "The Rooms level offers no room tile")
        room?.tap()
        waitForLanding(app, "room")
        shot(app, "4-room-landed")
        assertLandedUnderHome(app, "room")

        backButton(app).tap()
        settleScreen()
        shot(app, "5-after-back")
        assertHomeRoot(app, "Back")

        assertSettingsAsLeft(app, "return")
        shot(app, "6-settings-again")
    }

    /// A room already on Home, then a second room from Settings: Back leads to the first (append, not trim).
    func testASecondRoomAppendsToHomesStackAndBackLeadsToTheFirst() throws {
        let app = try launchOnSettings()
        let firstID = openRoom(app)
        waitForLanding(app, "first room")
        assertLandedUnderHome(app, "first room")
        let firstTitle = pageTitle(app)
        shot(app, "1-first-room")

        assertSettingsAsLeft(app, "between rooms")
        let secondID = openRoom(app, at: 1)
        XCTAssertNotEqual(firstID, secondID, "The second pass chose the first room again")
        waitForLanding(app, "second room")
        assertLandedUnderHome(app, "second room")
        let secondTitle = pageTitle(app)
        shot(app, "2-second-room")
        XCTAssertNotEqual(firstTitle, secondTitle, "The second room shows the first room's page")

        backButton(app).tap()
        settleScreen()
        shot(app, "3-back-to-first")
        XCTAssertEqual(pageTitle(app), firstTitle, "Back from the second room did not lead to the first")
        XCTAssertTrue(backButton(app).exists, "The first room lost its Back: Home's stack was trimmed")
    }

    /// Food, authored under Home, lands there from Settings.
    func testFoodFromQuickLinksOnSettingsLandsUnderHome() throws {
        let app = try launchOnSettings()
        openQuickLinks(app)
        let food = tile("quick-link-food", in: app)
        XCTAssertTrue(food.exists, "Quick Links has no Food tile")
        shot(app, "1-quick-links")
        food.tap()
        waitForLanding(app, "Food")
        shot(app, "2-food-landed")
        assertLandedUnderHome(app, "Food")
    }

    /// The room landed from Settings draws the same chrome as the same room opened from Home, where no tab changes: the same Quick Links and
    /// Profile presence, Back, and Home selected. (In the live publication a room page may draw neither: that is the page's, not the routing's.)
    func testARoomLandedFromSettingsDrawsTheSameChromeAsTheSameRoomOpenedFromHome() throws {
        let app = try FentonHomeApp.launchSignedIn(readyIdentifier: "nav.profile")
        XCTAssertTrue(app.navigationBars["Home"].appears(timeout: 10), "The app did not open on Home")
        openRoom(app)
        waitForLanding(app, "room from Home")
        shot(app, "1-room-from-home")
        assertLandedUnderHome(app, "room from Home")
        let fromHome = headerButtons(app)
        let title = pageTitle(app)
        backButton(app).tap()
        settleScreen()
        assertHomeRoot(app, "Back from the control")

        openSettings(app)
        openRoom(app)
        waitForLanding(app, "room from Settings")
        shot(app, "2-room-from-settings")
        assertLandedUnderHome(app, "room from Settings")
        XCTAssertEqual(pageTitle(app), title, "The same tile opened another page")
        XCTAssertEqual(headerButtons(app), fromHome, "The room landed from Settings draws other header buttons than the same room opened from Home")
    }

    // MARK: - Accessibility

    /// The landed room passes the repo's audit at the default text size and at an accessibility size.
    func testTheLandedRoomPassesTheAccessibilityAudit() throws {
        let app = try launchOnSettings()
        openRoom(app)
        waitForLanding(app, "room")
        assertLandedUnderHome(app, "room")
        try FentonHomeApp.audit(app) {
            let large = try self.launchOnSettings(arguments: FentonHomeApp.ax5)
            self.openRoom(large)
            self.waitForLanding(large, "room at AX5")
            self.shot(large, "audit-ax5-room")
            return large
        }
    }
}
