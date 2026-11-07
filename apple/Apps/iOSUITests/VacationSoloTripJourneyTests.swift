import XCTest

/// The Solo Trip page, its editor sheet, an active trip and the restore choice: the audits and the main actions at the largest text size.
@MainActor
final class VacationSoloTripJourneyTests: VacationJourneyTestCase {
    func testSoloTripPassesAudit() throws { try audit(.soloTripIdle) }
    func testSoloTripEditorPassesAudit() throws { try audit(.soloTripEditor) }
    func testActiveSoloTripPassesAudit() throws { try audit(.soloTripActive) }
    func testRestoreChoicePassesAudit() throws { try audit(.soloTripRestore) }

    /// At AX5 the last traveler tile can still be reached.
    func testLargestTextKeepsTravelersReachable() {
        // Clean: at AX5 the debug last-call bar grows over the bottom of the page and takes the taps.
        let app = open(.soloTripIdle, clean: true, arguments: FentonHomeApp.ax5)
        reveal(element("soloTrip.traveler.resident_2", in: app), in: app)
    }

    /// At AX5 the editor sheet's Confirm button can still be reached.
    func testLargestTextKeepsEditorConfirmReachable() {
        // Clean: at AX5 the debug last-call bar grows over the bottom of the page and takes the taps.
        let app = open(.soloTripEditor, clean: true, arguments: FentonHomeApp.ax5)
        reveal(element("soloTrip.editor.confirm", in: app), in: app)
    }

    /// Scheduling a trip for Alex starts it.
    func testSoloTripLifecycleSchedule() {
        let app = open(.soloTripIdle)
        let toggle = element("soloTrip.toggle", in: app)
        XCTAssertFalse(toggle.isEnabled, "The toggle needs a traveler first")
        let firstTraveler = element("soloTrip.traveler.resident_1", in: app)
        firstTraveler.tap()
        XCTAssertTrue(firstTraveler.isSelected)
        XCTAssertTrue(toggle.isEnabled)
        toggle.tap()
        tap("soloTrip.editor.confirm", in: app)
        waitForCall("operation=schedule", in: app)
        XCTAssertTrue(lastCall(in: app).contains("traveler=alex"))
        XCTAssertTrue(element("soloTrip.editor.confirm", in: app).disappears(timeout: 5))
        XCTAssertTrue(waitForValue("On", of: toggle), "Solo Trip never turned on")
        XCTAssertEqual(firstTraveler.value as? String, "Away")
        XCTAssertEqual(element("soloTrip.traveler.resident_2", in: app).value as? String, "Home")
        XCTAssertTrue(element("soloTrip.return", in: app).exists)
    }

    /// Turning the toggle off on an active trip ends it. Enters on the `solo-active` page the Active audit uses.
    func testSoloTripLifecycleEnd() {
        let app = open(.soloTripActive)
        let toggle = element("soloTrip.toggle", in: app)
        let firstTraveler = element("soloTrip.traveler.resident_1", in: app)
        toggle.tap()
        // Ending the trip asks first (AlertCopy.endSoloTrip), as the toggle tile's own question.
        let end = app.alerts.buttons["soloTrip.toggle.confirm"].firstMatch
        XCTAssertTrue(end.appears(timeout: 5), "No end-trip alert")
        tapCenter(of: end, in: app)
        waitForCall("operation=end_now", in: app)
        XCTAssertTrue(waitForValue("", of: firstTraveler), "Alex still shows \(firstTraveler.value ?? "nil")")
    }

    /// An active trip skips the chooser.
    func testEngagedTripActiveOpensDirectly() {
        let active = open(.soloTripActive)
        XCTAssertTrue(element("soloTrip.notice", in: active).exists)
    }

    /// A trip needing attention offers the restore choice.
    func testEngagedTripRestoreOffersChoice() {
        let restore = open(.soloTripRestore)
        assertTarget("soloTrip.status.keepCurrent", in: restore)
        assertTarget("soloTrip.status.restoreSaved", in: restore)
        tap("soloTrip.status.keepCurrent", in: restore)
        waitForCall("resolve_action=keep_current", in: restore)
    }
}
