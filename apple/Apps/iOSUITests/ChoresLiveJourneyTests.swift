import XCTest

/// The signed-in Chores tab on the real house, read-only (the Live plan). Nothing is checked off.
@MainActor
final class ChoresLiveJourneyTests: ChoresJourneyTestCase {
    /// Signed in, the real Chores tab shows its quick links and passes the audit. Nothing is checked off.
    func testLiveChoresTabAudit() throws {
        let app = try FentonHomeApp.launchSignedIn()
        openChores(in: app)
        XCTAssertTrue(element("chores.link.groceries", in: app).appears(timeout: 15), "Quick links missing")
        try FentonHomeApp.audit(app)
    }

    /// Signed in, Groceries opens from the real Chores tab. Nothing is checked off.
    func testLiveChoresTabOpensGroceries() throws {
        let app = try FentonHomeApp.launchSignedIn()
        openChores(in: app)
        let groceries = element("chores.link.groceries", in: app)
        XCTAssertTrue(groceries.appears(timeout: 15), "Quick links missing")
        groceries.tap()
        XCTAssertTrue(element("todo.page.groceries", in: app).appears(timeout: 10))
    }

    /// Opens the Chores section through whichever navigation the window shows: the tab bar, the folded Duo's
    /// vertical bar (a toolbar to XCUITest), or the iPad flyout.
    private func openChores(in app: XCUIApplication) {
        // The tab's badge is in its label ("Chores, 8 overdue").
        let item = app.barItem("Chores")
        if item.appears(timeout: 5), item.isHittable {
            item.tap()
        } else {
            app.buttons["nav.open"].tap()
            XCTAssertTrue(app.descendants(matching: .any)["nav.flyout"].appears(timeout: 3), "Flyout did not open")
            app.buttons["nav.chores"].tap()
        }
    }

    /// Goes back one page: the system Back button wherever the bar puts it (the folded iPhone Duo moves bar items
    /// into its vertical bar), else the leading-edge back swipe.
    private func goBack(in app: XCUIApplication) {
        // A window that splits shows the page as a column: Close is in the bar's column group (a Back from the system's stack is not there).
        let close = app.buttons["split.close"].firstMatch
        if close.exists, close.isHittable {
            close.tap()
            return
        }
        let back = app.buttons["BackButton"].firstMatch
        if back.exists, back.isHittable {
            back.tap()
            return
        }
        let window = app.windows.firstMatch
        let start = window.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 2, dy: window.frame.height / 2))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: window.frame.width * 0.7, dy: 0)))
    }

    /// Signed in, a Chores quick link opens its page without crashing and comes back (owner report 2026-10-13: Sam's
    /// Chores crashed). Nothing is checked off. One test per page, sharing this body.
    private func assertLivePageOpens(_ page: String) throws {
        let app = try FentonHomeApp.launchSignedIn()
        openChores(in: app)
        let link = element("chores.link.\(page)", in: app)
        XCTAssertTrue(link.appears(timeout: 15), "\(page) link missing")
        reveal(link, in: app).tap()
        XCTAssertTrue(element("todo.page.\(page)", in: app).appears(timeout: 10), "\(page) did not open")
        // Let the lists load and draw before leaving.
        _ = element("todo.empty", in: app).appears(timeout: 4)
        XCTAssertEqual(app.state, .runningForeground, "\(page) crashed the app")
        goBack(in: app)
        XCTAssertTrue(link.appears(timeout: 10), "Back from \(page) failed")
    }

    func testLiveChoresPageOpensGroceries() throws {
        try assertLivePageOpens("groceries")
    }

    func testLiveChoresPageOpensFirstResidentChores() throws {
        try assertLivePageOpens(JourneyExpectations.current(for: .signedIn).value(.choresFirstPageId))
    }

    func testLiveChoresPageOpensSecondResidentChores() throws {
        try assertLivePageOpens(JourneyExpectations.current(for: .signedIn).value(.choresSecondPageId))
    }

    func testLiveChoresPageOpensUnassignedChores() throws {
        try assertLivePageOpens("unassigned-chores")
    }

    func testLiveChoresPageOpensHomeImprovementChores() throws {
        try assertLivePageOpens("home-improvement-chores")
    }
}
