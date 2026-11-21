import XCTest

/// The helpers the live room journeys share (`RoomTabLiveJourneyTests`, `RoomChromeLiveJourneyTests`): a signed-in launch, Settings, Quick Links,
/// the Rooms level, a room's landing and the chrome checks. Live: needs `TEST_RUNNER_FENTON_HASS_*` (the `--env shell` runner passes them
/// through; they are never printed). Read only: it only navigates.
@MainActor
class RoomLiveJourneyTestCase: JourneyTestCase {
    // MARK: - Helpers

    /// `iphone`, `iphoneduo` or `ipad`, for screenshot names.
    var family: String { "\(FentonHomeApp.family)".lowercased() }

    /// Writes what the screen exposes (type, identifier, label, selected, frame of the bars, buttons and headings) to the shots folder and
    /// attaches it, so a failure shows which identifiers the live app really draws. One snapshot, not a query per element: per-element reads
    /// took minutes on a long page at an accessibility size. Read at run time, never committed.
    func dump(_ app: XCUIApplication, _ step: String) {
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

    func shot(_ app: XCUIApplication, _ step: String) {
        settleScreen()
        dump(app, step)
        keepScreenshot(app, "room-tab-\(family)-\(step)")
    }

    /// Opens Settings. iPad draws the tabs in a top bar with no "Settings" navigation bar, so there the `tab-settings` item is tapped and
    /// checked (selected, and the Settings page's first row, `settings-vacation`, on screen); iPhone and Duo keep the shared account-navigation path.
    func openSettings(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        guard family == "ipad" else { app.openAccountSettings(file: file, line: line); return }
        let item = app.buttons["tab-settings"].firstMatch
        XCTAssertTrue(item.appears(timeout: 10), "No Settings tab in the top bar", file: file, line: line)
        if !item.isSelected { item.tap() }
        let selected = NSPredicate(format: "isSelected == true")
        wait(for: [expectation(for: selected, evaluatedWith: item)], timeout: 10)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "settings-vacation").firstMatch.appears(timeout: 10),
                      "Settings did not open", file: file, line: line)
    }

    /// The system Back button; the folded Duo moves it to its rail, where only its identifier finds it.
    func backButton(_ app: XCUIApplication) -> XCUIElement {
        let named = app.buttons["BackButton"].firstMatch
        return named.exists ? named : app.navigationBars.buttons.element(boundBy: 0)
    }

    /// Whether a sheet is open: its Close button (`server-ui.sheet.close`) is on screen.
    func sheetIsOpen(_ app: XCUIApplication) -> Bool {
        let close = app.buttons["server-ui.sheet.close"]
        return close.exists && close.isHittable
    }

    func openQuickLinks(_ app: XCUIApplication) {
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
    func tile(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        let button = app.buttons[identifier]
        _ = button.appears(timeout: 10)
        if !(button.exists && button.isHittable) {
            scrollTo(button, in: app, scroller: { app.collectionViews.allElementsBoundByIndex.last ?? app.scrollViews.firstMatch })
        }
        return button
    }

    /// The room tiles of the Rooms level in reading order: the hittable buttons the level names `rooms-navigation.room-destination-<n>`.
    func roomTiles(_ app: XCUIApplication) -> [XCUIElement] {
        let tiles = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'rooms-navigation.room-destination-'"))
            .allElementsBoundByIndex.filter { $0.exists && $0.isHittable }
        return tiles.sorted { $0.frame.minY == $1.frame.minY ? $0.frame.minX < $1.frame.minX : $0.frame.minY < $1.frame.minY }
    }

    /// Opens Quick Links and the Rooms tile (which stays in the sheet), leaving the Rooms level showing.
    func showRoomsLevel(_ app: XCUIApplication) {
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
    func openRoom(_ app: XCUIApplication, at index: Int = 0) -> String {
        showRoomsLevel(app)
        let tiles = roomTiles(app)
        XCTAssertGreaterThan(tiles.count, index, "The Rooms level offers \(tiles.count) room tiles, need \(index + 1)")
        let id = tiles[index].identifier
        tiles[index].tap()
        return id
    }

    /// Waits for the sheet to close and the landed page to draw its chrome.
    func waitForLanding(_ app: XCUIApplication, _ what: String) {
        let end = Date().addingTimeInterval(15)
        while (sheetIsOpen(app) || !backButton(app).exists), Date() < end { usleep(100_000) }
        settleScreen()
        dump(app, "landed")
        keepScreenshot(app, "room-tab-\(family)-landed-\(what.replacingOccurrences(of: " ", with: "-"))")
        XCTAssertFalse(sheetIsOpen(app), "\(what): the sheet is still open")
    }

    /// The title of the page on top: its navigation bar, else its first text. Compared, never printed.
    func pageTitle(_ app: XCUIApplication) -> String {
        let bar = app.navigationBars.allElementsBoundByIndex.first { !$0.identifier.isEmpty && $0.identifier != "Settings" }
        if let bar { return bar.identifier }
        return app.staticTexts.allElementsBoundByIndex.first { !$0.label.isEmpty }?.label ?? ""
    }

    /// Asserts a page landed under Home: Home is the selected tab (where the window draws a bar), the page has Back and a title, and Settings is not
    /// the page showing. Quick Links and Profile are not required: whether a page draws them is the live publication's choice (see ``headerButtons(_:)``).
    func assertLandedUnderHome(_ app: XCUIApplication, _ what: String) {
        let home = app.barItem("Home")
        if home.exists { XCTAssertTrue(home.isSelected, "\(what): Home is not the selected tab") }
        XCTAssertTrue(backButton(app).exists, "\(what): no Back")
        XCTAssertFalse(pageTitle(app).isEmpty, "\(what): the page has no title")
        XCTAssertFalse(app.navigationBars["Settings"].isHittable, "\(what): the page is still under Settings")
    }

    /// Whether the page on top draws Quick Links and Profile, to compare one opening of a room with another.
    func headerButtons(_ app: XCUIApplication) -> [Bool] {
        [app.buttons["quickLinks.open"].isHittable, app.buttons["nav.profile"].isHittable]
    }

    func assertHomeRoot(_ app: XCUIApplication, _ what: String) {
        XCTAssertTrue(app.navigationBars["Home"].appears(timeout: 10), "\(what): Home's root does not show")
        XCTAssertTrue(app.buttons["quickLinks.open"].isHittable, "\(what): Home's root has no Quick Links")
        let home = app.barItem("Home")
        if home.exists { XCTAssertTrue(home.isSelected, "\(what): Home is not the selected tab") }
        XCTAssertFalse(app.buttons["BackButton"].exists, "\(what): the root shows a Back")
    }

    func assertSettingsAsLeft(_ app: XCUIApplication, _ what: String) {
        openSettings(app)
        XCTAssertTrue(app.navigationBars["Settings"].appears(timeout: 10), "\(what): Settings shows no page")
        XCTAssertFalse(sheetIsOpen(app), "\(what): a sheet is still over Settings")
        XCTAssertTrue(app.buttons["quickLinks.open"].isHittable, "\(what): Settings has no Quick Links")
        XCTAssertFalse(app.buttons["BackButton"].exists, "\(what): Settings shows a Back")
    }

    /// Opens a room by the label its Rooms-level tile carries, scrolling the level to it.
    /// - Parameters:
    ///   - label: The tile's visible name.
    func openRoom(_ app: XCUIApplication, named label: String) {
        openQuickLinks(app)
        let rooms = tile("quick-link-rooms", in: app)
        XCTAssertTrue(rooms.exists, "Quick Links has no Rooms tile")
        rooms.tap()
        settleScreen()
        let target = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'rooms-navigation.room-destination-' AND label == %@", label)).firstMatch
        XCTAssertTrue(target.appears(timeout: 10), "The Rooms level offers no \(label) tile")
        if !(target.exists && target.isHittable) {
            scrollTo(target, in: app, scroller: { app.collectionViews.allElementsBoundByIndex.last ?? app.scrollViews.firstMatch })
        }
        XCTAssertTrue(target.isHittable, "\(label) cannot be reached in the Rooms level")
        target.tap()
    }
}
