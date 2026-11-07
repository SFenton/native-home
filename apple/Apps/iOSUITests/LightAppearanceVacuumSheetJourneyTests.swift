import XCTest

/// The vacuum sheet in the light appearance (`Features/Vacuums`): one audit test per section, so a change to one tab's files runs only its pass.
@MainActor
final class LightAppearanceVacuumSheetJourneyTests: LightAppearanceJourneyTestCase {
    /// The vacuum sheet on `tab`, pinned to the light appearance.
    private func auditVacuumSheetInLight(tab: String) throws {
        try auditLight("vacuum-\(tab)") { arguments in
            let app = self.gallery("vacuums", environment: [
                "FENTON_GALLERY_VACUUM": JourneyExpectations.gallery[.vacuumMainFloorMapId], "FENTON_GALLERY_TAB": tab,
                "FENTON_GALLERY_SCENARIO": "docked", "FENTON_GALLERY_CLEAN": "1",
            ], arguments: arguments)
            self.waitReady("vacuum.tabs", in: app, what: "vacuum sheet")
            XCTAssertTrue(app.buttons["Close"].firstMatch.wait(for: \.isHittable, toEqual: true, timeout: 10))
            return app
        }
    }

    /// The controls.
    func testVacuumControlsPassAuditInLight() throws { try auditVacuumSheetInLight(tab: "controls") }

    /// The rooms (selected rooms are the label's opposite on a white cell).
    func testVacuumRoomsPassAuditInLight() throws { try auditVacuumSheetInLight(tab: "zones") }
}
