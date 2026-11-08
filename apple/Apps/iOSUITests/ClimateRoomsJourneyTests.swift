import XCTest

/// The Climate sheet's Rooms tab and a room's page: the colour room tiles, the dial and the vents, with their audits.
@MainActor
final class ClimateRoomsJourneyTests: ClimateJourneyTestCase {
    // MARK: - Rooms

    /// The Rooms tab is a grid of the same colour room tiles as the Rooms grid: a button each, a solid fill, a filled white
    /// glyph and a vertically centred chevron (owner, 2026-10-16: "standardise on room tiles across the app").
    func testRoomsTabShowsColourRoomTiles() throws {
        let app = launch(open: "rooms")
        settleScreen()
        keepScreenshot(app, "climate-rooms-tab-\(FentonHomeApp.family)")
        let capture = try XCTUnwrap(RenderedContrast.Capture.screen())
        let expected: [String: UInt32] = ["living_room": 0x8A6F44, "office": 0x007E94, "master_bedroom": 0x3E3EB7]
        for (key, fill) in expected {
            let tile = element("climate.room.\(key)", in: app)
            XCTAssertTrue(tile.appears(timeout: 5), key)
            XCTAssertEqual(tile.elementType, .button, "A room tile opens its room")
            XCTAssertGreaterThanOrEqual(tile.frame.height, 43)
            guard tile.isHittable, app.windows.firstMatch.frame.contains(tile.frame) else { continue }
            let frame = tile.frame
            let sample = try XCTUnwrap(TileGeometry.rgb(at: CGPoint(x: frame.minX + 10, y: frame.maxY - 10), in: capture))
            XCTAssertTrue(TileGeometry.matchesGlass(sample, fill, heightFraction: 1 - 10 / frame.height),
                          "\(key) is \(sample), expected \(String(fill, radix: 16)) under tinted glass")
            let chevron = try XCTUnwrap(TileGeometry.chevron(in: frame, capture: capture), "\(key): no chevron")
            XCTAssertEqual(chevron.midY, frame.midY, accuracy: 3, "\(key) chevron is vertically centred")
        }
    }

    /// A room shows its subtitle, opens its dial, vents and Back returns to Rooms.
    func testRoomDetailShowsDialAndVents() {
        let app = launch(open: "rooms")
        let living = element("climate.room.living_room", in: app)
        XCTAssertTrue(living.appears(timeout: 5))
        XCTAssertEqual(living.label, "Living Room")
        XCTAssertEqual(value(living), "70.9°F\nOccupied")
        living.tap()
        XCTAssertTrue(heading("Living Room", in: app).appears(timeout: 5))
        let dial = element("climate.roomDial", in: app)
        XCTAssertTrue(dial.appears(timeout: 5))
        XCTAssertEqual(dial.descendants(matching: .any)["thermostatDial.handle.low"].firstMatch.label, "Living Room heat to")
        let vent = reveal(element("climate.vent.cover.demo_living_room_vent_2", in: app), in: app)
        XCTAssertNotEqual(vent.elementType, .button, "Vents are read-only")
        XCTAssertEqual(vent.label, "Vent 2")
        XCTAssertEqual(value(vent), "Open · 50%", "A vent tile shows how far it is open")
        XCTAssertEqual(value(element("climate.vent.cover.demo_living_room_vent_1", in: app)), "Open · 100%")
        XCTAssertTrue(header("Living Room Vents", in: app).exists)
        back(app)
        XCTAssertTrue(element("climate.sheet.rooms", in: app).appears(timeout: 5))
    }

    func testRoomsTabPassesAudit() throws { try audit(open: "rooms") }

    func testRoomDetailPassesAudit() throws { try audit(open: "room:master_bedroom") }
}
