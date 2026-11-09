import XCTest

/// The bed sheet in the light appearance (`Features/Bedroom/BedSideSheet`).
@MainActor
final class LightAppearanceBedSheetJourneyTests: LightAppearanceJourneyTestCase {
    /// The bed sheet (Alex's side) on one of its tabs.
    private func auditBed(_ tab: String) throws {
        try auditLight("bed-\(tab)") { arguments in
            let app = self.gallery("bedroom", environment: [
                "FENTON_GALLERY_SCENARIO": "default", "FENTON_GALLERY_SHEET": self.expectations[.bedFirstSheetId], "FENTON_GALLERY_TAB": tab,
                "FENTON_GALLERY_CLEAN": "1",
            ], arguments: arguments)
            self.waitReady("bed.hint", in: app, what: "bed sheet")
            return app
        }
    }

    /// The bed sheet's controls tab, with its dial.
    func testBedSheetControlsPassesAuditInLight() throws { try auditBed("controls") }

    /// The bed sheet's Special Modes tab.
    func testBedSheetSpecialModesPassesAuditInLight() throws { try auditBed("special-modes") }
}
