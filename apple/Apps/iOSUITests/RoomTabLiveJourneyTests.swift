import XCTest

/// A homed page opens under its home tab (`.agents/decisions/2026-11-19-homed-page-tab.md`): from Settings, Quick Links, the Rooms tile and a
/// room, the sheet closes and the room lands on top of Home's stack, with Back and the same chrome as the room opened from Home (the live publication decides whether a room page draws Quick Links and Profile); Back leads to the page below it on Home
/// and Settings is where it was left, with no sheet. A second room appends to Home's stack, and Food, authored under Home, lands there too.
///
/// Live: needs `TEST_RUNNER_FENTON_HASS_*` (the `--env shell` runner passes them through; they are never printed) and skips without them. No room
/// name or entity id lives in the repository: the rooms are the first two room tiles the live Rooms level offers, found by what they are (a tile
/// that is not the sheet's own chrome) and compared by the identifier and title they carry at run time. It is read only: it only navigates. Runs on
/// iPhone, iPhone Duo and iPad.
@MainActor
final class RoomTabLiveJourneyTests: JourneyTestCase {
    // MARK: - Helpers

    /// `iphone`, `iphoneduo` or `ipad`, for screenshot names.
    private var family: String { "\(FentonHomeApp.family)".lowercased() }

    /// Writes what the screen exposes (type, identifier, label, selected, frame of the bars, buttons and headings) to the shots folder and
    /// attaches it, so a failure shows which identifiers the live app really draws. One snapshot, not a query per element: per-element reads
    /// took minutes on a long page at an accessibility size. Read at run time, never committed.
    private func dump(_ app: XCUIApplication, _ step: String) {
        var lines: [String] = []
        let kinds: Set<XCUIElement.ElementType> = [.tabBar, .toolbar, .navigationBar, .button, .cell, .staticText]
        func walk(_ node: XCUIElementSnapshot) {
            if kinds.contains(node.elementType), lines.count < 300 {
                lines.append("\(node.elementType.rawValue) id=\(node.identifier) label=\(node.label) sel=\(node.isSelected) frame=\(node.frame)")
            }
            node.children.forEach(walk)
        }
        if let snapshot = try? app.snapshot() { walk(snapshot) }
        let text = lines.joined(separator: "\n")
        let attachment = XCTAttachment(string: text)
        attachment.name = "tree-\(step)"
        attachment.lifetime = .keepAlways
        add(attachment)
        if let shots = ProcessInfo.processInfo.environment["FENTON_SHOTS_DIR"], !shots.isEmpty {
            try? FileManager.default.createDirectory(atPath: shots, withIntermediateDirectories: true)
            try? text.write(toFile: shots + "/room-tab-\(family)-tree-\(step).txt", atomically: true, encoding: .utf8)
        }
    }

    private func shot(_ app: XCUIApplication, _ step: String) {
        settleScreen()
        dump(app, step)
        keepScreenshot(app, "room-tab-\(family)-\(step)")
    }

    /// A signed-in launch that stops on Settings, the tab the journeys start from.
    private func launchOnSettings(arguments: [String] = []) throws -> XCUIApplication {
        let app = try FentonHomeApp.launchSignedIn(arguments: arguments, readyIdentifier: "nav.profile")
        dump(app, "launched")
        app.openAccountSettings()
        settleScreen()
        dump(app, "settings")
        return app
    }

    /// The system Back button; the folded Duo moves it to its rail, where only its identifier finds it.
    private func backButton(_ app: XCUIApplication) -> XCUIElement {
        let named = app.buttons["BackButton"].firstMatch
        return named.exists ? named : app.navigationBars.buttons.element(boundBy: 0)
    }

    /// Whether a sheet is open: its Close button (`server-ui.sheet.close`) is on screen.
    private func sheetIsOpen(_ app: XCUIApplication) -> Bool {
        let close = app.buttons["server-ui.sheet.close"]
        return close.exists && close.isHittable
    }

    private func openQuickLinks(_ app: XCUIApplication) {
        let button = app.buttons["quickLinks.open"]
        _ = button.appears(timeout: 10)
        dump(app, "pre-quick-links")
        XCTAssertTrue(button.exists && button.isHittable, "No Quick Links on the page")
        button.tap()
        let end = Date().addingTimeInterval(10)
        while !sheetIsOpen(app), Date() < end { usleep(100_000) }
        settleScreen()
        dump(app, "quick-links-sheet")
        XCTAssertTrue(sheetIsOpen(app), "Quick Links did not open a sheet")
    }

    /// A tile of the open sheet by its identifier (`quick-link-rooms`, `quick-link-food`), scrolled into view.
    private func tile(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        let button = app.buttons[identifier]
        _ = button.appears(timeout: 10)
        if !(button.exists && button.isHittable) {
            scrollTo(button, in: app, scroller: { app.collectionViews.allElementsBoundByIndex.last ?? app.scrollViews.firstMatch })
        }
        return button
    }

