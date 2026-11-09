import XCTest

/// Chores quick-link pages and Food spaces as columns (owner, 2026-11-01): where the window splits (iPad landscape, the unfolded Duo in
/// landscape) a quick link or a Food space opens beside the list that opened it, with the title as content and Close in the section
/// bar's column group; elsewhere it is pushed on the stack. Both are navigator routes (`ShellRoute.chores`, `.foodSpace`), so a rotation
/// moves the same page between a column and a push, and a page opened locally two deep (Vacation Mode under Vacation) goes back into
/// the columns when the window widens. Rules: `.agents/design/apple/split-view.md`, "Column navigation". Signed in (fixture recipes).
@MainActor
final class ColumnRoutesJourneyTests: ChoresJourneyTestCase {
    override class var rotatingFamilies: [FentonHomeApp.Family] { [.iPad] }

    /// Whether this window splits: iPad in landscape, the Duo only unfolded in landscape (951 pt wide; folded it is single-page).
    private func windowSplits(_ app: XCUIApplication) -> Bool {
        let window = app.windows.firstMatch.frame
        switch FentonHomeApp.family {
        case .iPhone: return false
        case .iPad: return window.width > window.height
        case .iPhoneDuo: return window.width > window.height && window.width >= 900
        }
    }

    private func landscape() {
        if FentonHomeApp.family == .iPad { XCUIDevice.shared.orientation = .landscapeLeft }
    }

    private func openSection(_ section: String, title: String, in app: XCUIApplication) {
        let item = app.barItem(title)
        if item.appears(timeout: 5), item.isHittable {
            item.tap()
        } else {
            app.buttons["nav.open"].tap()
            XCTAssertTrue(element("nav.flyout", in: app).appears(timeout: 3), "Flyout did not open")
            app.buttons["nav.\(section)"].tap()
        }
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        keepScreenshot(app, "columns-\(name)-\(FentonHomeApp.family)-\(app.windows.firstMatch.frame.width > app.windows.firstMatch.frame.height ? "landscape" : "portrait")")
    }

    /// A Chores quick link: beside the list in a splitting window (Close, the list still visible, the title in the page), a push elsewhere.
    func testChoresQuickLinkOpensAsAColumnWhereTheWindowSplits() throws {
        landscape()
        let app = try FentonHomeApp.launchSignedIn(environment: ["FENTON_FOOD_FIXTURES": "1"])
        openSection("chores", title: "Chores", in: app)
        let link = element("chores.link.unassigned-chores", in: app)
        XCTAssertTrue(link.appears(timeout: 20), "Quick links missing")
        let splits = windowSplits(app)
        reveal(link, in: app).tap()
        XCTAssertTrue(element("todo.page.unassigned-chores", in: app).appears(timeout: 10), "The page did not open")
        settleScreen()
        shot(app, "chores")
        if splits {
            XCTAssertTrue(app.buttons["split.close"].appears(timeout: 5), "No Close in the column group")
            XCTAssertTrue(element("todo.page.chores", in: app).exists, "The list left the window")
            // Geometric, not a constant: the page sits to the right of the list's frame (the Duo splits at the free-space midpoint, not the
            // window's).
            let list = element("todo.page.chores", in: app).frame
            let page = element("todo.page.unassigned-chores", in: app).frame
            XCTAssertTrue(page.minX >= list.maxX - 1 && page.minX > list.minX && page.maxX <= app.windows.firstMatch.frame.maxX + 1, "The page is not the right column (list \(list), page \(page))")
            app.buttons["split.close"].tap()
            XCTAssertTrue(element("todo.pane.placeholder", in: app).appears(timeout: 5) || element("todo.pane", in: app).exists || !element("todo.page.unassigned-chores", in: app).exists, "Close left the page open")
            XCTAssertTrue(link.appears(timeout: 5))
        } else {
            XCTAssertFalse(app.buttons["split.close"].exists, "A single-page window shows columns")
            XCTAssertTrue(app.buttons["BackButton"].firstMatch.exists || app.navigationBars.buttons.firstMatch.exists, "No Back on the pushed page")
        }
    }

