import XCTest

/// The Vacation Mode page: the checklist that blocks enabling, confirming the dates, back to the chooser it was pushed from, the checklist
/// and dates audits and the checklist at the largest text size.
@MainActor
final class VacationModeJourneyTests: VacationJourneyTestCase {
    /// An unfinished checklist blocks enabling; finishing it and confirming the dates turns Vacation Mode on.
    func testChecklistThenConfirmEnablesVacation() {
        let app = open(.vacationChecklist)
        let card = element("vacation.modeCard", in: app)
        XCTAssertEqual(card.value as? String, "Off")
        card.tap()
        // Any element type: the UIKit alert may expose the message as a static text or inside a larger element.
        XCTAssertTrue(app.descendants(matching: .any)["Error: All pre-vacation tasks must be checked off before Vacation Mode can be enabled."]
            .firstMatch.appears(timeout: 3))
        for index in 2..<5 {
            let row = element("vacation.checklist.\(index)", in: app)
            assertTarget("vacation.checklist.\(index)", in: app)
            XCTAssertEqual(row.value as? String, "Not checked")
            reveal(row, in: app).tap()
            XCTAssertEqual(row.value as? String, "Checked")
            waitForCall("input_boolean.turn_on", in: app)
        }
        app.swipeDown()
        tap("vacation.modeCard", in: app)
        XCTAssertTrue(element("vacation.confirm.action", in: app).appears(timeout: 5))
        tap("vacation.confirm.action", in: app)
        waitForCall("input_boolean.turn_on entity_id=\(expectations[.vacationMode])", in: app)
        XCTAssertTrue(element("vacation.dates.start", in: app).appears(timeout: 5))
        XCTAssertEqual(element("vacation.modeCard", in: app).value as? String, "On")
        // Back returns to the chooser it was pushed from, not to a second copy of this page.
        app.buttons["BackButton"].firstMatch.tap()
        XCTAssertTrue(element("vacation.chooser.vacationMode", in: app).appears(timeout: 5))
    }

    func testChecklistPassesAudit() throws { try audit(.vacationChecklist) }
    func testDatesPassAudit() throws { try audit(.vacationDates) }

    /// At AX5 the last checklist row can still be reached.
    func testLargestTextKeepsChecklistReachable() {
        // Clean: at AX5 the debug last-call bar grows over the bottom of the page and takes the taps.
        let app = open(.vacationChecklist, clean: true, arguments: FentonHomeApp.ax5)
        reveal(element("vacation.checklist.4", in: app), in: app)
    }

    /// Cancelling the turn-off alert keeps Vacation Mode on and calls nothing.
    func testDisablingVacationCancelKeepsOn() {
        let app = open(.vacationDates)
        let card = element("vacation.modeCard", in: app)
        XCTAssertEqual(card.value as? String, "On")
        // Cancel keeps it on and calls nothing.
        card.tap()
        let cancel = app.alerts.buttons["vacation.modeCard.cancel"].firstMatch
        XCTAssertTrue(cancel.appears(timeout: 5), "No turn-off alert")
        XCTAssertEqual(cancel.label, "Cancel")
        XCTAssertTrue(app.alerts["Turn Off Vacation Mode?"].exists)
        // iOS 27 nests each alert button in a same-named button, which a tap can't resolve: tap its frame.
        tapCenter(of: cancel, in: app)
        XCTAssertTrue(cancel.disappears(timeout: 5))
        XCTAssertEqual(card.value as? String, "On")
        XCTAssertEqual(lastCall(in: app), "None")
    }

    /// Confirming the turn-off alert turns Vacation Mode off, resets the checklist and shows it again.
    func testDisablingVacationConfirmResetsChecklist() {
        let app = open(.vacationDates)
        let card = element("vacation.modeCard", in: app)
        XCTAssertEqual(card.value as? String, "On")
        card.tap()
        let yes = app.alerts.buttons["vacation.modeCard.confirm"].firstMatch
        XCTAssertTrue(yes.appears(timeout: 5))
        XCTAssertEqual(yes.label, "Turn Off")
        tapCenter(of: yes, in: app)
        waitForCall("vacation_checklist_trash_and_recycles_taken_out", in: app)
        XCTAssertTrue(element("vacation.checklist.0", in: app).appears(timeout: 5))
    }
}
