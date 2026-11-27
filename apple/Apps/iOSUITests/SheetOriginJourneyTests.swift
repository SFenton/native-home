import XCTest

/// The global-chrome sheet rule on the `sheet-origin` gallery (owner, 2026-11-18): a tile in a sheet that names a page closes every level of the sheet and
/// lands on the section stack with Quick Links and Profile, and Back leads to the page under the sheet with the sheet closed. A tile that names a level stays
/// in the sheet, which carries neither button. Demo ids and fixtures only, no sign-in; runs on iPhone, iPhone Duo and iPad.
@MainActor
final class SheetOriginJourneyTests: JourneyTestCase {
    // MARK: - Helpers

    private func launch(arguments: [String] = [], groupedReveal: Bool = false) -> XCUIApplication {
        let app = FentonHomeApp.makeApp()
        app.launchEnvironment["FENTON_GALLERY"] = "sheet-origin"
        app.launchEnvironment["FENTON_GALLERY_BACKDROP_FIXTURE"] = "1"
        if groupedReveal { app.launchEnvironment["FENTON_GALLERY_GROUPED_REVEAL"] = "1" }
        app.launchArguments += arguments
        _ = startApp(app)
        XCTAssertTrue(app.buttons["quickLinks.open"].appears(timeout: 20), "No Quick Links button on the root page")
        XCTAssertTrue(app.buttons["nav.profile"].exists, "No Profile button on the root page")
        settleScreen()
        return app
    }

    private func openSheet(_ app: XCUIApplication) {
        app.buttons["quickLinks.open"].tap()
        XCTAssertTrue(app.buttons["node-palette-local"].appears(timeout: 10), "The sheet did not open")
        settleScreen()
    }

    /// The system Back button; the folded Duo moves it to its rail, where only its identifier finds it.
    private func backButton(_ app: XCUIApplication) -> XCUIElement {
        let named = app.buttons["BackButton"].firstMatch
        return named.exists ? named : app.navigationBars.buttons.element(boundBy: 0)
    }

    /// Whether `first` reads before `second`: higher, or on the same row and further left (the Duo's folded rail runs top to bottom).
    private func reads(_ first: XCUIElement, before second: XCUIElement) -> Bool {
        let a = first.frame, b = second.frame
        return abs(a.midY - b.midY) > 8 ? a.midY < b.midY : a.midX < b.midX
    }

    // MARK: - Journey

    func testATileInASheetClosesItAndLandsWithTheGlobalChromeAndBackLeadsToThePageUnderIt() {
        let app = launch()
        openSheet(app)
        // The sheet carries neither button: the buttons behind it cannot be tapped.
        XCTAssertFalse(app.buttons["quickLinks.open"].isHittable, "Quick Links draws over the sheet")
        XCTAssertFalse(app.buttons["nav.profile"].isHittable, "Profile draws over the sheet")
        app.buttons["node-palette-local"].tap()
        XCTAssertTrue(app.buttons["quickLinks.open"].isHittable || app.buttons["quickLinks.open"].appears(timeout: 10))
        XCTAssertTrue(app.buttons["node-palette-local"].disappears(timeout: 10), "The sheet is still open")
        settleScreen()
        XCTAssertTrue(app.buttons["quickLinks.open"].isHittable, "The landed page has no Quick Links")
        XCTAssertTrue(app.buttons["nav.profile"].isHittable, "The landed page has no Profile")
        let back = backButton(app)
        XCTAssertTrue(back.exists, "The landed page has no Back")
        back.tap()
        settleScreen()
        XCTAssertTrue(app.buttons["quickLinks.open"].isHittable, "Back did not return to the root page")
        XCTAssertFalse(app.buttons["node-palette-local"].exists, "Back reopened the sheet")
    }

    func testATileThatNamesALevelStaysInTheSheetAndTheNextLevelDrawsNeitherButton() {
        let app = launch()
        openSheet(app)
        app.buttons["node-palette-level"].tap()
        XCTAssertTrue(app.buttons["node-level-next"].appears(timeout: 10), "The level did not open inside the sheet")
        XCTAssertFalse(app.buttons["nav.profile"].isHittable, "A level draws Profile")
        app.buttons["node-level-next"].tap()
        XCTAssertTrue(app.buttons["node-level-next"].disappears(timeout: 10) || app.staticTexts["Level Two"].appears(timeout: 10))
        XCTAssertFalse(app.buttons["quickLinks.open"].isHittable, "The second level draws Quick Links")
    }

    // MARK: - Accessibility

    /// A ready grouped sheet has no loading announcement and keeps its actions available after local Back.
    func testAReadyGroupedSheetKeepsItsAccessibleActionsAfterLocalBackAtAX5() {
        let app = launch(arguments: FentonHomeApp.ax5, groupedReveal: true)
        openSheet(app)
        let tile = app.buttons["node-palette-local"]
        let level = app.buttons["node-palette-level"]
        let arc = app.descendants(matching: .any)["contentGate.spinner"].firstMatch
        XCTAssertFalse(arc.exists)
        XCTAssertTrue(tile.label.contains("Inspect Here"))
        XCTAssertTrue(scrollTo(level, in: app))
        level.tap()
        XCTAssertTrue(app.buttons["node-level-next"].appears(timeout: 10))
        backButton(app).tap()
        XCTAssertTrue(tile.appears(timeout: 10))
        XCTAssertTrue(scrollTo(tile, in: app))
        XCTAssertFalse(arc.exists)
        XCTAssertTrue(tile.isEnabled)
    }

    /// Back is the first button of the landed page's bar, so VoiceOver reaches it first. VoiceOver's own focus is not observable from XCUITest: the order is
    /// the proxy. Whether the system focuses Back after the landing push is for the device check once the Back change (`gc-runtime-back`) has merged.
    func testBackIsTheFirstBarButtonOnTheLandedPageBeforeQuickLinksAndProfile() {
        let app = launch()
        openSheet(app)
        app.buttons["node-palette-local"].tap()
        XCTAssertTrue(app.buttons["node-palette-local"].disappears(timeout: 10))
        settleScreen()
        let back = backButton(app)
        XCTAssertTrue(back.exists, "The landed page has no Back")
        XCTAssertTrue(reads(back, before: app.buttons["quickLinks.open"]), "Back does not read before Quick Links")
        XCTAssertTrue(reads(back, before: app.buttons["nav.profile"]), "Back does not read before Profile")
    }

    func testTheSheetsTileIsAButtonNamedForItsTitle() {
        let app = launch()
        openSheet(app)
        let tile = app.buttons["node-palette-local"]
        XCTAssertTrue(tile.label.contains("Inspect Here"), "The tile reads \(tile.label)")
        XCTAssertTrue(tile.isEnabled)
    }
}
