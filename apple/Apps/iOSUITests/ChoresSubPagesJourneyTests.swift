import XCTest

/// The Chores sub-pages and the empty states: the empty copy, the empty state centred in the free space, and every sub-page's
/// accessibility audit (area I of the Chores split).
@MainActor
final class ChoresSubPagesJourneyTests: ChoresJourneyTestCase {
    func testEmptyPagesSayNiceJob() {
        let app = launch(page: expectations[.choresFirstPageId], empty: true)
        XCTAssertTrue(element("todo.empty", in: app).appears(timeout: 5))
        XCTAssertTrue(app.staticTexts["You have no chores due. Nice job!"].exists)
    }

    /// The empty state is centred in the free space: between the large title and the Add Task button on a page with no
    /// header, and between the quick links and that button on the Chores landing (pattern: state-message).
    func testEmptyStateIsCentredInTheFreeSpace() {
        let page = launch(page: expectations[.choresFirstPageId], empty: true)
        let message = element("todo.empty", in: page)
        XCTAssertTrue(message.appears(timeout: 5))
        let free = (top: page.navigationBars.firstMatch.frame.maxY, bottom: page.buttons["fab.add"].frame.minY)
        let messageFrame = message.frame
        assertCentred(messageFrame, in: free, "between the title and Add Task")
        // Across the page's width; the Duo keeps a trailing column (clock and connection ring, about 90 pt) that the rows and the
        // message both leave clear, so its centre sits that much left of the screen's.
        XCTAssertEqual(messageFrame.midX, page.frame.midX, accuracy: 48)
        keepScreenshot(page, screenshotName("empty-centred"))

        let landing = launch(empty: true)
        let landingMessage = element("todo.empty", in: landing)
        XCTAssertTrue(landingMessage.appears(timeout: 5))
        let links = landing.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'chores.link.'")).allElementsBoundByIndex
        XCTAssertFalse(links.isEmpty, "The quick links stay above the empty state")
        let tilesBottom = links.map(\.frame.maxY).max() ?? 0
        keepScreenshot(landing, screenshotName("empty-landing-centred"))
        let landingFrame = landingMessage.frame
        XCTAssertGreaterThan(landingFrame.minY, tilesBottom - 1, "Below the quick links")
        assertCentred(landingFrame, in: (tilesBottom, landing.buttons["fab.add"].frame.minY), "between the quick links and Add Task")
        XCTAssertTrue(links[0].isHittable, "The quick links stay tappable under the empty state")
    }

    /// One page's screenshot and accessibility audit (with its AX5 relaunch). One test per page, sharing this body.
    private func assertSubPagePassesAudit(_ page: String, empty: Bool = false, name: String) throws {
        let app = launch(page: page, empty: empty)
        keepScreenshot(app, screenshotName(name))
        try FentonHomeApp.audit(app) { self.launch(page: page, empty: empty, arguments: FentonHomeApp.ax5) }
    }

    func testSubPageGroceriesPassesAccessibilityAudit() throws {
        try assertSubPagePassesAudit("groceries", name: "groceries")
    }

    func testSubPageFirstResidentChoresPassesAccessibilityAudit() throws {
        try assertSubPagePassesAudit(expectations[.choresFirstPageId], name: "first-resident-chores")
    }

    func testSubPageSecondResidentChoresPassesAccessibilityAudit() throws {
        try assertSubPagePassesAudit(expectations[.choresSecondPageId], name: "second-resident-chores")
    }

    func testSubPageUnassignedChoresPassesAccessibilityAudit() throws {
        try assertSubPagePassesAudit("unassigned-chores", name: "unassigned-chores")
    }

    func testSubPageHomeImprovementChoresPassesAccessibilityAudit() throws {
        try assertSubPagePassesAudit("home-improvement-chores", name: "home-improvement-chores")
    }

    func testSubPageToDoPassesAccessibilityAudit() throws {
        try assertSubPagePassesAudit("to-do", name: "to-do")
    }

    func testSubPageGroceriesEmptyPassesAccessibilityAudit() throws {
        try assertSubPagePassesAudit("groceries", empty: true, name: "groceries-empty")
    }

    /// The message sits in the middle of `free` when it fits there. When the page leaves it less room than it needs (the
    /// folded Duo under the quick links), it starts at the top of the space and scrolls instead (pattern: state-message).
    private func assertCentred(_ frame: CGRect, in free: (top: CGFloat, bottom: CGFloat), _ what: String) {
        if free.bottom - free.top >= frame.height + 16 {
            XCTAssertEqual(frame.midY, (free.top + free.bottom) / 2, accuracy: 14, "Centred \(what): message \(frame), free \(free)")
        } else {
            XCTAssertGreaterThanOrEqual(frame.minY, free.top - 1, "Too tall to centre \(what): starts at the top and scrolls")
        }
    }
}
