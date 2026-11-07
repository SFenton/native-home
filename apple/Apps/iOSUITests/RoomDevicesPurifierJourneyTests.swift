import XCTest

/// The air purifier sheet in the debug gallery: modes, auto sub-modes and manual speeds, and its accessibility audit.
@MainActor
final class RoomDevicesPurifierJourneyTests: RoomDevicesJourneyTestCase {

    /// A manual purifier's speed row sends the fan percentage.
    func testPurifierSpeedHigh() {
        let app = launch("purifier-manual", ready: "purifier.mode")
        XCTAssertTrue(segment("purifier.mode", "Manual", in: app).isSelected)
        XCTAssertTrue(segment("purifier.speed", "Medium", in: app).isSelected)
        XCTAssertFalse(element("purifier.auto", in: app).exists)
        segment("purifier.speed", "High", in: app).tap()
        expectCall("fan.set_percentage entity_id=\(expectations[.purifierFirstFan]) percentage=100", in: app)
    }

    /// Choosing Auto sends the fan mode; the auto sub-modes replace the speeds.
    func testPurifierModeAuto() {
        let app = launch("purifier-manual", ready: "purifier.mode")
        segment("purifier.mode", "Auto", in: app).tap()
        expectCall("select.select_option entity_id=\(expectations[.purifierFirstModeSelect]) option=Auto", in: app)
        XCTAssertTrue(segment("purifier.auto", "Quiet", in: app).appears(timeout: 5))
        XCTAssertFalse(element("purifier.speed", in: app).exists)
    }

    /// An auto purifier's Quiet sub-mode sends the auto-mode option and becomes selected (`purifier-auto` opens already in Auto).
    func testPurifierQuietAutoMode() {
        let app = launch("purifier-auto", ready: "purifier.mode")
        let quiet = segment("purifier.auto", "Quiet", in: app)
        XCTAssertTrue(quiet.appears(timeout: 5))
        quiet.tap()
        expectCall("select.select_option entity_id=\(expectations[.purifierFourthAutoModeSelect]) option=Quiet", in: app)
        XCTAssertTrue(quiet.wait(for: \.isSelected, toEqual: true, timeout: 5))
    }

    func testPurifierPassesAudit() throws { try audit("purifier-auto", ready: "purifier.mode", pose: .upright) }
    func testPurifierPassesAuditInIPadLandscape() throws { try audit("purifier-auto", ready: "purifier.mode", pose: .iPadLandscape) }
}
