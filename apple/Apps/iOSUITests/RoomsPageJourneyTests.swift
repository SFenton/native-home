import XCTest

/// Room pages: status chips, sheets, towel racks, sources, Bedroom 1, empty rooms, the Kitchen groceries and the page audits.
@MainActor
final class RoomsPageJourneyTests: RoomsJourneyTestCase {
    /// The Living Room's Lights chip opens the lights sheet; the Occupancy chip is a proper target.
    func testLivingRoomLightsChipSheet() {
        let app = launch(room: "living-room")
        XCTAssertTrue(app.navigationBars["Living Room"].exists)
        let occupancy = element("room.chip.Occupancy", in: app)
        XCTAssertTrue(occupancy.exists)
        assertTarget(occupancy)

        let lights = element("room.chip.Lights", in: app)
        lights.tap()
        XCTAssertTrue(element("room.sheet.lights-living-room", in: app).appears(timeout: 5))
        XCTAssertTrue(app.navigationBars["Living Room Lights"].exists)
    }

    /// The Vents card opens a read-only vent sheet whose open vent shows its position in the Vents family colour.
    func testLivingRoomVentsCardSheet() {
        let app = launch(room: "living-room")
        let vents = element("room.card.Vents", in: app)
        reveal(vents, in: app)
        vents.tap()
        XCTAssertTrue(element("room.entity.cover.demo_living_room_vent_1", in: app).appears(timeout: 5))
        XCTAssertFalse(app.buttons["room.entity.cover.demo_living_room_vent_1"].exists, "Read-only tiles are not buttons")
        XCTAssertEqual(element("room.entity.cover.demo_living_room_vent_1", in: app).value as? String, "Open · 60%",
                       "An open vent shows its position, as in Advanced Controls")
        // It fills with the Vents family while open (`#3B58B8`), like Advanced Controls' vent tiles. A read-only tile is flat (no
        // sheen, rim or shade; action-navigation-tiles.md, "Shape tells the class"), so the fill is the family colour itself.
        if let capture = RenderedContrast.Capture.screen() {
            let frame = element("room.entity.cover.demo_living_room_vent_1", in: app).frame
            let sample = TileGeometry.rgb(at: CGPoint(x: frame.minX + 10, y: frame.maxY - 10), in: capture)
            XCTAssertTrue(sample.map { TileGeometry.matches($0, 0x3B58B8) } ?? false,
                          "Open vent fill: \(String(describing: sample))")
        }
    }

