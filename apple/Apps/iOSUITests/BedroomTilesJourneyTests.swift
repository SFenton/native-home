import XCTest

/// The Bedroom 1 room tiles in the debug gallery: the wake-light and bed-side tiles, the sheet a bed tile opens and the tiles audit.
@MainActor
final class BedroomTilesJourneyTests: BedroomJourneyTestCase {
    // MARK: - Tiles

    func testTilesOpenTheirSheets() {
        let app = launch()
        // One snapshot per tile for label, value and size instead of a request per property.
        let wake = element("room.card.Wake-Light Alarms", in: app)
        let wakeFacts = try? wake.snapshot()
        XCTAssertEqual(wakeFacts?.label, "Wake-Light Alarms")
        // The room page's own card (one tile path): it reads the wake-light status sensor, not the controller's "Next Alarm" line.
        XCTAssertFalse((wakeFacts?.value as? String ?? "").isEmpty, "\(String(describing: wakeFacts?.value))")
        let bed = element("room.card.\(expectations[.bedFirstTitle])", in: app)
        let bedFacts = try? bed.snapshot()
        XCTAssertEqual(bedFacts?.value as? String, "Heating • +3")
        XCTAssertGreaterThanOrEqual(bedFacts?.frame.width ?? 0, 43, bedFacts?.label ?? expectations[.bedFirstTitle])
        XCTAssertGreaterThanOrEqual(bedFacts?.frame.height ?? 0, 43, bedFacts?.label ?? expectations[.bedFirstTitle])
        bed.tap()
        XCTAssertTrue(element("bed.power", in: app).appears(timeout: 10))
    }

    // MARK: - Accessibility audits

    func testTilesPassAudit() throws { try audit(sheet: nil) }
    func testTilesPassAuditInIPadLandscape() throws { try audit(sheet: nil, pose: .iPadLandscape) }
}
