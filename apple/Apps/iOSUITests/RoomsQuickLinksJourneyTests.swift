import XCTest

/// Quick Links and the room grid (`QuickLinksSheet`): tiles, the ranked Rooms grid, the sheet height, page links and the audit.
@MainActor
final class RoomsQuickLinksJourneyTests: RoomsJourneyTestCase {
    /// Quick Links shows its tiles.
    func testQuickLinksTilesPresent() {
        let app = launch(quickLinks: true, sheetProbe: true)
        for id in ["rooms", "security-system", "food", "vacuums", "media", "custom-lights", "sprinklers"] {
            XCTAssertTrue(element("quickLinks.\(id)", in: app).exists, id)
        }
        XCTAssertTrue(app.staticTexts["42 Items • 3 Expiring Soon"].exists || element("quickLinks.food", in: app).value as? String == "42 Items • 3 Expiring Soon")
    }

    /// The Security System tile's disc (rollout L, audit item 17): the fixture's alarm is armed, so the disc offers Disarm, left of the
    /// chevron, and asks first; Cancel sends nothing and the body asks again.
    func testQuickLinksSecurityDiscAsksBeforeDisarm() {
        let app = launch(quickLinks: true, sheetProbe: true)
        let disc = app.buttons["quickLinks.security-system.action.alarm"]
        XCTAssertTrue(disc.appears(timeout: 10), "No Security System disc")
        let tile = wholeTile("quickLinks.security-system", in: app)
        XCTAssertEqual(disc.label, "Disarm Security System")
        settleScreen()
        assertTarget(disc, inSheet: app)
        XCTAssertLessThan(disc.frame.maxX, tile.maxX - 20, "The disc sits left of the chevron")
        disc.tap()
        let alert = app.alerts["Disarm the Security System?"]
        XCTAssertTrue(alert.appears(timeout: 5), "Disarm did not ask")
        // (The alert is modal: the gallery's last-call text is not in the accessibility tree until it closes.)
        alert.buttons["Cancel"].firstMatch.tap()
        XCTAssertTrue(alert.disappears(timeout: 5))
        XCTAssertEqual(app.staticTexts["gallery.lastCall"].firstMatch.label, "Last call: None", "Nothing is sent before the answer")
        disc.tap()
        XCTAssertTrue(alert.appears(timeout: 5), "The disc asks again")
    }

    /// Disarm sends `alarm_disarm` and the disc becomes Arm Home, which arms without asking.
    func testQuickLinksSecurityDiscDisarmsThenArms() {
        let app = launch(quickLinks: true, sheetProbe: true)
        let disc = app.buttons["quickLinks.security-system.action.alarm"]
        XCTAssertTrue(disc.appears(timeout: 10), "No Security System disc")
        disc.tap()
        let alert = app.alerts["Disarm the Security System?"]
        XCTAssertTrue(alert.appears(timeout: 5))
        // The alert button carries the tile's `.confirm` identifier and is exposed twice (the convention is firstMatch).
        alert.buttons["Disarm"].firstMatch.tap()
        expectCall("alarm_control_panel.alarm_disarm entity_id=\(expectations[.securityAlarm])", in: app)
        XCTAssertTrue(disc.wait(for: \.label, toEqual: "Arm Home Security System", timeout: 10), "The disc did not become Arm Home")
        disc.tap()
        expectCall("alarm_control_panel.alarm_arm_home entity_id=\(expectations[.securityAlarm])", in: app)
        XCTAssertFalse(app.alerts.firstMatch.exists, "Arming asks nothing")
    }

