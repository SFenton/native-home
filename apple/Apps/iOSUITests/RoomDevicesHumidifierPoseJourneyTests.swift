import XCTest

/// The humidifier sheet's layout per pose. Its own small class so a layout-sensitive edit to `HumidifierSheet` runs it on every device family without tripling the rest of the humidifier journeys.
@MainActor
final class RoomDevicesHumidifierPoseJourneyTests: RoomDevicesJourneyTestCase {

    /// Two columns only on iPad landscape and unfolded Duo landscape; iPhone and every portrait are one column.
    func testHumidifierLayout() throws {
        try enter(.upright)
        let app = launch("humidifier", ready: "humidifier.power")
        if FentonHomeApp.family == .iPad {
            XCTAssertTrue(element("humidifier.layout.singleColumn", in: app).exists, "iPad portrait is one column")
            return
        }
        let window = app.windows.firstMatch.frame
        let landscape = window.width > window.height
        if FentonHomeApp.family == .iPhone { XCTAssertFalse(landscape, "iPhone stays portrait") }
        let expected = FentonHomeApp.family == .iPhoneDuo && landscape && window.width >= 720
            ? "humidifier.layout.twoColumn" : "humidifier.layout.singleColumn"
        XCTAssertTrue(element(expected, in: app).exists, "\(FentonHomeApp.family) window \(window.size) expects \(expected)")
    }

    /// iPad landscape splits into two columns: the hero leads and the tab's controls trail.
    func testHumidifierLayoutInIPadLandscape() throws {
        try enter(.iPadLandscape)
        let app = launch("humidifier", ready: "humidifier.power")
        XCTAssertTrue(element("humidifier.layout.twoColumn", in: app).appears(timeout: 5), "iPad landscape splits")
        // The hero leads; the tab's controls trail (the section bar runs along the bottom of both).
        XCTAssertLessThan(element("humidifier.power", in: app).frame.maxX, app.segmentedControls["humidifier.mode"].frame.minX)
    }
}
