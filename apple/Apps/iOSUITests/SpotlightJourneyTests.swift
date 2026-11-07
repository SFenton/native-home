import XCTest

/// A tapped Spotlight result opens S+H on its page (`.agents/platforms/apple/app-name.md`).
///
/// A journey cannot tap a result in the system's search, so the debug app takes `FENTON_OPEN_SPOTLIGHT=<item id>` and
/// hands the same `NSUserActivity` (`CSSearchableItemActionType`) to the same handler the system would. Runs on iPhone,
/// the folded Duo and iPad, which reach a section through the tab bar, the vertical bar or the flyout.
@MainActor
final class SpotlightJourneyTests: JourneyTestCase {
    /// Launches signed in with a long-lived token (never saved), asking the app to open `item` as Spotlight would.
    private func launch(opening item: String) throws -> XCUIApplication {
        guard let token = ProcessInfo.processInfo.environment["FENTON_HASS_TOKEN"], !token.isEmpty else {
            throw XCTSkip("Set TEST_RUNNER_FENTON_HASS_TOKEN to run the Spotlight journeys")
        }
        let app = FentonHomeApp.makeApp()
        app.launchEnvironment["FENTON_UITEST_RESET"] = "1"
        app.launchEnvironment["FENTON_HASS_TOKEN"] = token
        app.launchEnvironment["FENTON_OPEN_SPOTLIGHT"] = item
        if let server = ProcessInfo.processInfo.environment["FENTON_HASS_SERVER"] {
            app.launchEnvironment["FENTON_HASS_SERVER"] = server
        }
        app.launch()
        return app
    }

    /// A root section result lands on that section's page.
    private func expectSection(_ item: String, title: String) throws {
        let app = try launch(opening: item)
        XCTAssertTrue(app.navigationBars[title].appears(timeout: 30), "\(item) did not open \(title)")
        keepScreenshot(app, "spotlight-\(item)-\(layout)")
    }

    func testSpotlightSectionSecurityOpens() throws { try expectSection("section.security", title: "Security") }
    func testSpotlightSectionClimateOpens() throws { try expectSection("section.climate", title: "Climate") }
    func testSpotlightSectionChoresOpens() throws { try expectSection("section.chores", title: "Chores") }
    func testSpotlightSectionSettingsOpens() throws { try expectSection("section.settings", title: "Settings") }

    /// A room result pushes the room's page over Home.
    func testRoomResultOpensTheRoomPage() throws {
        let app = try launch(opening: "room.kitchen")
        XCTAssertTrue(app.navigationBars["Kitchen"].appears(timeout: 30), "room.kitchen did not open Kitchen")
        keepScreenshot(app, "spotlight-room-\(layout)")
    }

    /// A result from an older version of the app opens nothing and leaves Home as it was.
    func testUnknownResultLeavesHome() throws {
        let app = try launch(opening: "section.removed")
        XCTAssertTrue(app.buttons["home.chip.lights"].appears(timeout: 30), "Home did not appear")
    }
}
