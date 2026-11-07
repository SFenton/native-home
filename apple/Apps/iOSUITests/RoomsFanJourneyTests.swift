import XCTest

/// The bathroom fan tile (`BathroomFanRoomTile`): its rail, value, unavailable face, AX5 layout, sheet fit and the two bathroom audits.
@MainActor
final class RoomsFanJourneyTests: RoomsJourneyTestCase {
    /// The bathroom fan tile's Lock and Power send the fan script's explicit target state; fixture state only.
    func testRoomsFanPowerSendsTarget() {
        let app = launch(room: "guest-bathroom")
        // Toggle accessories are switches to XCUITest (like the towel rack).
        let power = app.switches["room.card.Fan.action.power"]
        let lock = app.switches["room.card.Fan.action.lock"]
        reveal(power, in: app)
        XCTAssertEqual(power.value as? String, "Off")
        XCTAssertEqual(lock.value as? String, "Off")
        assertTarget(power)
        assertTarget(lock)
        power.tap()
        let call = app.staticTexts["gallery.lastCall"].firstMatch
        let sent = NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "script.\(expectations[.fanFirstScript])", "target_power=on")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: sent, object: call)], timeout: 10), .completed,
                       "Power sends an explicit target, got '\(call.label)'")
        XCTAssertFalse(call.label.contains("toggle"))
    }

    /// The fan tile opens the fan sheet (it needs no prior power tap).
    func testRoomsFanOpensFanSheet() {
        let app = launch(room: "guest-bathroom")
        let tile = element("room.card.Fan", in: app)
        reveal(tile, in: app)
        tile.tap()
        XCTAssertTrue(element("device.sheet.fan", in: app).appears(timeout: 10), "The fan tile opens the fan sheet")
    }

    /// The Air Purifier opens the air quality sheet.
    func testRoomsFanPurifierOpensSheet() {
        let living = launch(room: "living-room")
        let purifier = element("room.card.Air Purifier", in: living)
        reveal(purifier, in: living)
        purifier.tap()
        XCTAssertTrue(element("device.sheet.purifier", in: living).appears(timeout: 10), "Air Purifier opens the air quality sheet")
    }

    // MARK: - Bathroom fan tile (owner design, 2026-10-17)

    /// The fan tile and its two buttons by the fan's power entity.
    private func fanButtons(in app: XCUIApplication) -> (tile: XCUIElement, lock: XCUIElement, power: XCUIElement) {
        (element("room.card.Fan", in: app), app.switches["room.card.Fan.action.lock"], app.switches["room.card.Fan.action.power"])
    }

    /// The chevron's ink, measured clear of the rail's own edge (the rail ends 32 pt in from the tile's edge).
    private func chevronBounds(of frame: CGRect) throws -> CGRect {
        let capture = try XCTUnwrap(RenderedContrast.Capture.screen())
        let background = try XCTUnwrap(TileGeometry.rgb(at: CGPoint(x: frame.maxX - 18, y: frame.minY + 6), in: capture))
        let region = CGRect(x: frame.maxX - 29, y: frame.minY + 14, width: 25, height: frame.height - 28)
        return try XCTUnwrap(TileGeometry.inkBounds(in: region, background: background, capture: capture), "No chevron drawn")
    }

    /// The Power button no longer sits under the chevron: the rail is vertically centred, its circles are 44 pt, and
    /// the chevron has its own slot to the right of them. Off/unlocked (Guest) and on/locked/timed (Master).
    private func assertFanRail(room: String, lit: Bool) throws {
        let app = launch(room: room, clean: true)
        let (_, lock, power) = fanButtons(in: app)
        reveal(power, in: app)
        for button in [lock, power] {
            assertTarget(button)
            XCTAssertEqual(button.frame.width, button.frame.height, accuracy: 1, "\(room): a circle")
            XCTAssertEqual(button.frame.midY, wholeTile("room.card.Fan", in: app).midY, accuracy: 2, "\(room): centred on the tile")
        }
        XCTAssertLessThan(lock.frame.maxX, power.frame.minX, "Lock then Power, not overlapping")
        let tileFrame = wholeTile("room.card.Fan", in: app)
        let chevron = try chevronBounds(of: tileFrame)
        XCTAssertFalse(power.frame.intersects(chevron), "\(room): the chevron is not under Power")
        XCTAssertGreaterThanOrEqual(chevron.minX - power.frame.maxX, 6, "\(room): spacing before the chevron")
        XCTAssertEqual(chevron.midY, tileFrame.midY, accuracy: 3, "\(room): the chevron stays centred")
        // Active: a solid white circle. Inactive: a translucent one, never white.
        let capture = try XCTUnwrap(RenderedContrast.Capture.screen())
        for button in [lock, power] {
            let sample = try XCTUnwrap(TileGeometry.rgb(at: CGPoint(x: button.frame.minX + 5, y: button.frame.midY), in: capture))
            if lit {
                XCTAssertTrue(TileGeometry.matches(sample, 0xFFFFFF, tolerance: 12), "\(room) \(button.label) is solid white: \(sample)")
            } else {
                XCTAssertLessThan(sample.r, 160, "\(room) \(button.label) is translucent, not white: \(sample)")
            }
        }
        keepScreenshot(app, "fan-tile-\(room)-\(FentonHomeApp.family)")
    }

    func testFanRailGuestBathroomIsCentred() throws {
        try assertFanRail(room: expectations[.roomsFirstFanRoom], lit: false)
    }

    func testFanRailMasterBathroomIsCentred() throws {
        try assertFanRail(room: expectations[.roomsSecondFanRoom], lit: true)
    }

    /// One short status line, with the lock spoken rather than written: VoiceOver reads "on, off in 12 minutes, locked".
    func testFanTileValueMaster() {
        let master = launch(room: expectations[.roomsSecondFanRoom])
        let tile = element("room.card.Fan", in: master)
        reveal(tile, in: master)
        let value = tile.value as? String ?? ""
        XCTAssertTrue(value.hasPrefix("on, off in 1") && value.hasSuffix(" minutes, locked"), "Spoken value: \(value)")
        XCTAssertEqual(master.switches["room.card.Fan.action.lock"].value as? String, "On")
        XCTAssertEqual(master.switches["room.card.Fan.action.power"].value as? String, "On")
    }

    /// An idle fan speaks "off" and its lock reads Off.
    func testFanTileValueGuest() {
        let guest = launch(room: "guest-bathroom")
        let off = element("room.card.Fan", in: guest)
        reveal(off, in: guest)
        XCTAssertEqual(off.value as? String, "off")
        XCTAssertEqual(guest.switches["room.card.Fan.action.lock"].value as? String, "Off")
    }

    /// An unavailable fan says so and its Lock and Power discs dim in place: they stay present but disabled, so the tile never
    /// changes shape (action-navigation-tiles.md, decided 2026-10-26).
    func testUnavailableFanDimsItsButtonsInPlace() {
        let app = launch(room: "guest-bathroom", scenario: "fan-unavailable")
        let tile = element("room.card.Fan", in: app)
        reveal(tile, in: app)
        XCTAssertEqual(tile.value as? String, "Unavailable")
        for action in ["power", "lock"] {
            let disc = app.switches["room.card.Fan.action.\(action)"]
            XCTAssertTrue(disc.exists, "the \(action) disc stays in place")
            XCTAssertFalse(disc.isEnabled, "the \(action) disc is dimmed and disabled")
        }
        keepScreenshot(app, "fan-tile-unavailable-\(FentonHomeApp.family)")
    }

    /// At the largest text the buttons drop below the status, stay circles no larger than 66 pt, and stay in the tile.
    func testFanRailMovesBelowTheTextAtAX5() {
        let app = launch(room: expectations[.roomsSecondFanRoom], arguments: FentonHomeApp.ax5)
        let (_, lock, power) = fanButtons(in: app)
        reveal(power, in: app)
        let tileFrame = wholeTile("room.card.Fan", in: app)
        for button in [lock, power] {
            XCTAssertGreaterThanOrEqual(button.frame.width, 43)
            XCTAssertLessThanOrEqual(button.frame.width, 67, "The circle is capped, so the glyph cannot outgrow it")
            XCTAssertEqual(button.frame.width, button.frame.height, accuracy: 1)
            XCTAssertTrue(tileFrame.insetBy(dx: -1, dy: -1).contains(button.frame), "Inside the tile")
        }
        XCTAssertGreaterThan(power.frame.minY, tileFrame.midY, "Below the status text, not wrapped beside it")
        XCTAssertLessThan(lock.frame.minX, tileFrame.midX, "Leading, under the text")
        XCTAssertLessThan(lock.frame.maxX, power.frame.minX)
        keepScreenshot(app, "fan-tile-ax5-\(FentonHomeApp.family)")
    }

    /// Opened from its room tile (the real route), the fan sheet is as tall as its content: no band of empty ground under
    /// the last control. Idle (Guest) and timed (Master).
    private func assertFanSheetFits(room: String, last: String) {
        let app = launch(room: room, clean: true)
        let tile = element("room.card.Fan", in: app)
        reveal(tile, in: app)
        tile.tap()
        let control = element(last, in: app)
        XCTAssertTrue(control.appears(timeout: 10), "\(room): the fan sheet opened")
        settleScreen() // The detent settles after the first measurement.
        keepScreenshot(app, "fan-sheet-from-tile-\(room)-\(FentonHomeApp.family)")
        XCTAssertTrue(control.isHittable, "\(room): the last control is on screen without scrolling")
        // The sheet's own bottom edge, not the window's: a content-fitted iPad form sheet is centred in the window
        // (`presentationSizing` fitted), so the window's ground below it is not the sheet's (guest bathroom, iPad:
        // 374 pt sheet, 418 pt of page under it).
        let sheet = element("device.sheet.fan", in: app).frame
        if FentonHomeApp.family == .iPhoneDuo {
            // Folded and beside a vertical hinge every sheet fills the height from the bottom (owner, 2026-10-31,
            // `DuoSheetPolicy.fillsHeight`; ModalSizing asserts the same): the ground under the last control is the full sheet's.
            XCTAssertGreaterThan(sheet.height, app.windows.firstMatch.frame.height * 0.6, "\(room): a Duo sheet fills the height")
            return
        }
        let edge = sheet.isEmpty ? app.windows.firstMatch.frame.maxY : sheet.maxY
        // The footnote (idle) sits a little below the button; the button is last while timed.
        let bottom = room == "guest-bathroom" ? control.frame.maxY + 60 : control.frame.maxY
        XCTAssertLessThanOrEqual(edge - bottom, 100, "\(room): empty ground under the last control")
    }

    func testFanSheetHeightFitsGuest() { assertFanSheetFits(room: "guest-bathroom", last: "fan.setTimer") }

    func testFanSheetHeightFitsMaster() { assertFanSheetFits(room: "master-bathroom", last: "fan.clearTimer") }

    // MARK: - Accessibility audits

    func testGuestBathroomPassesAudit() throws { try audit(room: "guest-bathroom", pose: .upright) }
    func testGuestBathroomPassesAuditInIPadLandscape() throws { try audit(room: "guest-bathroom", pose: .iPadLandscape) }
    /// The fan on, locked and timed, with its countdown and lit buttons.
    func testMasterBathroomPassesAudit() throws { try audit(room: "master-bathroom", pose: .upright) }
    func testMasterBathroomPassesAuditInIPadLandscape() throws { try audit(room: "master-bathroom", pose: .iPadLandscape) }
}
