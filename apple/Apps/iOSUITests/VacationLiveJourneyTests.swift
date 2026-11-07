import XCTest

/// Settings → Vacation against the real server (signed in); the Live plan only. It skips without credentials.
@MainActor
final class VacationLiveJourneyTests: VacationJourneyTestCase {
    /// Signed in to the real server, Settings → Vacation opens whichever page the house's state calls for.
    /// Read-only: nothing is tapped on the page, so the house is never changed.
    func testSettingsOpensVacationOnTheLiveServer() throws {
        let app = try FentonHomeApp.launchSignedIn()
        // Settings is in the Account sheet behind the profile avatar (direction G).
        app.openAccountSettings()
        assertTarget("settings.vacation", in: app)
        element("settings.vacation", in: app).tap()
        let landed = ["vacation.chooser.vacationMode", "vacation.modeCard", "soloTrip.toggle"].map { element($0, in: app) }
        let deadline = Date().addingTimeInterval(10)
        while !landed.contains(where: \.exists), Date() < deadline { usleep(200_000) }
        XCTAssertTrue(landed.contains(where: \.exists), "Vacation did not open")
    }
}
