import XCTest

/// The bed side sheet's Alarms tab: adding and deleting an alarm, the day page and the alarm editor, and their audits.
@MainActor
final class BedroomAlarmsJourneyTests: BedroomJourneyTestCase {
    // MARK: - Alarms

    /// Adding a bed alarm links the wake light, then publishes the side's alarms.
    func testAddingABedAlarm() {
        let app = launch(sheet: expectations[.bedSecondSheetId], tab: "alarms")
        tap("bed.alarms.add", in: app)
        tap("bed.editor.day.sunday", in: app)
        tap("bed.editor.save", in: app)
        expectCall(startingWith: "mqtt.publish", in: app)
        XCTAssertTrue(element("bed.alarms.sunday", in: app).appears(timeout: 5))
    }

    func testDeletingABedAlarmAsksFirst() {
        let app = launch(sheet: expectations[.bedFirstSheetId], tab: "alarms")
        tap("bed.alarms.saturday", in: app)
        tap("bed.day.alarm.09:15", in: app)
        tap("bed.editor.delete", in: app)
        let confirm = app.buttons["Delete Alarm"].firstMatch
        XCTAssertTrue(confirm.appears(timeout: 5))
        confirm.tap()
        expectCall(startingWith: "mqtt.publish", in: app)
    }

    // MARK: - Accessibility audits

    private func openBedAlarmDay(_ app: XCUIApplication) {
        tap("bed.alarms.monday", in: app)
        XCTAssertTrue(element("bed.day.add", in: app).appears(timeout: 10))
        settleScreen()
    }

    private func openBedAlarmEditor(_ app: XCUIApplication) {
        openBedAlarmDay(app)
        tap("bed.day.alarm.06:30", in: app)
        XCTAssertTrue(element("bed.editor.save", in: app).appears(timeout: 10))
        settleScreen()
    }

    func testBedAlarmsPassesAudit() throws { try audit(sheet: expectations[.bedFirstSheetId], tab: "alarms") }
    func testBedAlarmsPassesAuditInIPadLandscape() throws { try audit(sheet: expectations[.bedFirstSheetId], tab: "alarms", pose: .iPadLandscape) }

    func testBedAlarmDayPassesAudit() throws { try audit(sheet: expectations[.bedFirstSheetId], tab: "alarms", open: openBedAlarmDay) }
    func testBedAlarmDayPassesAuditInIPadLandscape() throws { try audit(sheet: expectations[.bedFirstSheetId], tab: "alarms", pose: .iPadLandscape, open: openBedAlarmDay) }

    func testBedAlarmEditorPassesAudit() throws { try audit(sheet: expectations[.bedFirstSheetId], tab: "alarms", open: openBedAlarmEditor) }
    func testBedAlarmEditorPassesAuditInIPadLandscape() throws { try audit(sheet: expectations[.bedFirstSheetId], tab: "alarms", pose: .iPadLandscape, open: openBedAlarmEditor) }
}
