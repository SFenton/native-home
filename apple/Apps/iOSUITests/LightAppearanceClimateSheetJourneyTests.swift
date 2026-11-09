import XCTest

/// The Thermostat · Advanced Controls sheet in the light appearance (`Features/Climate/ClimateSheet`).
@MainActor
final class LightAppearanceClimateSheetJourneyTests: LightAppearanceJourneyTestCase {
    private func auditClimate(_ open: String) throws {
        try auditLight("climate-\(open.replacingOccurrences(of: ":", with: "-"))") { arguments in
            let app = self.gallery("climate", environment: ["FENTON_GALLERY_CLIMATE_OPEN": open, "FENTON_GALLERY_CLEAN": "1"],
                                   arguments: arguments)
            XCTAssertTrue(app.buttons["Close"].appears(timeout: 15), "Climate sheet did not open")
            settleScreen()
            return app
        }
    }

    /// Thermostat · Advanced Controls: the rooms list.
    func testClimateSheetRoomsPassesAuditInLight() throws { try auditClimate("rooms") }

    /// Thermostat · Advanced Controls: the automation form.
    func testClimateSheetAutomationPassesAuditInLight() throws { try auditClimate("automation") }

    /// Thermostat · Advanced Controls: a room's dial.
    func testClimateSheetMasterBedroomPassesAuditInLight() throws { try auditClimate("room:bedroom_1") }
}
