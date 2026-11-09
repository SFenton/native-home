import XCTest

/// The row's swipe actions and the leading full swipe (area E of the Chores split).
@MainActor
final class ChoresSwipeJourneyTests: ChoresJourneyTestCase {
    /// Owner, 2026-10-16: swiping a row in from the leading edge completes it (a full swipe performs the action).
    func testLeadingSwipeCompletes() {
        let app = launch()
        let row = reveal(element("todo.item.13--fixture", in: app), in: app)
        // A drag across most of the row is a full swipe, which performs the leading action. iPad now and then drops the first
        // one, so the swipe is repeated (up to three times) until it has done something. A completed row does not leave at once: it
        // stays in its done look with Undo for the 5 s grace (`TodoListController.undoGrace`, owner 2026-10-24), so the row going
        // away is the end of the flow, not the sign the swipe worked. The sign is the action: the call, or the row's Undo control.
        let undo = element("todo.undo.13--fixture", in: app)
        let expected = "todo.update_item 13--fixture"
        var performed = false
        for attempt in 0..<3 where !performed {
            if attempt == 0 {
                row.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5))
                    .press(forDuration: 0.05, thenDragTo: row.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)))
            } else {
                row.swipeRight()
            }
            performed = undo.appears(timeout: attempt == 2 ? 8 : 3) || lastCall(in: app) == expected
        }
        XCTAssertTrue(performed, "The swipe did not complete the chore")
        XCTAssertEqual(lastCall(in: app), expected)
        XCTAssertEqual(row.value as? String, "Done")
        // Then the row hides once the grace is over, as in the check-off journey.
        XCTAssertTrue(row.disappears(timeout: 10), "Completed chore still shown after the grace")
    }

    /// The release of a swipe must not also press the row's check (a second toggle reopens the chore): it stays done, with Undo, once
    /// the swipe's tap suppression (350 ms) and the row's slide back (450 ms) have both passed.
    func testLeadingSwipeReleaseDoesNotToggleAgain() {
        let app = launch()
        let row = reveal(element("todo.item.13--fixture", in: app), in: app)
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: row.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)))
        let undo = element("todo.undo.13--fixture", in: app)
        XCTAssertTrue(undo.appears(timeout: 10), "Swiped chore never showed its done look")
        settleScreen()
        usleep(900_000)
        XCTAssertTrue(undo.exists, "The chore was toggled again after the swipe: Undo is gone")
        XCTAssertEqual(element("todo.item.13--fixture", in: app).value as? String, "Done", "The chore did not stay done")
    }

    /// The trailing swipe offers Delete (outermost) and Edit; Edit opens the task form.
    func testTrailingSwipeShowsDeleteAndEdit() {
        let app = launch()
        let row = reveal(element("todo.item.13--fixture", in: app), in: app)
        revealTrailingActions(of: row, in: app)
        let delete = element("todo.swipe.delete.13--fixture", in: app)
        let edit = element("todo.swipe.edit.13--fixture", in: app)
        XCTAssertTrue(delete.appears(timeout: 5) && edit.exists, "Trailing actions missing")
        XCTAssertEqual(delete.label, "Delete")
        XCTAssertEqual(edit.label, "Edit")
        keepScreenshot(app, screenshotName("chores-swipe-trailing"))
        XCTAssertLessThan(edit.frame.minX, delete.frame.minX, "Delete is outermost")
        edit.tap()
        XCTAssertTrue(app.textFields["task.name"].appears(timeout: 5))
        XCTAssertEqual(app.textFields["task.name"].value as? String, "Run the dishwasher")
    }
}
