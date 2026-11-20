import XCTest

/// A page that hides the global chrome, on the `chrome-hide` gallery (`FENTON_GALLERY_CASE`, see `UKChromeHideGallery`): the root page shows the tab
/// navigator, Quick Links and Profile; the page its tile opens hides some or all of them, keeps Back, and Back returns them.
///
/// The navigator is the floating bar on the iPhone and the unfolded Duo in portrait, the rail on the folded Duo and in landscape, and the top bar on the
/// iPad. Every test reads the window, never the device, so the same class runs in every pose the simulator is put in (the Duo folded or unfolded, the iPad
/// portrait or landscape through `FENTON_UITEST_ORIENTATION=landscape`). The `AX5` tests launch at the largest text size and the `ReduceMotion` tests with
/// Reduce Motion on. Each test keeps a screenshot named `<case>-<step>` (`root`, `hidden`, `back`), with `-ax5` or `-reduce-motion` after the case.
/// Demo ids and fixtures only, no sign-in.
@MainActor
final class ChromeHideJourneyTests: JourneyTestCase {
    // MARK: - Cases

    /// What a case hides on the page its tile opens.
    private struct Case {
        let name: String
        let gallery: String
        let hidesTabs: Bool
        let hidesItems: Bool
    }

    private static let tabs = Case(name: "tabs", gallery: "tabs", hidesTabs: true, hidesItems: false)
    private static let items = Case(name: "items", gallery: "items", hidesTabs: false, hidesItems: true)
    private static let both = Case(name: "both", gallery: "both", hidesTabs: true, hidesItems: true)
    private static let rootOnly = Case(name: "root-only", gallery: "root-only", hidesTabs: true, hidesItems: false)
    private static let columns = Case(name: "columns", gallery: "columns", hidesTabs: true, hidesItems: true)

    // MARK: - Helpers

