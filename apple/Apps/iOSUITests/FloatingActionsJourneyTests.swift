import XCTest

/// The shared floating action bar and filter sheet in the debug gallery: actions, search, sort/filter
/// sheets, audits and screenshots on iPhone, iPhone Duo and iPad (`.agents/patterns/floating-actions.md`).
@MainActor
final class FloatingActionsJourneyTests: JourneyTestCase {
    /// The gallery builds its rows, sort and search state per gallery (no statics, defaults or files), so a reused app resets between
    /// tests; AX5 (`arguments`) is part of the launch signature and keeps its own resident app (`app-reuse.md`).
    private func launch(arguments: [String] = []) -> XCUIApplication {
        let configured = FentonHomeApp.makeApp()
        configured.launchEnvironment["FENTON_GALLERY"] = "floating-actions"
        configured.launchArguments += arguments
        let app = startApp(configured)
        XCTAssertTrue(app.buttons["fab.add"].appears(timeout: 10))
        return app
    }

    private func lastAction(_ app: XCUIApplication) -> String {
        app.staticTexts["gallery.lastCall"].label
    }

    /// Every action is a named button at least 44 pt; icon-only actions keep their title for VoiceOver.
    func testActionsAreNamedAndLargeEnough() {
        let app = launch()
        // One snapshot answers existence, label and size of the four; hittability is a live read.
        guard let root = try? app.snapshot() else { return XCTFail("No snapshot of the page") }
        func flatten(_ node: XCUIElementSnapshot) -> [XCUIElementSnapshot] { node.children.flatMap { [$0] + flatten($0) } }
        let buttons = flatten(root).filter { $0.elementType == .button }
        for (id, label) in [("add", "Add Task"), ("sort", "Sort"), ("filter", "Filter"), ("search", "Search rows")] {
            guard let button = buttons.first(where: { $0.identifier == "fab.\(id)" }) else { XCTFail("\(id) missing"); continue }
            XCTAssertEqual(button.label, label)
            XCTAssertGreaterThanOrEqual(button.frame.height, 43, "\(id) too short")
            XCTAssertGreaterThanOrEqual(button.frame.width, 43, "\(id) too narrow")
            XCTAssertTrue(app.buttons["fab.\(id)"].isHittable, "\(id) not hittable")
        }
        app.buttons["fab.add"].tap()
        XCTAssertEqual(lastAction(app), "Last action: add")
    }

    /// The search field expands over the other actions, filters, and closes back to the buttons.
    func testSearchExpandsAndCloses() {
        let app = launch()
        app.buttons["fab.search"].tap()
        let field = app.textFields["fab.search.field"]
        XCTAssertTrue(field.appears(timeout: 5))
        XCTAssertFalse(app.buttons["fab.add"].exists, "Actions stay visible while searching")
        field.typeText("Row 30")
        XCTAssertTrue(app.staticTexts["Row 30"].appears(timeout: 5))
        XCTAssertFalse(app.staticTexts["Row 2"].exists)
        app.buttons["fab.search.close"].tap()
        XCTAssertTrue(app.buttons["fab.add"].appears(timeout: 5))
        XCTAssertTrue(app.staticTexts["Row 2"].exists, "Closing search clears it")
    }

    /// Sort applies a draft; Cancel drops it; the applied sort shows the action as selected.
    func testSortSheetAppliesDraft() {
        let app = launch()
        app.buttons["fab.sort"].tap()
        let apply = app.buttons["filterSheet.apply"]
        XCTAssertTrue(apply.appears(timeout: 5))
        XCTAssertFalse(apply.isEnabled, "Apply enabled without a change")
        app.buttons["gallery.sort.alphabetical"].tap()
        XCTAssertTrue(app.buttons["gallery.sort.alphabetical"].isSelected)
        XCTAssertTrue(apply.isEnabled)
        apply.tap()
        XCTAssertTrue(apply.disappears(timeout: 5))
        XCTAssertEqual(lastAction(app), "Last action: sort Alphabetical")
        XCTAssertTrue(app.buttons["fab.sort"].isSelected, "Active sort not shown")

        app.buttons["fab.sort"].tap()
        XCTAssertTrue(app.buttons["filterSheet.reset"].appears(timeout: 5))
        app.buttons["filterSheet.reset"].tap()
        app.buttons["filterSheet.cancel"].tap()
        XCTAssertTrue(app.buttons["fab.sort"].appears(timeout: 5))
        XCTAssertTrue(app.buttons["fab.sort"].isSelected, "Cancel applied the draft")
    }

