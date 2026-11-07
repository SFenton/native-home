import XCTest

/// The bed side sheet's Temperature and Status tabs and its Solo Trip scopes: the power prompt, stage steppers and scope prompt, the ringing alarm card and the sheet audits.
@MainActor
final class BedroomBedJourneyTests: BedroomJourneyTestCase {
    // MARK: - Bed side

    /// The dial handle reads the signed level; turning off asks first and sends the broker script.
    func testPowerAsksBeforeTurningOff() {
        let app = launch(sheet: expectations[.bedFirstSheetId])
        let handle = element("thermostatDial.handle.target", in: app)
        let handleFacts = try? handle.snapshot()
        XCTAssertEqual(handleFacts?.label, "\(expectations[.bedFirstTitle]) target level")
        XCTAssertEqual(handleFacts?.value as? String, "+3")
        let power = element("bed.power", in: app)
        assertTarget(power)
        power.tap()
        let confirm = turnOffConfirmation(in: app)
        XCTAssertTrue(confirm.appears(timeout: 5), "Turning off asks first")
        confirm.tap()
        expectCall(startingWith: "script.\(expectations[.bedHotFlashBrokerScript]) action=power_off side=left", in: app)
        XCTAssertTrue(element("bed.subtitle", in: app).wait(for: \.label, toEqual: "Off", timeout: 5))
        tap("bed.power", in: app)
        expectCall(startingWith: "script.\(expectations[.bedHotFlashBrokerScript]) action=power_heat", in: app)
    }

    /// Stepping the running stage sets tonight's target and asks Tonight or All Nights.
    func testRunningStageAsksForScope() {
        let app = launch(sheet: expectations[.bedFirstSheetId])
        tap("bed.stage.asleep.down", in: app)
        expectCall(startingWith: "script.\(expectations[.bedFirstTonightScript]) level=2", in: app)
        let allNights = element("bed.scope.allNights", in: app)
        XCTAssertTrue(allNights.appears(timeout: 5), "Scope prompt opens")
        allNights.tap()
        expectCall(containing: "entity_id=\(expectations[.bedFirstAsleepLevel])", in: app)
    }

    /// Other stages send the level and rewrite the schedule.
    func testOtherStagesPublishTheSchedule() {
        let app = launch(sheet: expectations[.bedFirstSheetId])
        let stage = element("bed.stage.bedtime", in: app)
        reveal(stage, in: app)
        XCTAssertEqual(stage.value as? String, "+4")
        tap("bed.stage.bedtime.up", in: app)
        expectCall(startingWith: "mqtt.publish payload=", in: app)
        XCTAssertEqual(element("bed.stage.bedtime", in: app).value as? String, "+5")
    }

    func testRingingAlarmCanBeSnoozedAndStopped() {
        let app = launch(sheet: expectations[.bedFirstSheetId], scenario: "ringing")
        XCTAssertTrue(element("bed.alarm.active", in: app).exists)
        tap("bed.alarm.snooze", in: app)
        expectCall(startingWith: "button.press entity_id=\(expectations[.bedFirstAlarmSnooze])", in: app)
        tap("bed.alarm.stop", in: app)
        expectCall(startingWith: "button.press entity_id=\(expectations[.bedFirstAlarmStop])", in: app)
        XCTAssertTrue(element("bed.alarm.active", in: app).disappears(timeout: 5))
    }

    func testTravelerSideIsReadOnly() {
        let app = launch(sheet: expectations[.bedSecondSheetId], scenario: "solo-trip")
        XCTAssertTrue(element("bed.soloTrip", in: app).exists)
        XCTAssertFalse(element("bed.power", in: app).exists, "The traveler's side has no power control")
        XCTAssertEqual(element("bed.hint", in: app).label, "Away · Read Only")
    }

    func testHomeSideControlsTheWholeBed() {
        let app = launch(sheet: expectations[.bedFirstSheetId], scenario: "solo-trip")
        XCTAssertTrue(app.navigationBars["\(expectations[.bedFirstTitle]) · Whole Bed"].exists)
        element("bed.power", in: app).tap()
        let confirm = turnOffConfirmation(in: app)
        XCTAssertTrue(confirm.appears(timeout: 5), "Turning off asks first")
        confirm.tap()
        expectCall(startingWith: "script.\(expectations[.bedHouseholdAwayScript]) action=set_power", in: app)
    }

    // MARK: - Accessibility audits

    func testBedTemperaturePassesAudit() throws { try audit(sheet: expectations[.bedFirstSheetId], scenario: "ringing") }
    func testBedTemperaturePassesAuditInIPadLandscape() throws { try audit(sheet: expectations[.bedFirstSheetId], scenario: "ringing", pose: .iPadLandscape) }

    func testBedStatusPassesAudit() throws { try audit(sheet: expectations[.bedFirstSheetId], tab: "status") }
    func testBedStatusPassesAuditInIPadLandscape() throws { try audit(sheet: expectations[.bedFirstSheetId], tab: "status", pose: .iPadLandscape) }

    func testSoloTripBedPassesAudit() throws { try audit(sheet: expectations[.bedSecondSheetId], scenario: "solo-trip") }
    func testSoloTripBedPassesAuditInIPadLandscape() throws { try audit(sheet: expectations[.bedSecondSheetId], scenario: "solo-trip", pose: .iPadLandscape) }
}