    /// The Security System tile's body still opens the alarm card beside its disc.
    func testQuickLinksSecurityBodyOpensTheAlarmCard() {
        let app = launch(quickLinks: true, sheetProbe: true)
        let tile = element("quickLinks.security-system", in: app)
        XCTAssertTrue(tile.appears(timeout: 10))
        tile.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).tap()
        XCTAssertTrue(app.navigationBars["Security System"].appears(timeout: 10), "The body did not open the alarm card")
    }

    /// Rooms pushes the ranked grid, and a room opens with its visit counted.
    func testQuickLinksOpensKitchen() {
        let app = launch(quickLinks: true, sheetProbe: true)
        // Read the scale once the sheet has finished presenting: a transform caught mid-animation would loosen the check.
        settleScreen()
        let drawnScale = sheetScale(in: app)
        element("quickLinks.rooms", in: app).tap()
        let kitchen = element("rooms.kitchen", in: app)
        XCTAssertTrue(kitchen.appears(timeout: 5))
        assertTarget(kitchen, inSheet: app, scale: drawnScale)
        kitchen.tap()
        XCTAssertTrue(app.navigationBars["Kitchen"].appears(timeout: 10), "Room pushes after the sheet closes")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", expectations[.roomsAccessIncrementScript])).firstMatch.exists
            || app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "script.turn_on")).firstMatch.exists)
    }

    /// The Rooms grid draws each room in its own colour with a filled white glyph and a vertically centred chevron
    /// (owner, 2026-10-16: "room tiles don't have nice colours, and icons should be filled/white").
    func testRoomsGridTilesAreColouredWithCentredChevrons() throws {
        let app = launch(quickLinks: true, clean: true, sheetProbe: true)
        settleScreen()
        let drawnScale = sheetScale(in: app)
        element("quickLinks.rooms", in: app).tap()
        XCTAssertTrue(element("rooms.kitchen", in: app).appears(timeout: 5))
        settleScreen()
        keepScreenshot(app, "rooms-grid-\(FentonHomeApp.family)")
        let capture = try XCTUnwrap(RenderedContrast.Capture.screen())
        let windowMaxY = app.windows.firstMatch.frame.maxY
        let expected: [String: UInt32] = ["kitchen": 0x547F12, "gym": 0xAF5F00, "garage": 0xA6222C, "living-room": 0x8A6F44]
        for (room, fill) in expected {
            let tile = element("rooms.\(room)", in: app)
            // Below the fold on a short window: a tile can be hittable while its bottom edge is off the screen.
            guard isReachable(tile), tile.frame.maxY < windowMaxY - 20 else { continue }
            assertTarget(tile, inSheet: app, scale: drawnScale)
            let frame = tile.frame
            let sample = try XCTUnwrap(TileGeometry.rgb(at: CGPoint(x: frame.minX + 10, y: frame.maxY - 10), in: capture))
            XCTAssertTrue(TileGeometry.matchesGlass(sample, fill, heightFraction: 1 - 10 / frame.height),
                          "\(room) is \(sample), expected \(String(fill, radix: 16)) under tinted glass")
            let chevron = try XCTUnwrap(TileGeometry.chevron(in: frame, capture: capture), "\(room): no chevron")
            XCTAssertEqual(chevron.midY, frame.midY, accuracy: 3, "\(room) chevron is vertically centred")
            // A filled white glyph: white ink in the leading 44 pt column, and nothing else but the title beside it.
            let glyphColumn = CGRect(x: frame.minX + 8, y: frame.minY + 6, width: 36, height: frame.height - 12)
            // Only near-white differs from every room fill by this much, so a family-coloured glyph would not register.
            let glyph = try XCTUnwrap(TileGeometry.inkBounds(in: glyphColumn, background: sample, threshold: 400, capture: capture),
                                      "\(room): no white glyph")
            XCTAssertGreaterThan(glyph.height, 14, "\(room) glyph is drawn")
        }
    }

    /// Quick Links is only as tall as its tiles, and the page on top owns the height (owner, 2026-10-26: "it should only
    /// show what it has to on any device"): Rooms refits the sheet, Back restores the tiles' height. An iPad sheet keeps
    /// its first height, so there only the fit is checked.
    func testQuickLinksFitsThePageOnTop() {
        let app = launch(quickLinks: true, sheetProbe: true)
        let window = app.windows.firstMatch.frame
        // The sheet's visible height: from the top of its bar to the bottom of the window.
        func sheetHeight(_ title: String) -> CGFloat { window.maxY - app.navigationBars[title].firstMatch.frame.minY }
        XCTAssertTrue(app.navigationBars["Quick Links"].firstMatch.appears(timeout: 5))
        let tiles = sheetHeight("Quick Links")
        let lastTile = element("quickLinks.sprinklers", in: app).frame
        // Fitted: under the last row there is only the content padding and the home-indicator area, not a screen of ground and not
        // the 34 pt band the detent used to add (`proposals/sheet-bottom-gap`, option B): 56 pt on an iPhone, 58 on the Duo, 43 on an iPad.
        if lastTile.maxY <= window.maxY {
            XCTAssertLessThan(window.maxY - lastTile.maxY, 72, "Quick Links has empty ground under its tiles (sheet \(tiles) pt)")
        }
        guard FentonHomeApp.family != .iPad else { return }
        element("quickLinks.rooms", in: app).tap()
        XCTAssertTrue(app.navigationBars["Rooms"].firstMatch.appears(timeout: 5))
        settleScreen()
        // Rooms is taller than the tiles: the sheet grows unless the tiles already filled the largest sheet.
        XCTAssertGreaterThanOrEqual(sheetHeight("Rooms"), tiles - 1, "Rooms shrank the sheet")
        if tiles < window.height - 120 {
            XCTAssertGreaterThan(sheetHeight("Rooms"), tiles + 20, "Rooms did not refit the sheet; fit probe: \(element("sheet.fit.probe", in: app).value as? String ?? "none"), window \(window.height)")
        }
        // Back: the system `BackButton` (the Duo's rail), else the bar button that is not Close (as ClimateJourneyTests).
        let tiles0 = element("quickLinks.rooms", in: app)
        var candidates: [XCUIElement] = [app.buttons["BackButton"]]
        candidates += app.navigationBars.buttons.allElementsBoundByIndex.filter { $0.label != "Close" }
        var returned = false
        for button in candidates where isReachable(button) {
            button.tap()
            // The pop and the sheet's refit take a while on a loaded Duo (an accessibility query alone can take 3 s there), so wait
            // for the tiles to be hittable for longer than one query.
            let shown = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: tiles0)
            if XCTWaiter().wait(for: [shown], timeout: 15) == .completed { returned = true; break }
        }
        XCTAssertTrue(returned, "Back did not return to the tiles")
        settleScreen()
        XCTAssertEqual(sheetHeight("Quick Links"), tiles, accuracy: 2, "Back did not restore the tiles' height")
    }

    /// Page links close Quick Links and push their page.
    func testQuickLinksPushAPage() {
        let app = launch(quickLinks: true, sheetProbe: true)
        element("quickLinks.media", in: app).tap()
        XCTAssertTrue(app.navigationBars["Media"].appears(timeout: 10))
    }

    // MARK: - Accessibility audits

    func testQuickLinksPassesAudit() throws { try audit(quickLinks: true, pose: .upright) }
    func testQuickLinksPassesAuditInIPadLandscape() throws { try audit(quickLinks: true, pose: .iPadLandscape) }
}
