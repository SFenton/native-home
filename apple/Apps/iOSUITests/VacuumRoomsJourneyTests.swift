import XCTest

/// The Rooms section: ordered room selection tiles, then Clean from Controls, Pause while cleaning, and the Rooms audit.
@MainActor
final class VacuumRoomsJourneyTests: VacuumJourneyTestCase {
    /// Rooms are selection tiles with order discs, setting the mode; Clean sends the selected-segments script. A flow: Clean follows the selection.
    func testRoomsCleanSelectAndStart() {
        let app = launch(Self.mainFloor)
        tab("Rooms", in: app)
        // Rooms are selection tiles: "selected" when chosen, never "switch", with the order in the label.
        let office = element("vacuum.room.input_boolean.roborock_office_toggle", in: app)
        XCTAssertTrue(office.appears(timeout: 10))
        reveal(office, in: app)
        assertTarget(office)
        XCTAssertEqual(office.value as? String, "Not selected")
        XCTAssertFalse(office.isSelected)
        XCTAssertFalse(office.label.contains("cleaning order"), "Unchosen rooms carry no order: \(office.label)")
        office.tap()
        let on = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Selected"), object: office)
        XCTAssertEqual(XCTWaiter().wait(for: [on], timeout: 5), .completed, "Office is \(office.value ?? "nil")")
        XCTAssertTrue(office.isSelected, "The selected trait")
        XCTAssertTrue(office.label.contains("cleaning order 3"), "Order in the label: \(office.label)")

        tab("Controls", in: app)
        let clean = app.buttons["vacuum.action.clean"]
        reveal(clean, in: app)
        assertTarget(clean)
        clean.tap()
        expectCall(expectations[.vacuumMainFloorCleanScript], in: app)
        XCTAssertTrue(app.buttons["vacuum.action.pause"].appears(timeout: 10), "Cleaning shows Pause")
        // The start-clean transition: the setup fades out and the tab control drops Rooms (web minimal mode).
        let rooms = element("vacuum.tabs", in: app).buttons["Rooms"]
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: rooms)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 10), .completed, "Rooms tab stays while cleaning")
        XCTAssertFalse(app.buttons["vacuum.action.clean"].exists, "The setup is gone")
    }

    /// Pause while cleaning sends vacuum.pause. Enters on the gallery's `cleaning` scenario (the one the capture test uses).
    func testRoomsCleanPauseWhileCleaning() {
        let app = launch(Self.mainFloor, scenario: "cleaning")
        let pause = app.buttons["vacuum.action.pause"]
        XCTAssertTrue(pause.appears(timeout: 10), "Cleaning shows Pause")
        reveal(pause, in: app)
        pause.tap()
        expectCall("vacuum.pause entity_id=\(expectations[.vacuumMainFloorEntity])", in: app)
    }

    func testRoomsPassAudit() throws { try audit(Self.mainFloor, tab: "zones") }
    func testRoomsPassAuditInIPadLandscape() throws { try audit(Self.mainFloor, tab: "zones", pose: .iPadLandscape) }
}
