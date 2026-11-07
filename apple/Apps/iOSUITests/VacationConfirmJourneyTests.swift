import XCTest

/// The confirmation sheet that enabling Vacation Mode opens: its audit and its action at the largest text size.
@MainActor
final class VacationConfirmJourneyTests: VacationJourneyTestCase {
    func testConfirmSheetPassesAudit() throws { try audit(.confirmSheet) }

    /// At AX5 the sheet's Confirm button can still be reached.
    func testLargestTextKeepsConfirmReachable() {
        // Clean: at AX5 the debug last-call bar grows over the bottom of the page and takes the taps.
        let app = open(.confirmSheet, clean: true, arguments: FentonHomeApp.ax5)
        reveal(element("vacation.confirm.action", in: app), in: app)
    }

    /// Cancelling the confirmation leaves Vacation Mode off.
    func testCancellingTheConfirmationKeepsItOff() {
        let app = open(.confirmSheet)
        tap("vacation.confirm.cancel", in: app)
        XCTAssertTrue(element("vacation.modeCard", in: app).appears(timeout: 5))
        XCTAssertEqual(element("vacation.modeCard", in: app).value as? String, "Off")
        XCTAssertEqual(lastCall(in: app), "None")
    }
}