    private func addButtons(_ app: XCUIApplication) -> XCUIElementQuery { app.buttons.matching(identifier: "fab.add") }

    /// Where columns show, Chores has ONE Add button, floating at the bottom-right over both columns, that adds to the page the person
    /// is looking at (owner, 2026-11-02); a single-page window keeps each page's own.
    func testChoresHasOneAddButtonOverTheColumns() throws {
        landscape()
        let app = try FentonHomeApp.launchSignedIn(environment: ["FENTON_FOOD_FIXTURES": "1"])
        openSection("chores", title: "Chores", in: app)
        let link = element("chores.link.groceries", in: app)
        XCTAssertTrue(link.appears(timeout: 20), "Quick links missing")
        XCTAssertTrue(app.buttons["fab.add"].appears(timeout: 10), "No Add Task on the Chores list")
        XCTAssertEqual(app.buttons["fab.add"].label, "Add Task")
        let splits = windowSplits(app)
        let window = app.windows.firstMatch.frame
        if splits {
            XCTAssertEqual(addButtons(app).count, 1)
            XCTAssertGreaterThan(app.buttons["fab.add"].frame.midX, window.midX, "The button is not at the trailing side")
        }
        reveal(link, in: app).tap()
        XCTAssertTrue(element("todo.page.groceries", in: app).appears(timeout: 10), "The page did not open")
        settleScreen()
        let add = app.buttons["fab.add"]
        XCTAssertTrue(add.appears(timeout: 5), "No Add button with the page open")
        XCTAssertEqual(addButtons(app).count, 1, "More than one Add button")
        XCTAssertEqual(add.label, "Add Groceries", "The button does not belong to the open page")
        if splits {
            let page = element("todo.page.groceries", in: app).frame
            let list = element("todo.page.chores", in: app).frame
            XCTAssertTrue(list.maxX <= page.minX + 1, "Not a two-column window")
            XCTAssertGreaterThan(add.frame.midX, page.midX, "The button is not inside the right column")
            XCTAssertLessThan(window.maxX - add.frame.maxX, 40, "Not at the trailing edge (button \(add.frame), window \(window))")
            XCTAssertLessThanOrEqual(add.frame.maxX, window.maxX + 1, "Past the trailing edge (button \(add.frame), window \(window))")
            XCTAssertLessThan(page.maxY - add.frame.maxY, 120, "Not at the bottom")
            XCTAssertGreaterThan(add.frame.minY, window.midY, "Not at the bottom")
        }
        shot(app, "chores-add")
        add.tap()
        XCTAssertTrue(app.textFields["grocery.item"].appears(timeout: 10), "The button added to the wrong page")
    }

    /// The Add button hides while a chore form is open in a column and returns with Close.
    func testAddButtonHidesWhileAChoreFormIsOpenInAColumn() throws {
        landscape()
        let app = try FentonHomeApp.launchSignedIn(environment: ["FENTON_FOOD_FIXTURES": "1"])
        openSection("chores", title: "Chores", in: app)
        XCTAssertTrue(app.buttons["fab.add"].appears(timeout: 20), "No Add Task")
        guard windowSplits(app) else { throw XCTSkip("A single-page window opens the form as a sheet over the page") }
        app.buttons["fab.add"].tap()
        XCTAssertTrue(app.textFields["task.name"].appears(timeout: 10), "The form did not open")
        XCTAssertFalse(app.buttons["fab.add"].exists, "Add Task shows while the form is open")
        app.buttons["split.close"].tap()
        XCTAssertTrue(app.buttons["fab.add"].appears(timeout: 5), "Add Task did not come back")
        XCTAssertEqual(addButtons(app).count, 1)
    }

