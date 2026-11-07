import XCTest

/// The wallpaper covers the whole window (`.agents/patterns/page-backdrop.md` R7).
///
/// Owner, 2026-10-16 (iPhone 18 Pro, Release): "Blurred image does not take full phone space". The photo ended at the
/// bottom of the safe-area rect, so a band of the plain base color showed under the tab bar and the home indicator on
/// every tab root and pushed page. These journeys launch with `FENTON_BACKDROP_FIXTURE=1`, a bright synthetic photo
/// that stays several times brighter than the plain base color under every scrim stop, then sample the four corners
/// and four edge midpoints of a screenshot and fail on any that is as dark as the base: on each tab root and pushed
/// page, scrolled to the bottom, and after backgrounding the app and returning.
///
/// iPad runs portrait and (`TEST_RUNNER_FENTON_UITEST_ORIENTATION=landscape`) landscape; the folded iPhone Duo is
/// portrait like the iPhone. Skips without credentials.
@MainActor
final class WallpaperJourneyTests: JourneyTestCase {
    private func launch() throws -> XCUIApplication {
        // `nav.profile` is on every section root: the app reopens on the section the last run left (SceneStorage).
        let app = try FentonHomeApp.launchSignedIn(environment: ["FENTON_BACKDROP_FIXTURE": "1"], readyIdentifier: "nav.profile")
        openHome(in: app)
        return app
    }

    // MARK: - Sampling

    private func uncovered(in app: XCUIApplication) -> [String] { WallpaperSampling.uncovered(in: app) }

    /// Asserts the wallpaper reaches every sampled edge of the window. Polls for a few seconds: the fixture photo is
    /// rendered once at launch and a pushed page is still sliding in for a moment.
    private func assertCovered(_ app: XCUIApplication, _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        var missing = uncovered(in: app)
        let deadline = Date().addingTimeInterval(8)
        while !missing.isEmpty, Date() < deadline {
            usleep(500_000)
            missing = uncovered(in: app)
        }
        keepScreenshot(app, "wallpaper-\(name)-\(layout)")
        saveToCaptureFolder(name)
        XCTAssertTrue(missing.isEmpty, "\(name) (\(layout)): plain background at \(missing.joined(separator: ", "))", file: file, line: line)
    }

