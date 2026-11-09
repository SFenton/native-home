import XCTest

/// The Climate sheet's Automation tab: the toggles, the Eco option page and Predictive Comfort with its detail, with their audits.
@MainActor
final class ClimateAutomationJourneyTests: ClimateJourneyTestCase {
    // MARK: - Automation

    /// Automation: toggles are system switches that send `homeassistant.toggle`.
    func testAutomationEcoModeToggle() {
        let app = launch(open: "automation")
        let eco = reveal(element("climate.toggle.switch.demo_contact_1", in: app), in: app)
        XCTAssertEqual(eco.label, "Eco Mode")
        XCTAssertEqual(value(eco), "1")
        flip(eco)
        XCTAssertTrue(hasValue(eco, "0"))
        waitForCall("homeassistant.toggle entity_id=switch.demo_contact_1", in: app)
    }

    /// An Eco option page selects with `select.select_option` and its row shows the new value. Enters from the Automation tab, as a
    /// person does, because the row's name and value before the tap are part of the check.
    func testAutomationEcoAwayOptionPage() {
        let app = launch(open: "automation")
        let opener = reveal(element("climate.eco.eco-away", in: app), in: app)
        XCTAssertEqual(opener.label, "Eco Behavior When Away")
        XCTAssertEqual(value(opener), "Keep Eco Active")
        opener.tap()
        XCTAssertTrue(heading("Eco Behavior When Away", in: app).appears(timeout: 5))
        XCTAssertTrue(element("climate.option.Keep Eco Active", in: app).isSelected)
        let targets = reveal(element("climate.option.Use Eco Away Targets", in: app), in: app)
        XCTAssertTrue(targets.label.hasSuffix("Use the wider away temperature range while everyone is away."), targets.label)
        targets.tap()
        XCTAssertTrue(targets.wait(for: \.isSelected, toEqual: true, timeout: 3))
        waitForCall("select.select_option entity_id=select.demo_contact_1 option=Use Eco Away Targets", in: app)
        back(app)
        XCTAssertTrue(hasValue(reveal(element("climate.eco.eco-away", in: app), in: app), "Use Eco Away Targets"))
    }

    /// While Predictive Comfort is on, Current Prediction opens the detail.
    func testPredictiveComfortDetailPage() {
        let app = launch(open: "automation")
        reveal(element("climate.predictive.open", in: app), in: app).tap()
        XCTAssertTrue(heading("Predictive Comfort", in: app).appears(timeout: 5))
        XCTAssertEqual(element("climate.predictive.recommendation", in: app).label, "Recommendation: Pre-Cool")
        XCTAssertEqual(element("climate.metric.Comfort Band", in: app).label, "Comfort Band, 71.0°F - 74.0°F")
        reveal(element("climate.predictive.reasons", in: app), in: app)
        XCTAssertTrue(header("Why This Prediction", in: app).exists)
        XCTAssertTrue(app.staticTexts["Predicted indoor temperature is 75.1°F, above your 71.0°F - 74.0°F comfort band."].exists)
        let allowAway = reveal(element("climate.toggle.switch.demo_contact_2", in: app), in: app)
        XCTAssertEqual(allowAway.label, "Predictive Comfort While Away")
        XCTAssertEqual(value(allowAway), "0")
        back(app)
    }

    /// Predictive Comfort is a switch (`switch.turn_on` / `turn_off`); Current Prediction hides while it is off.
    func testPredictiveComfortSwitchOffOn() {
        let app = launch(open: "automation")
        let predictive = reveal(element("climate.predictive", in: app), in: app)
        XCTAssertEqual(predictive.label, "Predictive Comfort, On · Pre-Cool")
        XCTAssertEqual(value(predictive), "1")
        let power = reveal(element("climate.predictive", in: app), in: app)
        flip(power)
        waitForCall("switch.turn_off entity_id=switch.demo_contact_4", in: app)
        XCTAssertTrue(hasValue(power, "0"))
        XCTAssertFalse(element("climate.predictive.open", in: app).exists, "Current Prediction hides while off")
        flip(power)
        waitForCall("switch.turn_on entity_id=switch.demo_contact_4", in: app)
    }

    func testAutomationTabPassesAudit() throws { try audit(open: "automation") }

    func testPredictiveDetailPassesAudit() throws { try audit(open: "predictive") }
    func testEcoOptionPagePassesAudit() throws { try audit(open: "eco-critical") }
}
