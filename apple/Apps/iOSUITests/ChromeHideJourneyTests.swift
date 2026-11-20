import XCTest

/// A page that hides the global chrome, on the `chrome-hide` gallery: the root page shows the tab navigator, Quick Links and Profile; the page its tile
/// opens hides all three, keeps Back, and Back returns them. The navigator is the floating bar on iPhone and the unfolded Duo in portrait, the rail on the
/// folded Duo and in landscape, and the top bar on iPad. Demo ids and fixtures only, no sign-in; runs on iPhone, iPhone Duo and iPad.
@MainActor
final class ChromeHideJourneyTests: JourneyTestCase {
    // MARK: - Helpers

    private func launch(arguments: [String] = []) -> XCUIApplication {
        let app = FentonHomeApp.makeApp()
        app.launchEnvironment["FENTON_GALLERY"] = "chrome-hide"
        app.launchEnvironment["FENTON_GALLERY_BACKDROP_FIXTURE"] = "1"
        app.launchArguments += arguments
        _ = startApp(app)
        XCTAssertTrue(app.buttons["quickLinks.open"].appears(timeout: 20), "No Quick Links button on the root page")
        XCTAssertTrue(app.buttons["nav.profile"].exists, "No Profile button on the root page")
        settleScreen()
        return app
    }

    /// Whether the tab navigator draws: the other tab's item is in the tree and on screen, in the bar, the top bar or the rail.
    private func tabsShown(_ app: XCUIApplication, waiting: TimeInterval = 10) -> Bool {
        let end = Date().addingTimeInterval(waiting)
        while !isReachable(shelfTab(app)), Date() < end { usleep(200_000) }
        return isReachable(shelfTab(app))
    }

    /// The other tab's item: in the bottom bar or the rail by its title, in the iPad's top bar (inside the navigation bar) by its id.
    private func shelfTab(_ app: XCUIApplication) -> XCUIElement {
        let bar = app.barItem("Shelf")
        return bar.exists ? bar : app.buttons["tab-beta"].firstMatch
    }

    private func openHidingPage(_ app: XCUIApplication) {
        let tile = app.buttons["node-open-echo"]
        XCTAssertTrue(tile.appears(timeout: 10), "No tile that opens the page")
        tile.tap()
        XCTAssertTrue(app.staticTexts["Sample Detail"].appears(timeout: 10), "The page did not open")
        settleScreen()
    }

    /// The system Back button; the folded Duo moves it to its rail, where only its identifier finds it.
    private func backButton(_ app: XCUIApplication) -> XCUIElement {
        let named = app.buttons["BackButton"].firstMatch
        return named.exists ? named : app.navigationBars.buttons.element(boundBy: 0)
    }

    // MARK: - Journey

    func testAPageThatHidesTheChromeDrawsWithoutItAndBackBringsItBack() {
        let app = launch()
        XCTAssertTrue(tabsShown(app), "The root page has no tab navigator")
        openHidingPage(app)
        XCTAssertTrue(shelfTab(app).disappears(timeout: 10) || !tabsShown(app, waiting: 0), "The tab navigator stays on the hiding page")
        XCTAssertFalse(app.buttons["quickLinks.open"].exists && app.buttons["quickLinks.open"].isHittable, "Quick Links draws on the hiding page")
        XCTAssertFalse(app.buttons["nav.profile"].exists && app.buttons["nav.profile"].isHittable, "Profile draws on the hiding page")
        let back = backButton(app)
        XCTAssertTrue(back.exists, "The hiding page has no Back")
        back.tap()
        settleScreen()
        XCTAssertTrue(app.buttons["quickLinks.open"].appears(timeout: 10), "Back did not return Quick Links")
        XCTAssertTrue(app.buttons["nav.profile"].isHittable, "Back did not return Profile")
        XCTAssertTrue(tabsShown(app), "Back did not return the tab navigator")
    }

    // MARK: - Accessibility

    func testHiddenChromeIsAbsentFromTheTreeAndBackIsReachable() {
        let app = launch()
        openHidingPage(app)
        XCTAssertTrue(app.buttons["quickLinks.open"].disappears(timeout: 10), "Quick Links is in the tree on the hiding page")
        XCTAssertFalse(app.buttons["nav.profile"].exists, "Profile is in the tree on the hiding page")
        XCTAssertFalse(tabsShown(app, waiting: 0), "The tab navigator is reachable on the hiding page")
        let back = backButton(app)
        XCTAssertTrue(back.exists && back.isHittable, "Back is not reachable on the hiding page")
        XCTAssertTrue(back.isEnabled)
    }
}