    /// With `FENTON_WALLPAPER_DIR` set, also writes the screenshot there (before and after comparisons).
    private func saveToCaptureFolder(_ name: String) {
        guard let folder = ProcessInfo.processInfo.environment["FENTON_WALLPAPER_DIR"] else { return }
        let url = URL(fileURLWithPath: folder).appendingPathComponent("\(name)-\(layout).png")
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: url)
    }

    // MARK: - Navigation

    private func openHome(in app: XCUIApplication) {
        openSection("home", title: "Home", in: app)
        XCTAssertTrue(app.navigationBars["Home"].appears(timeout: 15), "Home did not appear")
    }

    private func openRoot(_ section: String, _ title: String, in app: XCUIApplication) {
        openSection(section, title: title, in: app)
        XCTAssertTrue(app.navigationBars[title].appears(timeout: 15), "\(title) did not appear")
    }

    /// Drags the page up repeatedly so its end (and the bounce past it) is under the tab bar.
    private func scrollToBottom(_ app: XCUIApplication) {
        let window = app.windows.firstMatch
        for _ in 0..<10 {
            // Short of the trailing edge on the folded Duo, where the vertical tab bar sits.
            let from = window.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.8))
            from.press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.15)),
                       withVelocity: .fast, thenHoldForDuration: 0)
        }
        settleScreen()
    }

    /// Back: the bar's back button, which the folded iPhone Duo moves to its rail.
    private func goBack(in app: XCUIApplication) {
        let back = app.buttons["BackButton"].firstMatch
        if back.exists { back.tap() } else { app.navigationBars.buttons.element(boundBy: 0).tap() }
    }

    /// Backs out of a page pushed over Quick Links until its tiles show again.
    private func backToQuickLinks(in app: XCUIApplication) {
        let tiles = element("quickLinks.rooms", in: app)
        for _ in 0..<4 where !(tiles.exists && tiles.isHittable) {
            goBack(in: app)
            settleScreen()
        }
        XCTAssertTrue(tiles.appears(timeout: 10), "Back did not return to Quick Links")
    }

    /// Scrolls until `target` can be tapped, then taps it.
    private func tap(_ id: String, in app: XCUIApplication) {
        let target = element(id, in: app)
        XCTAssertTrue(target.appears(timeout: 15), "\(id) missing")
        let window = app.windows.firstMatch
        for _ in 0..<24 where !(target.exists && target.isHittable) {
            let from = window.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.65))
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: -220)),
                       withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        XCTAssertTrue(target.isHittable, "\(id) never came into view")
        target.tap()
    }

    private func openQuickLinks(in app: XCUIApplication) {
        app.buttons["quickLinks.open"].tap()
        XCTAssertTrue(element("quickLinks.rooms", in: app).appears(timeout: 10), "Quick Links did not open")
    }

    // MARK: - Journeys

    /// A tab root, at the top and scrolled to the bottom. `launch()` opens Home, so a later launch needs no reset.
    private func tabRootCoversTheWindow(_ section: String, _ title: String) throws {
        let app = try launch()
        if section != "home" { openRoot(section, title, in: app) }
        assertCovered(app, section)
        scrollToBottom(app)
        assertCovered(app, "\(section)-bottom")
    }

    func testWallpaperTabRootCoversHome() throws { try tabRootCoversTheWindow("home", "Home") }
    func testWallpaperTabRootCoversSecurity() throws { try tabRootCoversTheWindow("security", "Security") }
    func testWallpaperTabRootCoversClimate() throws { try tabRootCoversTheWindow("climate", "Climate") }
    func testWallpaperTabRootCoversChores() throws { try tabRootCoversTheWindow("chores", "Chores") }

    /// A to-do list pushed over Chores in the section stack, then (where Quick Links is a tab, not a sheet) a room, Food
    /// and Media pushed over Quick Links; each at the top and scrolled to the bottom. Regular width presents Quick
    /// Links as a sheet, which draws no wallpaper (R3), so its pages are skipped there.
    func testPushedPagesCoverTheWindow() throws {
        let app = try launch()
        openRoot("chores", "Chores", in: app)
        tap("chores.link.groceries", in: app)
        XCTAssertTrue(app.navigationBars["Groceries"].appears(timeout: 15), "Groceries did not open")
        assertCovered(app, "todo-list")
        scrollToBottom(app)
        assertCovered(app, "todo-list-bottom")
        goBack(in: app) // A pushed page has no menu or tab to leave through on regular width.
        XCTAssertTrue(app.navigationBars["Chores"].appears(timeout: 10), "Back did not return to Chores")
        openHome(in: app)

        openQuickLinks(in: app)
        if app.buttons["quickLinks.close"].exists {
            app.buttons["quickLinks.close"].tap()
            return
        }
        assertCovered(app, "quick-links")
        tap("quickLinks.rooms", in: app)
        let bedroom = try JourneyExpectations.current(for: .signedIn).value(.roomBedroomId)
        tap("rooms.\(bedroom)", in: app)
        XCTAssertTrue(element("room.scroll.\(bedroom)", in: app).appears(timeout: 15), "The bedroom page did not open")
        assertCovered(app, "room")
        scrollToBottom(app)
        assertCovered(app, "room-bottom")
        // Back out to the tiles rather than reopening Quick Links from the bar: the folded Duo's vertical bar was not
        // reachable from a pushed page that had been scrolled.
        for (page, scroll) in [("food", "food.scroll"), ("media", "media.scroll")] {
            backToQuickLinks(in: app)
            tap("quickLinks.\(page)", in: app)
            XCTAssertTrue(element(scroll, in: app).appears(timeout: 15), "\(page) did not open")
            assertCovered(app, page)
            scrollToBottom(app)
            assertCovered(app, "\(page)-bottom")
        }
        backToQuickLinks(in: app)
        openHome(in: app)
    }

    /// Sending the app to the background and returning keeps the wallpaper: Home, then a pushed page.
    func testBackgroundAndForegroundKeepTheWindowCovered() throws {
        let app = try launch()
        assertCovered(app, "before-background")
        XCUIDevice.shared.press(.home)
        settleScreen()
        app.activate()
        XCTAssertTrue(app.navigationBars["Home"].appears(timeout: 15), "Home did not return")
        assertCovered(app, "after-foreground")
        scrollToBottom(app)
        XCUIDevice.shared.press(.home)
        settleScreen()
        app.activate()
        settleScreen()
        assertCovered(app, "after-foreground-scrolled")
    }
}
