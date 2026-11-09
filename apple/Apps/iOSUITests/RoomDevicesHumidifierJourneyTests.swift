import XCTest

/// The humidifier sheet in the debug gallery: presets, the dial, the fault state, schedules, the three tab audits and the largest-text reachability of its display.
@MainActor
final class RoomDevicesHumidifierJourneyTests: RoomDevicesJourneyTestCase {

    /// The mist preset sends the humidifier's level script; the dial is one adjustable handle.
    func testHumidifierMistLevelHigh() {
        let app = launch("humidifier", ready: "humidifier.power")
        let handle = element("thermostatDial.handle.target", in: app)
        let facts = try? handle.snapshot() // label, value and size from one read
        XCTAssertNotNil(facts, "The mist handle is not in the tree")
        XCTAssertEqual(facts?.label, "Mist level")
        XCTAssertEqual(facts?.value as? String, "5")
        assertTarget(handle)
        let high = segment("humidifier.mist", "High", in: app)
        reveal(high, in: app)
        high.tap()
        expectCall("script.\(expectations[.humidifierSetLevelScript]) level=8", in: app)
    }

    /// Warm mist High writes the warm-level number and becomes selected.
    func testHumidifierWarmLevelHigh() {
        let app = launch("humidifier", ready: "humidifier.power")
        let warm = segment("humidifier.warm", "High", in: app)
        reveal(warm, in: app)
        warm.tap()
        expectCall("number.set_value entity_id=\(expectations[.humidifierWarmLevel]) value=3", in: app)
        XCTAssertTrue(warm.wait(for: \.isSelected, toEqual: true, timeout: 5))
    }

    /// The target-humidity dial reads as an adjustable handle.
    func testHumidifierTargetHumidity() {
        let app = launch("humidifier", ready: "humidifier.power")
        let targetHandle = element("humidifier.targetDial", in: app).descendants(matching: .any)["thermostatDial.handle.target"].firstMatch
        // XCUITest reports an adjustable view inside the dial's group as not hittable (a drag on it works: ThermostatDialJourneyTests drags
        // it), so the dial's section is brought into view by the Warm Mist control under it and the handle is read by its 64 pt frame.
        reveal(element("humidifier.warm", in: app), in: app)
        XCTAssertTrue(targetHandle.appears(timeout: 10), "The target handle is not in the tree")
        let facts = try? targetHandle.snapshot()
        XCTAssertGreaterThanOrEqual(facts?.frame.width ?? 0, 44)
        XCTAssertGreaterThanOrEqual(facts?.frame.height ?? 0, 44)
        XCTAssertEqual(facts?.label, "Target humidity")
        XCTAssertEqual(facts?.value as? String, "50 percent")
    }

    /// Turn Off sends the power switch's service.
    func testHumidifierPowerOff() {
        let app = launch("humidifier", ready: "humidifier.power")
        let power = element("humidifier.power", in: app)
        reveal(power, in: app)
        power.tap()
        expectCall("switch.turn_off entity_id=\(expectations[.humidifierPower])", in: app)
    }

    /// A removed tank locks output and explains why.
    func testHumidifierFault() {
        let app = launch("humidifier-fault", ready: "humidifier.power")
        XCTAssertFalse(element("thermostatDial.handle.target", in: app).exists, "Read-only while faulted")
        XCTAssertTrue(app.staticTexts["Reinsert the water tank to restore controls."].exists)
        XCTAssertFalse(segment("humidifier.mode", "Sleep", in: app).isEnabled)
    }

    /// Schedules list the activities; editing one and saving writes the helper.
    func testHumidifierScheduleEditNight() {
        let app = launch("humidifier", ready: "humidifier.power", tab: "schedules")
        let night = element("humidifier.activity.Night", in: app)
        reveal(night, in: app)
        XCTAssertTrue(element("humidifier.activity.Evening", in: app).appears(timeout: 5))
        night.tap()
        let save = element("activity.save", in: app)
        XCTAssertTrue(save.appears(timeout: 5))
        // The fixture's Night runs Sunday–Thursday; adding Friday and Saturday makes it every day.
        element("activity.day.friday", in: app).tap()
        element("activity.day.saturday", in: app).tap()
        save.tap()
        XCTAssertTrue(night.appears(timeout: 10), "Back on the list after saving")
        XCTAssertTrue(night.label.contains("Every day"), night.label)
    }

    /// A new weekday night overlaps the existing Night, so its Save stays off.
    func testHumidifierScheduleAddOverlapping() {
        let app = launch("humidifier", ready: "humidifier.power", tab: "schedules")
        let add = element("humidifier.addActivity", in: app)
        reveal(add, in: app)
        add.tap()
        XCTAssertTrue(element("activity.save", in: app).appears(timeout: 5))
        XCTAssertTrue(app.staticTexts["This activity overlaps another activity on Monday."].appears(timeout: 5),
                      "A new weekday night overlaps the existing one")
        // Count the Saves a person can reach (a popped editor's toolbar item can linger in the tree on iPad); from a fresh
        // launch only the new editor's is expected, and the last one laid out is the one this test is about.
        let saves = app.descendants(matching: .any).matching(identifier: "activity.save")
        func reachable() -> [XCUIElement] { saves.allElementsBoundByIndex.filter { $0.isHittable } }
        // A bounded wait on a count (the popped editor's Save leaving the tree), polled at 100 ms.
        let deadline = Date().addingTimeInterval(10)
        while reachable().count > 1, Date() < deadline { usleep(100_000) }
        XCTAssertGreaterThanOrEqual(reachable().count, 1, "No editor Save is reachable")
        let saveNow = reachable().last ?? saves.firstMatch
        if saveNow.isEnabled { self.add(XCTAttachment(string: app.debugDescription)) } // `add` is the Add Activity row above.
        XCTAssertFalse(saveNow.isEnabled, "Save stays off while the activity overlaps another")
    }

    func testHumidifierControlsPassAudit() throws { try audit("humidifier", ready: "humidifier.power", pose: .upright) }
    func testHumidifierControlsPassAuditInIPadLandscape() throws { try audit("humidifier", ready: "humidifier.power", pose: .iPadLandscape) }
    func testHumidifierSchedulesPassAudit() throws { try audit("humidifier", ready: "humidifier.power", tab: "schedules", pose: .upright) }
    func testHumidifierSchedulesPassAuditInIPadLandscape() throws { try audit("humidifier", ready: "humidifier.power", tab: "schedules", pose: .iPadLandscape) }
    func testHumidifierInfoPassesAudit() throws { try audit("humidifier", ready: "humidifier.power", tab: "info", pose: .upright) }
    func testHumidifierInfoPassesAuditInIPadLandscape() throws { try audit("humidifier", ready: "humidifier.power", tab: "info", pose: .iPadLandscape) }

    /// At AX5 the humidifier sheet keeps its display reachable by scrolling.
    func testLargestTextKeepsHumidifierDisplayReachable() {
        let humidifier = launch("humidifier", ready: "humidifier.power", arguments: FentonHomeApp.ax5)
        reveal(element("humidifier.display", in: humidifier), in: humidifier, onLeadingEdge: true)
    }
}
