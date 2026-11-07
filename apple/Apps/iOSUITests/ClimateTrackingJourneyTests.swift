import XCTest

/// The Climate sheet's Tracking tab and its room pages: the opener counts, the room switches and the audits.
@MainActor
final class ClimateTrackingJourneyTests: ClimateJourneyTestCase {
    // MARK: - Tracking

    /// Tracking: counts in the openers follow the room switches; turning off Track Selected Rooms disables the
    /// Selected Rooms and Critical Protection openers.
    func testTrackingCountsAndRoomPages() {
        let app = launch(open: "tracking")
        let selected = reveal(element("climate.tracking.selected-rooms", in: app), in: app)
        XCTAssertEqual(value(selected), "3 of 11 selected")
        XCTAssertEqual(value(element("climate.tracking.critical-protection", in: app)), "1 room forced")
        XCTAssertEqual(value(element("climate.tracking.occupied-only", in: app)), "2 of 11 occupied only")
        selected.tap()
        XCTAssertTrue(heading("Selected Rooms", in: app).appears(timeout: 5))
        let kitchen = reveal(element("climate.track.selected-rooms.kitchen", in: app), in: app)
        XCTAssertEqual(kitchen.label, "Kitchen")
        XCTAssertFalse(kitchen.isSelected, "A room that is off is not selected")
        kitchen.tap()
        XCTAssertTrue(isSelected(kitchen))
        waitForCall("homeassistant.toggle entity_id=switch.thermostat_contact_sensors_track_kitchen", in: app)
        back(app)
        XCTAssertTrue(hasValue(reveal(element("climate.tracking.selected-rooms", in: app), in: app), "4 of 11 selected"))

        reveal(element("climate.tracking.critical-protection", in: app), in: app).tap()
        XCTAssertTrue(heading("Critical Protection", in: app).appears(timeout: 5))
        XCTAssertFalse(element("climate.track.critical-protection.office", in: app).exists, "Tracked rooms are not listed")
        XCTAssertTrue(isSelected(reveal(element("climate.track.critical-protection.guest_room", in: app), in: app)))
        back(app)

        let track = reveal(element("climate.toggle.switch.thermostat_contact_sensors_only_track_selected_rooms", in: app), in: app)
        flip(track)
        XCTAssertTrue(hasValue(track, "0"))
        let disabled = reveal(element("climate.tracking.selected-rooms", in: app), in: app)
        XCTAssertFalse(disabled.isEnabled)
        XCTAssertEqual(value(disabled), "Enable Track Selected Rooms first")
        XCTAssertFalse(element("climate.tracking.critical-protection", in: app).isEnabled)
    }

    func testTrackingTabPassesAudit() throws { try audit(open: "tracking") }

    func testTrackingDetailPassesAudit() throws { try audit(open: "selected-rooms") }
}
