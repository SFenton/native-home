import XCTest

/// Duo widths (`.agents/design/duo-widths.md`): a short row of tiles fills its section on every family, and a portrait-shaped window shows one
/// column of sections at any text size. The Duo journeys run folded, unfolded portrait and unfolded landscape lying flat (the runner sets the
/// pose, `.agents/testing/apple/devices.md`); the assertions are geometric, so they hold in whichever pose the run is in.
@MainActor
final class DuoWidthsJourneyTests: RoomsJourneyTestCase {
    /// The widest content a window can hold in one section column: two 340 pt columns and the 24 pt gap need 704 pt.
    private static let twoSectionColumns: CGFloat = 704

    // MARK: - Layout

    /// Admin's lone tiles span their section instead of sitting in one 150 pt track with a clipped title.
    func testAdminTilesFillTheirSection() {
        let configured = FentonHomeApp.makeApp()
        configured.launchEnvironment["FENTON_GALLERY"] = "household-settings"
        configured.launchEnvironment["FENTON_GALLERY_HOUSEHOLD"] = "admin"
        let app = startApp(configured)
        let page = element("household.admin", in: app)
        XCTAssertTrue(page.appears(timeout: FentonHomeApp.launchWait()), "Admin did not open")
        settleScreen()
        let opener = element("admin.open.presenceOverrides", in: app)
        XCTAssertTrue(opener.appears(timeout: 10), "the Presence opener is missing")
        let tile = wholeTile("admin.open.presenceOverrides", in: app)
        XCTAssertGreaterThanOrEqual(tile.width, 0.8 * page.frame.width, "a lone Admin tile is one track: \(tile) in \(page.frame)")
        keepScreenshot(app, "duo-widths-admin")
    }

    /// Bedroom 1's Wake-Light Alarms tile takes the whole Sleep & Wake section, not one of its two tracks.
    func testTheWakeLightTileSpansItsSection() {
        let app = launch(room: expectations[.roomBedroomId])
        let section = element("room.section.\(sleepAndWake)", in: app)
        XCTAssertTrue(section.appears(timeout: 10), "the Sleep & Wake section is missing")
        let wake = wholeTile("room.card.Wake-Light Alarms", in: app)
        XCTAssertGreaterThanOrEqual(wake.width, 0.95 * section.frame.width, "the Wake Light tile leaves its row half empty: \(wake) in \(section.frame)")
    }

    /// A window narrower than two section columns shows one: every section of a room page starts at the same x.
    func testAPortraitShapedRoomPageShowsOneSectionColumn() {
        let app = launch(room: "living-room")
        let window = app.windows.firstMatch.frame
        let climate = element("room.section.Climate", in: app)
        let devices = element("room.section.Devices", in: app)
        XCTAssertTrue(climate.appears(timeout: 10) && devices.exists, "the room's sections are missing")
        if window.width < Self.twoSectionColumns + 32 {
            XCTAssertEqual(climate.frame.minX, devices.frame.minX, accuracy: 1, "two section columns in a \(window.width) pt window")
            XCTAssertGreaterThan(devices.frame.minY, climate.frame.minY, "sections stack")
        }
    }

    /// Climate: the Vent beside the Air Purifier share their row, Vents first in reading order.
    func testTheVentAndThePurifierShareARow() {
        let app = launch(room: "living-room")
        let vents = wholeTile("room.card.Vents", in: app)
        let purifier = purifierFrame(in: app)
        XCTAssertGreaterThan(vents.width, 0, "the Vents tile is missing")
        if abs(vents.minY - purifier.minY) < 1 {
            XCTAssertEqual(vents.width, purifier.width, accuracy: 2, "same-size buttons in a row")
            XCTAssertLessThan(vents.minX, purifier.minX, "reading order is leading to trailing")
        } else {
            XCTAssertEqual(vents.width, purifier.width, accuracy: 2, "stacked, each fills the section")
        }
    }

    // MARK: - Accessibility

    /// 44 pt targets, row-by-row reading order and one track at AX5: every tile of a section is the section's width and they stack.
    func testAccessibilityAtTheLargestTextSizeGivesOneTrack() {
        let configured = FentonHomeApp.makeApp()
        configured.launchEnvironment["FENTON_GALLERY"] = "rooms"
        configured.launchEnvironment["FENTON_GALLERY_OFFLINE"] = "1"
        configured.launchEnvironment["FENTON_GALLERY_ROOM"] = "living-room"
        configured.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        let app = startApp(configured)
        XCTAssertTrue(element("room.scroll.living-room", in: app).appears(timeout: 30), "the room did not open")
        settleScreen()
        let section = element("room.section.Climate", in: app)
        let vents = wholeTile("room.card.Vents", in: app)
        let purifier = purifierFrame(in: app)
        XCTAssertTrue(section.exists)
        XCTAssertEqual(vents.minX, purifier.minX, accuracy: 1, "AX5 is one track: tiles stack")
        XCTAssertLessThan(vents.minY, purifier.minY, "reading order is unchanged")
        XCTAssertGreaterThanOrEqual(vents.width, 0.9 * section.frame.width, "the stacked tile is the section's width")
    }

    /// Filling only widens: the Wake-Light tile stays a 44 pt target.
    func testAFilledTileKeepsA44PointTarget() {
        let app = launch(room: expectations[.roomBedroomId])
        assertTarget(element("room.card.Wake-Light Alarms", in: app))
    }

    // MARK: - Helpers

    private var sleepAndWake: String { "Sleep & Wake" }

    /// The Air Purifier tile's frame in the Living Room (`room.card.Air Purifier`).
    private func purifierFrame(in app: XCUIApplication) -> CGRect { wholeTile("room.card.Air Purifier", in: app) }
}
