import XCTest

/// Checking a chore off, the Undo grace, a rejected completion and the Reduce Motion path (area D of the Chores split).
@MainActor
final class ChoresCheckUndoJourneyTests: ChoresJourneyTestCase {
    /// Checking a chore off calls Home Assistant and keeps the row in its done look with Undo for 5 s, then it leaves
    /// (owner, 2026-10-24).
    func testCheckingOffAChoreKeepsItWithUndoThenHidesIt() {
        let app = launch()
        let row = element("todo.item.13--fixture", in: app)
        reveal(row, in: app)
        XCTAssertEqual(row.label, "Run the dishwasher")
        XCTAssertTrue((row.value as? String)?.hasPrefix("Not done, Due in") == true)
        row.tap()
        XCTAssertTrue(element("todo.undo.13--fixture", in: app).appears(timeout: 3), "No Undo after the tick")
        XCTAssertEqual(row.value as? String, "Done")
        XCTAssertEqual(lastCall(in: app), "todo.update_item 13--fixture")
        XCTAssertTrue(row.disappears(timeout: 10), "Completed chore still shown after the grace")
    }

    /// Owner, 2026-10-16: a completed chore animates away, and if Home Assistant rejects it the chore comes back with
    /// the error (the fixture refuses every check-off after 4 s).
    func testRejectedCompletionBringsTheChoreBack() {
        let app = launch(environment: ["FENTON_GALLERY_FAIL_COMPLETE": "1"])
        let row = reveal(element("todo.item.13--fixture", in: app), in: app)
        row.tap()
        XCTAssertTrue(element("todo.undo.13--fixture", in: app).appears(timeout: 3), "The chore did not show its done look")
        XCTAssertTrue(element("todo.undo.13--fixture", in: app).disappears(timeout: 15), "The chore never came back")
        XCTAssertTrue((element("todo.item.13--fixture", in: app).value as? String)?.hasPrefix("Not done") == true)
        XCTAssertTrue(app.staticTexts["Unable to update task"].appears(timeout: 3), "No error shown")
        XCTAssertTrue(lastCall(in: app).hasSuffix("failed"))
    }

    /// Reduce Motion: the row still leaves and returns (a fade, not a slide).
    func testCompletionStillWorksWithReduceMotion() {
        let app = FentonHomeApp.launchGallery("chores", environment: FentonHomeApp.SystemSetting.environment([.reduceMotion]))
        reducedMotion = true
        XCTAssertTrue(app.buttons["fab.add"].appears(timeout: 10))
        let row = reveal(element("todo.item.13--fixture", in: app), in: app)
        row.tap()
        XCTAssertTrue(row.disappears(timeout: 10))
    }

    /// Undo puts the chore back as not done.
    func testUndoReopensTheChore() {
        let app = launch()
        let row = reveal(element("todo.item.13--fixture", in: app), in: app)
        row.tap()
        let undo = element("todo.undo.13--fixture", in: app)
        XCTAssertTrue(undo.appears(timeout: 3))
        undo.tap()
        XCTAssertTrue(undo.disappears(timeout: 3), "Undo stays after it was used")
        XCTAssertTrue((element("todo.item.13--fixture", in: app).value as? String)?.hasPrefix("Not done") == true)
        XCTAssertEqual(lastCall(in: app), "todo.update_item 13--fixture")
    }
}
