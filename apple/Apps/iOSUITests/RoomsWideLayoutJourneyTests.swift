import XCTest

/// The room page layout that depends on width: the fan joins the two-column grid on iPad and keeps the full-width lead row on a phone. Its own
/// class, named to sort last: it rotates the iPad.
@MainActor
final class RoomsWideLayoutJourneyTests: RoomsJourneyTestCase {
    /// Regular width puts the fan in the two-column grid next to the vent; a phone keeps the full-width lead row.
    private func assertFanTileGrid(_ pose: Pose) throws {
        try enter(pose)
        let app = launch(room: "guest-bathroom", clean: true)
        let fan = element("room.card.Fan", in: app)
        let vent = element("room.card.Vent", in: app)
        reveal(fan, in: app)
        // The whole tiles: the Fan's body element stops where its discs start.
        let fanFrame = wholeTile("room.card.Fan", in: app), ventFrame = wholeTile("room.card.Vent", in: app)
        let window = app.windows.firstMatch.frame
        if FentonHomeApp.family == .iPad {
            XCTAssertLessThan(fanFrame.width, window.width * 0.6, "Not a full-width lead row on iPad (\(pose.rawValue))")
            XCTAssertEqual(fanFrame.minY, ventFrame.minY, accuracy: 2, "The vent shares the fan's row")
            XCTAssertLessThan(fanFrame.maxX, ventFrame.minX)
            XCTAssertEqual(fanFrame.height, ventFrame.height, accuracy: 1, "Equal heights in the grid")
            keepScreenshot(app, "fan-tile-grid-ipad-\(pose.captureSuffix)")
        } else if FentonHomeApp.family == .iPhone {
            XCTAssertGreaterThan(fanFrame.width, window.width * 0.85, "A phone keeps the full-width lead row")
        }
    }

    func testFanTileJoinsTheTwoColumnGridOnIPad() throws { try assertFanTileGrid(.upright) }

    func testFanTileJoinsTheTwoColumnGridOnIPadInIPadLandscape() throws { try assertFanTileGrid(.iPadLandscape) }
}