    /// The room tiles of the Rooms level in reading order: the hittable buttons the level names `rooms-navigation.room-destination-<n>`.
    private func roomTiles(_ app: XCUIApplication) -> [XCUIElement] {
        let tiles = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'rooms-navigation.room-destination-'"))
            .allElementsBoundByIndex.filter { $0.exists && $0.isHittable }
        return tiles.sorted { $0.frame.minY == $1.frame.minY ? $0.frame.minX < $1.frame.minX : $0.frame.minY < $1.frame.minY }
    }

    /// Opens Quick Links and the Rooms tile (which stays in the sheet), leaving the Rooms level showing.
    private func showRoomsLevel(_ app: XCUIApplication) {
        openQuickLinks(app)
        let rooms = tile("quick-link-rooms", in: app)
        XCTAssertTrue(rooms.exists, "Quick Links has no Rooms tile")
        rooms.tap()
        settleScreen()
        dump(app, "rooms-level")
        XCTAssertTrue(sheetIsOpen(app), "The Rooms tile closed the sheet: it names a level, and stays in it")
        XCTAssertFalse(roomTiles(app).isEmpty, "The Rooms level offers no room tile")
    }

    /// Opens a room through Quick Links and Rooms.
    /// - Parameters:
    ///   - index: Which room tile, in reading order.
    /// - Returns: The room tile's identifier, to tell rooms apart.
    @discardableResult
    private func openRoom(_ app: XCUIApplication, at index: Int = 0) -> String {
        showRoomsLevel(app)
        let tiles = roomTiles(app)
        XCTAssertGreaterThan(tiles.count, index, "The Rooms level offers \(tiles.count) room tiles, need \(index + 1)")
        let id = tiles[index].identifier
        tiles[index].tap()
        return id
    }

    /// Waits for the sheet to close and the landed page to draw its chrome.
    private func waitForLanding(_ app: XCUIApplication, _ what: String) {
        let end = Date().addingTimeInterval(15)
        while (sheetIsOpen(app) || !backButton(app).exists), Date() < end { usleep(100_000) }
        settleScreen()
        dump(app, "landed")
        keepScreenshot(app, "room-tab-\(family)-landed-\(what.replacingOccurrences(of: " ", with: "-"))")
        XCTAssertFalse(sheetIsOpen(app), "\(what): the sheet is still open")
    }

    /// The title of the page on top: its navigation bar, else its first text. Compared, never printed.
    private func pageTitle(_ app: XCUIApplication) -> String {
        let bar = app.navigationBars.allElementsBoundByIndex.first { !$0.identifier.isEmpty && $0.identifier != "Settings" }
        if let bar { return bar.identifier }
        return app.staticTexts.allElementsBoundByIndex.first { !$0.label.isEmpty }?.label ?? ""
    }

    /// Asserts a page landed under Home: Home is the selected tab (where the window draws a bar), the page has Back and a title, and Settings is not
    /// the page showing. Quick Links and Profile are not required: whether a page draws them is the live publication's choice (see ``headerButtons(_:)``).
    private func assertLandedUnderHome(_ app: XCUIApplication, _ what: String) {
        let home = app.barItem("Home")
        if home.exists { XCTAssertTrue(home.isSelected, "\(what): Home is not the selected tab") }
        XCTAssertTrue(backButton(app).exists, "\(what): no Back")
        XCTAssertFalse(pageTitle(app).isEmpty, "\(what): the page has no title")
        XCTAssertFalse(app.navigationBars["Settings"].isHittable, "\(what): the page is still under Settings")
    }

    /// Whether the page on top draws Quick Links and Profile, to compare one opening of a room with another.
    private func headerButtons(_ app: XCUIApplication) -> [Bool] {
        [app.buttons["quickLinks.open"].isHittable, app.buttons["nav.profile"].isHittable]
    }

    private func assertHomeRoot(_ app: XCUIApplication, _ what: String) {
        XCTAssertTrue(app.navigationBars["Home"].appears(timeout: 10), "\(what): Home's root does not show")
        XCTAssertTrue(app.buttons["quickLinks.open"].isHittable, "\(what): Home's root has no Quick Links")
        let home = app.barItem("Home")
        if home.exists { XCTAssertTrue(home.isSelected, "\(what): Home is not the selected tab") }
        XCTAssertFalse(app.buttons["BackButton"].exists, "\(what): the root shows a Back")
    }

    private func assertSettingsAsLeft(_ app: XCUIApplication, _ what: String) {
        app.openAccountSettings()
        XCTAssertTrue(app.navigationBars["Settings"].appears(timeout: 10), "\(what): Settings shows no page")
        XCTAssertFalse(sheetIsOpen(app), "\(what): a sheet is still over Settings")
        XCTAssertTrue(app.buttons["quickLinks.open"].isHittable, "\(what): Settings has no Quick Links")
        XCTAssertFalse(app.buttons["BackButton"].exists, "\(what): Settings shows a Back")
    }

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

        app.openAccountSettings()
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
