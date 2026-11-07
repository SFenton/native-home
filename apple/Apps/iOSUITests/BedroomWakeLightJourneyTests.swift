import XCTest

/// The room's wake-light sheet: the alarm list and defaults, adding an alarm to a bed, stopping a wake, the linked bed alarm and the sheet audits.
@MainActor
final class BedroomWakeLightJourneyTests: BedroomJourneyTestCase {
    // MARK: - Wake light

    func testWakeAlarmToggleAndDefaults() {
        let app = launch(sheet: "wake-light")
        let toggle = element("wake.alarm.weekday.enabled", in: app)
        reveal(toggle, in: app)
        toggle.tap()
        expectCall(containing: "operation=upsert_alarm", in: app)
        selectTab("Defaults", in: app)
        tap("wake.defaults.ramp.15", in: app)
        expectCall(containing: "operation=update_defaults", in: app)
    }

    /// A new weekly alarm with "Add to Sam's Bed" creates the missing bed alarms.
    func testAddingAWakeAlarmToABed() {
        let app = launch(sheet: "wake-light")
        tap("wake.add", in: app)
        let bed = element("wake.editor.bed.right", in: app)
        reveal(bed, in: app)
        bed.switches.firstMatch.exists ? bed.switches.firstMatch.tap() : bed.tap()
        tap("wake.editor.save", in: app)
        expectCall(startingWith: "mqtt.publish", in: app)
        XCTAssertTrue(element("wake.add", in: app).appears(timeout: 5), "Back on the list")
    }

    func testStoppingAWakeEpisode() {
        let app = launch(sheet: "wake-light", scenario: "waking")
        tap("wake.stop", in: app)
        expectCall(containing: "operation=end_episode", in: app)
        XCTAssertTrue(element("wake.stop", in: app).disappears(timeout: 5))
    }

    func testLinkedAlarmOpensTheBed() {
        let app = launch(sheet: "wake-light")
        tap("wake.alarm.sleepypod-left.open", in: app)
        XCTAssertTrue(element("bed.alarms.add", in: app).appears(timeout: 10), "Bed sheet opens on Alarms")
    }

    // MARK: - Accessibility audits

    private func openWakeEditor(_ app: XCUIApplication) {
        tap("wake.add", in: app)
        XCTAssertTrue(element("wake.editor.save", in: app).appears(timeout: 10))
        settleScreen() // The growing name field settles after the push; auditing mid-layout sampled the wrong frames.
    }

    func testWakeAlarmsPassesAudit() throws { try audit(sheet: "wake-light", scenario: "waking") }
    func testWakeAlarmsPassesAuditInIPadLandscape() throws { try audit(sheet: "wake-light", scenario: "waking", pose: .iPadLandscape) }

    func testWakeDefaultsPassesAudit() throws { try audit(sheet: "wake-light", tab: "defaults") }
    func testWakeDefaultsPassesAuditInIPadLandscape() throws { try audit(sheet: "wake-light", tab: "defaults", pose: .iPadLandscape) }

    func testWakeEditorPassesAudit() throws { try audit(sheet: "wake-light", open: openWakeEditor) }
    func testWakeEditorPassesAuditInIPadLandscape() throws { try audit(sheet: "wake-light", pose: .iPadLandscape, open: openWakeEditor) }
}
