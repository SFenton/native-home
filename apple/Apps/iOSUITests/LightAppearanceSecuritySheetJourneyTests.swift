import XCTest

/// The Security System sheet in the light appearance, armed and triggered (`Features/Security/SecuritySystemSheet`).
@MainActor
final class LightAppearanceSecuritySheetJourneyTests: LightAppearanceJourneyTestCase {
    func testSecuritySystemSheetPassesAuditInLight() throws {
        try auditLight("security-system") { arguments in
            let app = self.gallery("security", arguments: arguments)
            XCTAssertTrue(app.buttons["security.chip.security"].appears(timeout: 30), "Security page did not appear")
            app.buttons["security.chip.security"].tap()
            XCTAssertTrue(app.navigationBars["Security System"].appears(timeout: 10), "Security system sheet did not open")
            XCTAssertTrue(app.buttons["Close"].firstMatch.wait(for: \.isHittable, toEqual: true, timeout: 10))
            settleScreen()
            return app
        }
    }

    func testTriggeredSecuritySheetPassesAuditInLight() throws {
        try auditLight("security-triggered") { arguments in
            let app = self.gallery("security", environment: ["FENTON_GALLERY_SCENARIO": "triggered"], arguments: arguments)
            XCTAssertTrue(app.buttons["security.chip.security"].appears(timeout: 30), "Security page did not appear")
            app.buttons["security.chip.security"].tap()
            XCTAssertTrue(app.navigationBars["Security System"].appears(timeout: 10), "Security system sheet did not open")
            XCTAssertTrue(app.buttons["Close"].firstMatch.wait(for: \.isHittable, toEqual: true, timeout: 10))
            settleScreen()
            return app
        }
    }
}
