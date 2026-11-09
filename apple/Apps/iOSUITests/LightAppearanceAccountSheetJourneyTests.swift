import XCTest

/// The Account sheet, and Settings pushed inside it, in the light appearance (signed in, Live; `Features/Settings/Profile`).
@MainActor
final class LightAppearanceAccountSheetJourneyTests: LightAppearanceJourneyTestCase {
    /// The Account sheet, and Settings pushed inside it, in light.
    func testAccountSheetPassesAuditInLight() throws {
        func open(_ arguments: [String]) throws -> XCUIApplication {
            let app = try FentonHomeApp.launchSignedIn(arguments: arguments, environment: ["FENTON_APPEARANCE": "light"])
            app.openAccountSheet()
            settleScreen()
            return app
        }
        let app = try open([])
        assertSheet(app, isLight: true, "account")
        keepScreenshot(app, "light-account-\(layout)")
        try FentonHomeApp.audit(app) { try open(FentonHomeApp.ax5) }
    }
}
