import XCTest

/// The grill sheet in the debug gallery: read-only sensors, the explicit-service switches and its accessibility audit.
@MainActor
final class RoomDevicesGrillJourneyTests: RoomDevicesJourneyTestCase {

    /// Sensors are read-only; the switches toggle with explicit services.
    func testGrillCards() {
        let app = launch("grill", ready: "grill.Keep Warm")
        XCTAssertEqual(element("grill.Probe 1", in: app).value as? String, "165 °F")
        XCTAssertFalse(element("grill.Probe 1", in: app).elementType == .button, "Sensors are not buttons")
        let keepWarm = element("grill.Keep Warm", in: app)
        XCTAssertEqual(keepWarm.value as? String, "Off")
        keepWarm.tap()
        expectCall("switch.turn_on entity_id=\(expectations[.grillKeepWarm])", in: app)
        let on = NSPredicate(format: "value == %@", "On")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: on, object: keepWarm)], timeout: 5), .completed)
    }

    // The header, not a card: at AX5 the cards start below the folded iPhone Duo's fold.
    func testGrillPassesAudit() throws { try audit("grill", ready: "grill.header", pose: .upright) }
    func testGrillPassesAuditInIPadLandscape() throws { try audit("grill", ready: "grill.header", pose: .iPadLandscape) }
}
