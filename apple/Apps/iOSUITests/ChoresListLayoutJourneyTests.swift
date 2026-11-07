import XCTest

/// How a todo list sits in its page: the quick links and modules share one margin, the first row clears the group's rounded
/// corners, and the last row scrolls clear of the Add bar (area B of the Chores split).
@MainActor
final class ChoresListLayoutJourneyTests: ChoresJourneyTestCase {
    /// The quick links start and end where the modules below them do, whatever the window: they are a plain list row with
    /// zero insets, like the rows below them (owner follow-up, 2026-10-17: the tiles were inset about
    /// 16 pt more than the Past Due rows).
    func testQuickLinksAlignWithTheListMargins() {
        let app = launch()
        let groceries = element("chores.link.groceries", in: app)
        XCTAssertTrue(groceries.appears(timeout: 10))
        let heading = app.staticTexts["Past Due"].firstMatch
        XCTAssertTrue(heading.appears(timeout: 5), "Past Due heading missing")
        let edit = element("todo.edit.12--fixture", in: app)
        XCTAssertTrue(edit.appears(timeout: 5), "Past Due row missing")
        // Let the measured inset settle.
        groceries.settled()
        edit.settled()
        XCTAssertEqual(groceries.frame.minX, heading.frame.minX, accuracy: 1.5, "The tiles start inside the headings' edge")
        // The row's edit button sits 4 pt inside the module's trailing edge.
        // The grid's rightmost tile (Groceries spans the row on a phone, but not in four columns on iPad).
        let tiles = [expectations[.choresFirstPageId], expectations[.choresSecondPageId], "unassigned-chores", "home-improvement-chores", "groceries"]
            .map { element("chores.link.\($0)", in: app) }
        let trailing = tiles.map(\.frame.maxX).max() ?? 0
        let leading = tiles.map(\.frame.minX).min() ?? 0
        XCTAssertEqual(leading, heading.frame.minX, accuracy: 1.5, "The leftmost tile starts at the headings' edge")
        XCTAssertEqual(trailing, edit.frame.maxX + 4, accuracy: 2, "The rightmost tile ends at the modules' edge")
        keepScreenshot(app, screenshotName("chores-alignment"))
    }

    /// The first row of the list is masked to the group's rounded top corners, so its heading starts below them: the Q of
    /// "Quick Links" was cut by the arc when the row had no top inset (owner report, 2026-10-26).
    func testQuickLinksHeadingClearsTheListsTopCorners() {
        let app = launch()
        let heading = app.staticTexts["Quick Links"].firstMatch
        XCTAssertTrue(heading.appears(timeout: 10), "Quick Links heading missing")
        // The old `List` masked its first row to the group's corners (the row's top is the reference); the stack page has no
        // such mask, and keeps the same gap under the bar so the two look alike (``TodoPageLayout/leadingRowTopInset``).
        let firstRow = app.collectionViews["todo.page.chores"].cells.firstMatch
        if firstRow.exists {
            XCTAssertGreaterThanOrEqual(heading.frame.minY - firstRow.frame.minY, 11.5, "The heading starts inside the row's rounded corner")
        } else {
            let bar = app.navigationBars.firstMatch
            let top = bar.exists && bar.frame.width > bar.frame.height ? bar.frame.maxY : scroller(app).frame.minY
            XCTAssertGreaterThanOrEqual(heading.frame.minY - top, 11.5, "The heading starts too close under the bar")
        }
        keepScreenshot(app, screenshotName("chores-quick-links-heading"))
    }

    /// The Add bar's height is added to the list's bottom inset: at AX5 the last chore scrolls clear of the bar and can be
    /// tapped (owner, 2026-10-16: nothing permanently covered).
    func testLastChoreScrollsClearOfTheAddBar() {
        let app = launch(arguments: FentonHomeApp.ax5)
        let list = scroller(app)
        let last = element("todo.item.15--fixture", in: app)
        // The page is a plain stack now (every row is built), so a row far below can be in the tree without being on screen:
        // scroll a fixed number of rounds, more than the longest AX5 page needs, and the page stops at its end.
        // The list is a collection view whose rows are built as they scroll in, so a short, large-text window (the folded Duo's AX5
        // page) needs more rounds before the last row exists: drag until it does, then settle.
        // At AX5 the Quick Links tiles are a screen tall each, so the drags start on a tile, and mid-screen: the lower third holds the
        // floating Add bar (interactive glass, which keeps a drag that starts on it) and the gallery's last-call line, and a drag that
        // starts there never reached the list (2026-11-04: every family). Measured drags (400 pt/s); the system swipe does not
        // scroll the folded Duo.
        for round in 0..<60 where round < 12 || !last.exists {
            let x = round % 2 == 0 ? 0.5 : 0.15
            list.coordinate(withNormalizedOffset: CGVector(dx: x, dy: 0.55))
                .press(forDuration: 0.05, thenDragTo: list.coordinate(withNormalizedOffset: CGVector(dx: x, dy: 0.1)), withVelocity: 400, thenHoldForDuration: 0)
        }
        last.settled()
        if !last.exists {
            add(XCTAttachment(string: app.debugDescription))
            let ids = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'todo.item.'")).allElementsBoundByIndex.map { "\($0.identifier)@\($0.frame.minY)" }
            keepScreenshot(app, screenshotName("chores-last-never-appeared"))
            let lists = app.collectionViews.allElementsBoundByIndex.map { "\($0.identifier)@\($0.frame)" }
            print("CHORE-DIAG window=\(app.windows.firstMatch.frame) list=\(list.identifier)@\(list.frame) lists=\(lists) items=\(ids) "
                  + "first cell \(app.cells.firstMatch.frame)")
        }
        XCTAssertTrue(last.exists, "The last chore never appeared")
        let barTop = min(app.buttons["fab.add"].frame.minY, app.staticTexts["gallery.lastCall"].frame.minY)
        XCTAssertLessThanOrEqual(last.frame.maxY, barTop, "The last chore ends under the Add bar")
        XCTAssertTrue(last.isHittable)
    }
}