    private func launch(_ chosen: Case, arguments: [String] = [], reduceMotion: Bool = false) -> XCUIApplication {
        let app = FentonHomeApp.makeApp()
        app.launchEnvironment["FENTON_GALLERY"] = "chrome-hide"
        app.launchEnvironment["FENTON_GALLERY_CASE"] = chosen.gallery
        app.launchEnvironment["FENTON_GALLERY_BACKDROP_FIXTURE"] = "1"
        if reduceMotion { app.launchEnvironment.merge(FentonHomeApp.SystemSetting.environment([.reduceMotion])) { _, new in new } }
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

    private func itemsShown(_ app: XCUIApplication) -> Bool {
        isReachable(app.buttons["quickLinks.open"]) && isReachable(app.buttons["nav.profile"])
    }

    private func openHidingPage(_ app: XCUIApplication) {
        let tile = app.buttons["node-open-echo"]
        XCTAssertTrue(tile.appears(timeout: 10), "No tile that opens the page")
        tile.tap()
        XCTAssertTrue(app.staticTexts["Sample Detail"].appears(timeout: 10), "The page did not open")
        settleScreen()
    }

    /// The way back: the system Back button (the folded Duo moves it to its rail, where only its identifier finds it), or, in columns, the detail
    /// column's own Back or Close.
    private func backButton(_ app: XCUIApplication) -> XCUIElement {
        for id in ["BackButton", "split.back", "split.close"] where app.buttons[id].firstMatch.exists { return app.buttons[id].firstMatch }
        return app.navigationBars.buttons.element(boundBy: 0)
    }

    /// Opens the page, checks what it hides and what it keeps, and goes Back, keeping a screenshot at each step.
    private func journey(_ chosen: Case, arguments: [String] = [], reduceMotion: Bool = false, suffix: String = "") {
        let label = chosen.name + suffix
        let app = launch(chosen, arguments: arguments, reduceMotion: reduceMotion)
        XCTAssertTrue(tabsShown(app), "The root page has no tab navigator")
        XCTAssertTrue(itemsShown(app), "The root page lacks Quick Links or Profile")
        keepScreenshot(app, "\(label)-root")
        openHidingPage(app)
        if chosen.hidesTabs {
            XCTAssertTrue(shelfTab(app).disappears(timeout: 10) || !tabsShown(app, waiting: 0), "The tab navigator stays on the hiding page")
        } else {
            XCTAssertTrue(tabsShown(app), "The page hides the tabs it should keep")
        }
        if chosen.hidesItems {
            XCTAssertTrue(app.buttons["quickLinks.open"].disappears(timeout: 10) || !isReachable(app.buttons["quickLinks.open"]), "Quick Links draws on the hiding page")
            XCTAssertFalse(isReachable(app.buttons["nav.profile"]), "Profile draws on the hiding page")
        } else {
            XCTAssertTrue(itemsShown(app), "The page hides the buttons it should keep")
        }
        let back = backButton(app)
        XCTAssertTrue(back.exists && back.isHittable, "The hiding page has no Back")
        keepScreenshot(app, "\(label)-hidden")
        back.tap()
        settleScreen()
        XCTAssertTrue(app.buttons["quickLinks.open"].appears(timeout: 10), "Back did not return Quick Links")
        XCTAssertTrue(itemsShown(app), "Back did not return Profile")
        XCTAssertTrue(tabsShown(app), "Back did not return the tab navigator")
        keepScreenshot(app, "\(label)-back")
    }

    // MARK: - Journeys

    func testATabsOnlyPageHidesTheTabsAndKeepsTheButtons() { journey(Self.tabs) }
    func testAnItemsOnlyPageHidesQuickLinksAndProfileAndKeepsTheTabs() { journey(Self.items) }
    func testAPageThatHidesTheChromeDrawsWithoutItAndBackBringsItBack() { journey(Self.both) }
    func testRootOnlyHidesTheTabsOnAPushedPageAndKeepsTheButtons() { journey(Self.rootOnly) }
    /// In a window wide enough for columns the page opened last decides; in a narrow one it is a stack with the same answer.
    func testInColumnsThePageOpenedLastDecidesWhatIsHidden() { journey(Self.columns) }

    // MARK: - Text size and Reduce Motion

    func testATabsOnlyPageAtAX5() { journey(Self.tabs, arguments: FentonHomeApp.ax5, suffix: "-ax5") }
    func testAnItemsOnlyPageAtAX5() { journey(Self.items, arguments: FentonHomeApp.ax5, suffix: "-ax5") }
    func testAPageThatHidesBothAtAX5() { journey(Self.both, arguments: FentonHomeApp.ax5, suffix: "-ax5") }
    func testRootOnlyAtAX5() { journey(Self.rootOnly, arguments: FentonHomeApp.ax5, suffix: "-ax5") }
    func testColumnsAtAX5() { journey(Self.columns, arguments: FentonHomeApp.ax5, suffix: "-ax5") }

    func testATabsOnlyPageWithReduceMotion() { journey(Self.tabs, reduceMotion: true, suffix: "-reduce-motion") }
    func testAnItemsOnlyPageWithReduceMotion() { journey(Self.items, reduceMotion: true, suffix: "-reduce-motion") }
    func testAPageThatHidesBothWithReduceMotion() { journey(Self.both, reduceMotion: true, suffix: "-reduce-motion") }
    func testRootOnlyWithReduceMotion() { journey(Self.rootOnly, reduceMotion: true, suffix: "-reduce-motion") }
    func testColumnsWithReduceMotion() { journey(Self.columns, reduceMotion: true, suffix: "-reduce-motion") }

    // MARK: - Accessibility

    func testHiddenChromeIsAbsentFromTheTreeAndBackIsReachable() {
        let app = launch(Self.both)
        openHidingPage(app)
        XCTAssertTrue(app.buttons["quickLinks.open"].disappears(timeout: 10), "Quick Links is in the tree on the hiding page")
        XCTAssertFalse(app.buttons["nav.profile"].exists, "Profile is in the tree on the hiding page")
        XCTAssertFalse(tabsShown(app, waiting: 0), "The tab navigator is reachable on the hiding page")
        let back = backButton(app)
        XCTAssertTrue(back.exists && back.isHittable, "Back is not reachable on the hiding page")
        XCTAssertTrue(back.isEnabled)
    }
}
