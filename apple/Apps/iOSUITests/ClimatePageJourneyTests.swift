import XCTest

/// The Climate page: the Whole Home dial, the Thermostat Hub row and its pop-up menus, the open-contact cards, the three entries and the page and
/// hub-picker audits (`.agents/pages/climate/ios.md`). Every journey runs on the gallery fixtures, so none changes the house.
@MainActor
final class ClimatePageJourneyTests: ClimateJourneyTestCase {
    // MARK: - Page

    /// Whole Home dial, hub row and pop-up menus, open contacts and the three entries, with names and roles.
    func testPageSectionsAndSemantics() {
        let app = launch()
        XCTAssertTrue(element("thermostatDial.readout", in: app).label.hasPrefix("Whole Home thermostat, Heating"))
        XCTAssertEqual(hubRow(in: app).label, "Thermostat Hub, Heat")
        let mode = element("climate.hub.mode", in: app)
        XCTAssertEqual(mode.label, "Thermostat Hub Mode")
        XCTAssertEqual(value(mode), "Heat")
        XCTAssertGreaterThanOrEqual(mode.frame.height, 43)
        XCTAssertEqual(value(element("climate.hub.fan", in: app)), "Auto")
        XCTAssertFalse(element("climate.awayNotice", in: app).exists, "Home shows no away notice")
        XCTAssertFalse(element("climate.integrationWarning", in: app).exists)
        let window = element("climate.contact.binary_sensor.demo_office_contact_2", in: app)
        XCTAssertTrue(window.exists)
        XCTAssertEqual(window.label, "Office Window")
        XCTAssertEqual(value(window), "Open")
        XCTAssertNotEqual(window.elementType, .button, "Contact cards are not buttons")
        for (tab, title) in [("rooms", "Room Thermostats"), ("automation", "Advanced Configuration"), ("tracking", "Room Tracking")] {
            let entry = reveal(element("climate.entry.\(tab)", in: app), in: app)
            XCTAssertEqual(entry.label, title)
            XCTAssertGreaterThanOrEqual(entry.frame.height, 43)
        }
    }

    /// Whole Home is compact (owner, 2026-10-16: "takes up too much space now and I don't want the card background"):
    /// the dial sits straight on the wallpaper with no card around it, and the hub is one short pill under it.
    func testWholeHomeIsCompactWithNoCard() throws {
        let app = launch(clean: true)
        let home = element("climate.wholeHome", in: app)
        let hub = element("climate.hub", in: app)
        XCTAssertTrue(hub.appears(timeout: 5))
        XCTAssertLessThan(hub.frame.height, 90, "The hub is one compact row, not two list rows")
        XCTAssertLessThanOrEqual(hub.frame.minY - home.frame.maxY, 20, "The hub sits right under the dial")
        keepScreenshot(app, "climate-whole-home-\(FentonHomeApp.family)")
        // No card: the dial container's corner is the wallpaper, the same as the page margin beside it.
        let capture = try XCTUnwrap(RenderedContrast.Capture.screen())
        let inside = try XCTUnwrap(TileGeometry.rgb(at: CGPoint(x: home.frame.minX + 6, y: home.frame.minY + 6), in: capture))
        let beside = try XCTUnwrap(TileGeometry.rgb(at: CGPoint(x: max(2, home.frame.minX - 6), y: home.frame.minY + 6), in: capture))
        XCTAssertLessThan(abs(inside.r - beside.r) + abs(inside.g - beside.g) + abs(inside.b - beside.b), 30,
                          "The dial has no card background: \(inside) vs \(beside)")
    }

    /// Away on vacation: the notice reads Vacation Mode, Automatic Thermostat's warning shows, nothing is open.
    func testAwayScenarioShowsTheNoticeAndWarning() {
        let app = launch(scenario: "away")
        let notice = element("climate.awayNotice", in: app)
        XCTAssertTrue(notice.appears(timeout: 5))
        XCTAssertTrue(notice.label.hasPrefix("Vacation Mode Active. The room may be cooler or warmer"), notice.label)
        XCTAssertTrue(reveal(element("climate.integrationWarning", in: app), in: app).label.hasPrefix("Automatic Thermostat is off."))
        XCTAssertFalse(app.staticTexts["Open Contact Sensors"].exists)
        // The dial shows the eco-away thermostat's wider range.
        XCTAssertEqual(element("thermostatDial.handle.low", in: app).value as? String, "62 degrees")
    }

