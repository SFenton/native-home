import XCTest

/// Deleting a task asks first (area F of the Chores split).
@MainActor
final class ChoresDeleteJourneyTests: ChoresJourneyTestCase {
    /// Delete asks first; cancelling leaves the task, confirming removes it with `todo.remove_item`.
    func testSwipeDeleteConfirmsBeforeRemoving() {
        let app = launch()
        let row = reveal(element("todo.item.13--fixture", in: app), in: app)
        revealTrailingActions(of: row, in: app)
        element("todo.swipe.delete.13--fixture", in: app).tap()
        let confirm = element("todo.delete.confirm", in: app)
        XCTAssertTrue(confirm.appears(timeout: 5), "No confirmation")
        XCTAssertNotEqual(lastCall(in: app), "todo.remove_item 13--fixture", "Deleted before the answer")
        XCTAssertTrue(row.exists)
        confirm.tap()
        XCTAssertTrue(row.disappears(timeout: 5))
        XCTAssertEqual(lastCall(in: app), "todo.remove_item 13--fixture")
    }
}
