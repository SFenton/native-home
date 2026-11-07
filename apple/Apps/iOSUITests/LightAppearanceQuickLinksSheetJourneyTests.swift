import XCTest

/// The Quick Links sheet in the light appearance (`Features/Rooms/QuickLinksSheet`).
@MainActor
final class LightAppearanceQuickLinksSheetJourneyTests: LightAppearanceJourneyTestCase {
    /// Quick Links: the room grid tiles in a sheet.
    func testQuickLinksPassesAuditInLight() throws {
        try auditLight("quick-links") { arguments in
            let app = self.gallery("rooms", environment: [
                "FENTON_GALLERY_OFFLINE": "1", "FENTON_GALLERY_QUICK_LINKS": "1", "FENTON_GALLERY_CLEAN": "1",
            ], arguments: arguments)
            self.waitReady("quickLinks.rooms", in: app, what: "Quick Links")
            return app
        }
    }
}
