import XCTest

/// The lights sheets in the light appearance (selected by `BrightnessTile` and `Features/CustomLights`): Home's Lights
/// chip sheet (signed in, Live) and every section of the Direction G gallery sheet (tiles, families, app tile, inset list).
@MainActor
final class LightAppearanceLightsJourneyTests: LightAppearanceJourneyTestCase {
    /// One section of the gallery sheet in light.
    private func auditSection(_ section: String) throws {
        try auditLight("gallery-\(section.lowercased())") { arguments in
            let app = self.gallery("direction-g", arguments: ["-directionGSheet", "open", "-directionGSheetSection", section] + arguments)
            self.waitReady("g.sheet.tabs", in: app, what: "gallery sheet")
            return app
        }
    }

    /// Filled, off, lit, error, tinted and washed tiles.
    func testGallerySheetControlsPassesAuditInLight() throws { try auditSection("Controls") }

    /// Every family off.
    func testGallerySheetFamiliesPassesAuditInLight() throws { try auditSection("Families") }

    /// The app tile.
    func testGallerySheetAppsPassesAuditInLight() throws { try auditSection("Apps") }

    /// An inset list.
    func testGallerySheetSettingsPassesAuditInLight() throws { try auditSection("Settings") }

    /// Home's Lights chip sheet (the room overview: rows, a light tile slab and a group), in light.
    func testLightsOverviewSheetPassesAuditInLight() throws {
        func open(_ arguments: [String]) throws -> XCUIApplication {
            let app = try FentonHomeApp.launchSignedIn(arguments: arguments, environment: ["FENTON_APPEARANCE": "light"])
            app.buttons["home.chip.lights"].tap()
            XCTAssertTrue(app.buttons["Close"].appears(timeout: 5))
            settleScreen()
            return app
        }
        let app = try open([])
        assertSheet(app, isLight: true, "lights overview")
        keepScreenshot(app, "light-lights-overview-\(layout)")
        try FentonHomeApp.audit(app) { try open(FentonHomeApp.ax5) }
    }
}