    /// The Living Room Remote card opens the media remote sheet.
    func testLivingRoomRemoteOpensSheet() {
        let app = launch(room: "living-room")
        let remote = element("room.card.Living Room Remote", in: app)
        reveal(remote, in: app)
        remote.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.2)).tap() // The body, clear of the discs.
        XCTAssertTrue(element("remote.power", in: app).appears(timeout: 5), "Remote opens the media remote sheet")
    }

    /// The room rail's chips keep their text at 4.5:1 as rendered in their colours (Climate and Air Quality follow Home
    /// Assistant's colours, Occupancy fills when detected, Window reads the house), each named with its state.
    func testLivingRoomChipsReadOnTheirColours() throws {
        let app = launch(room: "living-room", clean: true)
        for title in ["Lights", "Climate", "Occupancy", "Window", "Air Quality"] {
            let chip = element("room.chip.\(title)", in: app)
            XCTAssertTrue(chip.appears(timeout: 10), title)
            XCTAssertTrue(chip.label.hasPrefix("\(title), "), chip.label)
            assertTarget(chip)
            if chip.frame.maxX <= app.windows.firstMatch.frame.maxX,
               let capture = RenderedContrast.Capture.screen(), let ratio = RenderedContrast.ratio(of: chip.frame, in: capture) {
                XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(title) chip measured \(ratio):1")
            }
        }
        keepScreenshot(app, "room-chips-\(FentonHomeApp.family)")
    }

    /// Towel racks send an explicit turn_on, then turn_off, never toggle.
    func testTowelRackSendsExplicitPower() {
        let app = launch(room: expectations[.roomsFirstFanRoom])
        let towel = app.switches["room.card.Towel Rack"]
        reveal(towel, in: app)
        XCTAssertEqual(towel.value as? String, "Off")
        towel.tap()
        expectCall("switch.turn_on entity_id=\(expectations[.roomsTowelRack])", in: app)
        let on = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "On"), object: towel)
        XCTAssertEqual(XCTWaiter().wait(for: [on], timeout: 5), .completed, "The fixture echoes the rack on")
        towel.tap()
        expectCall("switch.turn_off entity_id=\(expectations[.roomsTowelRack])", in: app)
    }

    /// Studio sources are selections that share the remote's optimistic state.
    func testMusicRoomSources() {
        let app = launch(room: expectations[.roomStudioId])
        let xbox = element("room.card.Game Console", in: app)
        reveal(xbox, in: app)
        xbox.tap()
        XCTAssertNotEqual(app.staticTexts["gallery.lastCall"].firstMatch.label, "Last call: None")
    }

    /// Bedroom 1: the wake light opens the Bedroom lane's sheet (fixture state, gallery caller).
    func testMasterBedroomOpensWakeLightSheet() {
        let app = launch(room: expectations[.roomBedroomId])
        let wake = element("room.card.Wake-Light Alarms", in: app)
        reveal(wake, in: app)
        wake.tap()
        XCTAssertTrue(element("wake.subtitle", in: app).appears(timeout: 10), "The wake light opens its sheet")
    }

    /// Bedroom 1: a bed opens the Bedroom lane's bed sheet.
    func testMasterBedroomOpensBedSheet() {
        let app = launch(room: expectations[.roomBedroomId])
        let bed = element("room.card.\(expectations[.bedFirstTitle])", in: app)
        reveal(bed, in: app)
        bed.tap()
        XCTAssertTrue(element("bed.dial", in: app).appears(timeout: 10), "The bed opens its sheet")
        XCTAssertTrue(element("bed.power", in: app).exists)
    }

    /// Bedroom 1's beds: one heating (filled), one idle in heat mode (the off face keeps the Heating glyph).
    /// The glyph colours are unit-tested (`ThermostatTileFace`); this keeps the page for review.
    func testIdleBedKeepsItsFamilyGlyph() {
        let app = launch(room: expectations[.roomBedroomId], clean: true)
        let idle = element("room.card.\(expectations[.bedSecondTitle])", in: app)
        reveal(idle, in: app)
        assertTarget(idle)
        reveal(element("room.card.\(expectations[.bedFirstTitle])", in: app), in: app)
        keepScreenshot(app, "\(expectations[.roomBedroomId])-beds-\(FentonHomeApp.family)")
    }

    /// Rooms without sections say so.
    func testEmptyRoom() {
        let app = launch(room: "hallway")
        XCTAssertTrue(element("room.empty", in: app).exists)
        XCTAssertTrue(app.staticTexts["Nothing Here Yet!"].exists)
    }

    /// The Kitchen's Groceries section pushes the grocery list and Food pages.
    func testKitchenGroceries() {
        let app = launch(room: "kitchen")
        let list = element("room.groceries.list", in: app)
        reveal(list, in: app)
        XCTAssertTrue(app.staticTexts["5 items"].exists)
        list.tap()
        XCTAssertTrue(app.navigationBars["Grocery List"].appears(timeout: 5))
    }

    // MARK: - Accessibility audits

    func testLivingRoomPassesAudit() throws { try audit(room: "living-room", pose: .upright) }
    func testLivingRoomPassesAuditInIPadLandscape() throws { try audit(room: "living-room", pose: .iPadLandscape) }
    func testMasterBedroomPassesAudit() throws { try audit(room: expectations[.roomBedroomId], pose: .upright) }
    func testMasterBedroomPassesAuditInIPadLandscape() throws { try audit(room: expectations[.roomBedroomId], pose: .iPadLandscape) }
    func testMusicRoomPassesAudit() throws { try audit(room: expectations[.roomStudioId], pose: .upright) }
    func testMusicRoomPassesAuditInIPadLandscape() throws { try audit(room: expectations[.roomStudioId], pose: .iPadLandscape) }
    func testKitchenPassesAudit() throws { try audit(room: "kitchen", pose: .upright) }
    func testKitchenPassesAuditInIPadLandscape() throws { try audit(room: "kitchen", pose: .iPadLandscape) }
}