    /// The hub's mode and fan dropdowns are native menus with the current choice checked; a choice closes the menu
    /// and sends `climate.set_hvac_mode` / `climate.set_fan_mode`.
    func testHubDropdownsSendModeAndFan() {
        let app = launch()
        element("climate.hub.mode", in: app).tap()
        let cool = menuItem("Cool", in: app)
        XCTAssertTrue(cool.appears(timeout: 5), "Mode menu did not open")
        XCTAssertTrue(menuItem("Heat", in: app).isSelected, "The current mode is checked")
        cool.tap()
        waitForCall("climate.set_hvac_mode entity_id=\(expectations[.climateHub]) hvac_mode=cool", in: app)
        XCTAssertTrue(hasValue(element("climate.hub.mode", in: app), "Cool"))

        element("climate.hub.fan", in: app).tap()
        let on = menuItem("On", in: app)
        XCTAssertTrue(on.appears(timeout: 5), "Fan menu did not open")
        on.tap()
        XCTAssertTrue(element("climate.hub.fan", in: app).appears(timeout: 5), "Fan menu closes after a choice")
        waitForCall("climate.set_fan_mode entity_id=\(expectations[.climateHub]) fan_mode=on", in: app)
    }

    /// An entry opens the sheet on its tab; the tab control switches tabs; Close closes it.
    func testEntriesOpenTheSheetOnTheirTab() {
        let app = launch()
        reveal(element("climate.entry.tracking", in: app), in: app).tap()
        XCTAssertTrue(element("climate.sheet.tracking", in: app).appears(timeout: 5))
        XCTAssertTrue(heading("Advanced Controls", in: app).exists)
        let tabs = app.segmentedControls["climate.sheet.tabs"]
        if tabs.exists {
            tabs.buttons["Rooms"].tap()
        } else {
            // A menu at accessibility sizes.
            element("climate.sheet.tabs", in: app).tap()
            app.buttons["Rooms"].tap()
        }
        XCTAssertTrue(element("climate.sheet.rooms", in: app).appears(timeout: 5))
        // Forms load rows as they scroll: the first and the last room.
        XCTAssertTrue(element("climate.room.living_room", in: app).appears(timeout: 5))
        XCTAssertTrue(reveal(element("climate.room.theater_room", in: app), in: app).exists)
        app.buttons["Close"].tap()
        XCTAssertTrue(element("climate.wholeHome", in: app).appears(timeout: 5))
    }

    func testPagePassesAuditPortrait() throws { try audit() }

    /// iPad landscape only; the other families have no such pose.
    func testPagePassesAuditIPadLandscape() throws {
        guard FentonHomeApp.family == .iPad else { throw XCTSkip("iPad only") }
        XCUIDevice.shared.orientation = .landscapeLeft
        settleScreen()
        try audit()
    }

    func testAwayPagePassesAudit() throws { try audit(scenario: "away") }

    func testHubPickerPassesAudit() throws {
        try audit { app in
            self.element("climate.hub.mode", in: app).tap()
            XCTAssertTrue(self.menuItem("Cool", in: app).appears(timeout: 5))
        }
    }

    /// At AX5 every entry and the tab control stay reachable.
    func testLargestTextKeepsEntriesReachable() {
        let app = launch(arguments: FentonHomeApp.ax5)
        for tab in ["rooms", "automation", "tracking"] {
            XCTAssertTrue(reveal(element("climate.entry.\(tab)", in: app), in: app).isHittable)
        }
        element("climate.entry.tracking", in: app).tap()
        XCTAssertTrue(element("climate.sheet.tabs", in: app).appears(timeout: 5), "The tab control becomes a menu at AX5")
    }
}