    /// A Food space from the hub: a column beside it, the next one replaces it, Close brings the prompt back; pushed elsewhere.
    func testFoodSpaceOpensAsAColumnWhereTheWindowSplits() throws {
        landscape()
        let app = try FentonHomeApp.launchSignedIn(environment: ["FENTON_FOOD_FIXTURES": "1"])
        app.buttons["quickLinks.open"].tap()
        let food = element("quickLinks.food", in: app)
        XCTAssertTrue(food.appears(timeout: 10), "No Food link in Quick Links")
        food.tap()
        let fridge = element("food.space.frigo", in: app)
        XCTAssertTrue(fridge.appears(timeout: 15), "The Food hub did not open")
        let splits = windowSplits(app)
        settleScreen()
        shot(app, "food-hub-empty")
        fridge.tap()
        settleScreen()
        shot(app, "food")
        if splits {
            XCTAssertTrue(app.buttons["split.close"].appears(timeout: 10), "No Close in the column group")
            XCTAssertTrue(fridge.exists, "The hub left the window")
            element("food.space.dispensa", in: app).tap()
            XCTAssertTrue(app.buttons["split.close"].appears(timeout: 5))
            XCTAssertFalse(app.buttons["columns.back"].exists, "A space drilled instead of replacing the other")
            app.buttons["split.close"].tap()
            XCTAssertTrue(element("food.pane.placeholder", in: app).appears(timeout: 5), "The prompt did not return")
        } else {
            XCTAssertFalse(app.buttons["split.close"].exists, "A single-page window shows columns")
            XCTAssertFalse(fridge.exists && fridge.isHittable, "The hub stayed over the pushed space")
        }
    }

    /// Rotating a pushed quick-link page moves it into a column and back, and keeps the Settings depth-two page.
    func testRotationMovesPagesBetweenPushAndColumns() throws {
        try XCTSkipUnless(FentonHomeApp.family == .iPad, "Only the iPad can be rotated by the runner (devices.md)")
        XCUIDevice.shared.orientation = .portrait
        let app = try FentonHomeApp.launchSignedIn()
        openSection("chores", title: "Chores", in: app)
        let link = element("chores.link.groceries", in: app)
        XCTAssertTrue(link.appears(timeout: 20))
        reveal(link, in: app).tap()
        XCTAssertTrue(element("todo.page.groceries", in: app).appears(timeout: 10))
        XCTAssertFalse(app.buttons["split.close"].exists)
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["split.close"].appears(timeout: 10), "The pushed page did not move into a column")
        XCTAssertTrue(element("todo.page.chores", in: app).exists)
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.buttons["split.close"].disappears(timeout: 10), "The column stayed after the window narrowed")
        XCTAssertTrue(element("todo.page.groceries", in: app).exists, "The page was lost")
    }

    /// Vacation Mode, two deep under Vacation in Settings, survives portrait to landscape as a column (depth two keeps both pages).
    func testDepthTwoPageSurvivesRotationIntoColumns() throws {
        try XCTSkipUnless(FentonHomeApp.family == .iPad, "Only the iPad can be rotated by the runner (devices.md)")
        XCUIDevice.shared.orientation = .portrait
        let app = try FentonHomeApp.launchSignedIn()
        app.openAccountSettings()
        element("settings.vacation", in: app).tap()
        // The house's state picks the landing page: the chooser (then Vacation Mode is the second page) or, already away, Vacation Mode itself.
        let chooser = element("vacation.chooser.vacationMode", in: app)
        let card = element("vacation.modeCard", in: app)
        let deadline = Date().addingTimeInterval(15)
        while !chooser.exists, !card.exists, Date() < deadline { usleep(200_000) }
        try XCTSkipUnless(chooser.exists, "The house lands on Vacation Mode directly; no depth-two page to carry")
        chooser.tap()
        XCTAssertTrue(card.appears(timeout: 10), "Vacation Mode did not open from the chooser")
        XCTAssertTrue(app.navigationBars.firstMatch.exists)
        settleScreen()
        XCUIDevice.shared.orientation = .landscapeLeft
        let back = app.buttons["columns.back"]
        let arrived = back.appears(timeout: 10)
        shot(app, "settings-depth2")
        XCTAssertTrue(arrived, "The depth-two page did not return as a drilled column")
        app.buttons["columns.back"].tap()
        XCTAssertTrue(app.buttons["split.close"].appears(timeout: 5), "Back did not return to the first page")
    }
}
