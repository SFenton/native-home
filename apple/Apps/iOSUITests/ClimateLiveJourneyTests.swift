import XCTest

/// The signed-in Climate tab on the real house, read-only (the Live plan). Nothing that changes a setting is tapped.
@MainActor
final class ClimateLiveJourneyTests: ClimateJourneyTestCase {
    /// Signed in against the house: the Climate tab shows the Whole Home dial and the hub row. Nothing is tapped.
    func testLiveClimatePageReads() throws {
        let app = try FentonHomeApp.launchSignedIn()
        openClimateTab(app)
        XCTAssertTrue(element("thermostatDial.readout", in: app).appears(timeout: 15))
        XCTAssertTrue(element("thermostatDial.readout", in: app).label.hasPrefix("Whole Home thermostat"))
        XCTAssertTrue(hubRow(in: app).exists)
    }

    /// Signed in against the house: the live Climate page passes the audit. Nothing is tapped that changes a setting.
    func testLiveClimatePageAudit() throws {
        let app = try FentonHomeApp.launchSignedIn()
        openClimateTab(app)
        // The AX5 relaunch confirms iPad's "partially unsupported" Dynamic Type report (a known false positive).
        try FentonHomeApp.audit(app) {
            let large = try FentonHomeApp.launchSignedIn(arguments: FentonHomeApp.ax5)
            self.openClimateTab(large)
            settleScreen()
            return large
        }
    }

    /// Signed in against the house: the Rooms sheet reads the Office's temperature.
    func testLiveClimateRoomsSheetReadsOffice() throws {
        let app = try FentonHomeApp.launchSignedIn()
        openClimateTab(app)
        reveal(element("climate.entry.rooms", in: app), in: app).tap()
        XCTAssertTrue(element("climate.sheet.rooms", in: app).appears(timeout: 5))
        XCTAssertTrue(value(reveal(element("climate.room.office", in: app), in: app)).contains("°F\n"))
    }

    private func openClimateTab(_ app: XCUIApplication) {
        // Regular width (iPad, unfolded Duo) navigates through the flyout; compact width through the tab bar.
        if app.buttons["nav.open"].appears(timeout: 3) {
            app.buttons["nav.open"].tap()
            XCTAssertTrue(app.buttons["nav.climate"].appears(timeout: 3), "Flyout did not open")
            app.buttons["nav.climate"].tap()
        } else {
            let tab = app.barItem("Climate")
            if tab.appears(timeout: 5) { tab.tap() } else { app.buttons["Climate"].firstMatch.tap() }
        }
        XCTAssertTrue(element("climate.wholeHome", in: app).appears(timeout: 15), "Climate tab did not open")
    }
}