    /// At the largest text size the bar reflows (the labelled action on its own full-width row, the circles beneath)
    /// instead of wrapping a letter per line or running over the page: every button is on screen, at least 44 pt, and
    /// none overlaps another (folded iPhone Duo capture, 2026-10-16).
    func testBarReflowsAtTheLargestTextSize() {
        let app = launch(arguments: FentonHomeApp.ax5)
        guard let root = try? app.snapshot() else { return XCTFail("No snapshot of the page") }
        func flatten(_ node: XCUIElementSnapshot) -> [XCUIElementSnapshot] { node.children.flatMap { [$0] + flatten($0) } }
        let all = flatten(root)
        let window = all.first { $0.elementType == .window }?.frame ?? app.windows.firstMatch.frame
        let buttons = ["add", "sort", "filter", "search"].compactMap { id in
            let found = all.first { $0.elementType == .button && $0.identifier == "fab.\(id)" }
            if found == nil { XCTFail("fab.\(id)") }
            return found
        }
        for action in buttons {
            XCTAssertGreaterThanOrEqual(action.frame.width, 43, "\(action.identifier) too narrow")
            XCTAssertGreaterThanOrEqual(action.frame.height, 43, "\(action.identifier) too short")
            XCTAssertGreaterThanOrEqual(action.frame.minX, window.minX - 0.5, "\(action.identifier) runs off the leading edge")
            XCTAssertLessThanOrEqual(action.frame.maxX, window.maxX + 0.5, "\(action.identifier) runs off the trailing edge")
        }
        for (index, first) in buttons.enumerated() {
            for second in buttons[(index + 1)...] {
                XCTAssertFalse(first.frame.insetBy(dx: 1, dy: 1).intersects(second.frame.insetBy(dx: 1, dy: 1)),
                               "\(first.identifier) overlaps \(second.identifier)")
            }
        }
        // The title wraps by word at most: the capsule is far wider than a single line of its label is tall.
        let add = buttons[0].frame
        XCTAssertGreaterThan(add.width, add.height * 1.5, "Add Task wraps into a tall pill")
        keepScreenshot(app, "floating-actions-ax5-\(FentonHomeApp.family)")
    }

    /// The top of the bar's buttons, in screen points.
    private func barTop(_ app: XCUIApplication) -> CGFloat {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'fab.'")).allElementsBoundByIndex.map(\.frame.minY).min() ?? .greatestFiniteMagnitude
    }

    /// Owner, 2026-10-16: nothing stays permanently covered. The bar's height is added to the list's bottom inset, so the
    /// last row scrolls clear of the buttons and can still be tapped.
    func testLastRowScrollsClearOfTheBar() {
        let app = launch()
        // The UIKit gallery lists the rows in a table view (the SwiftUI one was a collection view).
        let list = app.tables.firstMatch
        let last = app.staticTexts["Row 30"]
        for _ in 0..<15 { list.swipeUp(velocity: .fast) }
        XCTAssertTrue(last.exists, "Row 30 never appeared")
        XCTAssertLessThanOrEqual(last.frame.maxY, barTop(app), "The last row ends under the bar")
        XCTAssertTrue(last.isHittable, "The last row can't be reached")
    }

    /// Owner, 2026-10-16: the bar is Liquid Glass, so a row scrolled under it still shows through. A row's text under the
    /// bar's search capsule measures its rendered contrast against the glass behind it.
    func testRowsShowThroughTheGlassBar() throws {
        let app = launch()
        let top = barTop(app)
        // At rest the list shows rows 52 pt apart, so one starts inside the bar's 52 pt strip.
        let rows = (1...30).map { app.staticTexts["Row \($0)"] }.filter(\.exists)
        let seen = rows.map { "\($0.label)@\(Int($0.frame.minY))" }.joined(separator: " ")
        let covered = rows.first { $0.frame.midY > top + 4 && $0.frame.midY < top + 48 }
        let row = try XCTUnwrap(covered, "No row came to rest under the bar (bar top \(Int(top)); rows: \(seen))")
        keepScreenshot(app, "floating-actions-through-glass-\(FentonHomeApp.family)")
        let capture = try XCTUnwrap(RenderedContrast.Capture.screen())
        let ratio = try XCTUnwrap(RenderedContrast.ratio(of: row.frame, in: capture), "No pixels under \(row.label)")
        XCTAssertGreaterThanOrEqual(ratio, 1.15, "\(row.label) under the bar is not visible through the glass (rendered \(ratio):1)")
    }

    func testPagePassesAccessibilityAudit() throws {
        let app = launch()
        keepScreenshot(app, "floating-actions-\(FentonHomeApp.family)")
        try FentonHomeApp.audit(app) { self.launch(arguments: FentonHomeApp.ax5) }
    }

    func testFilterSheetPassesAccessibilityAudit() throws {
        func open(_ app: XCUIApplication) -> XCUIApplication {
            app.buttons["fab.filter"].tap()
            XCTAssertTrue(app.buttons["filterSheet.apply"].appears(timeout: 5))
            settleScreen() // Let the sheet settle.
            return app
        }
        let app = open(launch())
        keepScreenshot(app, "filter-sheet-\(FentonHomeApp.family)")
        try FentonHomeApp.audit(app) { open(self.launch(arguments: FentonHomeApp.ax5)) }
    }
}
