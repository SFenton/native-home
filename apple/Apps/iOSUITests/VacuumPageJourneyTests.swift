import XCTest

/// The Vacuums page: robot tiles, Auto-Clean switches, and the page and unavailable-page audits (`Features/Vacuums/VacuumsScreen`).
@MainActor
final class VacuumPageJourneyTests: VacuumJourneyTestCase {
    /// Tiles name each robot and its state, under a summary line.
    func testVacuumsPageTileAndSummary() {
        let app = launch()
        let tile = element("vacuums.tile.\(Self.mainFloor)", in: app)
        XCTAssertTrue(tile.label.contains("Main Floor"), tile.label)
        assertTarget(tile)
        XCTAssertTrue(element("vacuums.summary", in: app).exists, "The summary line under the large title")
    }

    /// Tiles carry Start / Pause and Dock discs beside the chevron (rollout lane M, item 31).
    func testVacuumsPageTileCarriesStartAndDockDiscs() {
        let app = launch()
        let start = element("vacuums.tile.\(Self.mainFloor).action.start_pause", in: app)
        let dock = element("vacuums.tile.\(Self.mainFloor).action.dock", in: app)
        XCTAssertTrue(start.exists && dock.exists, "Both discs are always there")
        assertTarget(start)
        assertTarget(dock)
        XCTAssertFalse(dock.isEnabled, "A docked robot has nowhere to go: Dock dims in place")
    }

    /// Auto-Clean rows are switches that send their service.
    func testVacuumsPageAutoCleanSwitch() {
        let app = launch()
        let row = element("vacuums.autoClean.\(expectations[.vacuumMainFloorAutoCleanPause])", in: app)
        reveal(row, in: app)
        // A list-row switch (direction G): the identifier is on the Toggle; iOS 18 and later nest the switch itself.
        let pause = row.switches.firstMatch.exists ? row.switches.firstMatch : row
        XCTAssertEqual(pause.value as? String, "1", "Main Floor Auto-Clean is enabled")
        pause.tap()
        expectCall("switch.turn_on entity_id=\(expectations[.vacuumMainFloorAutoCleanPause])", in: app)
        let paused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "0"), object: pause)
        XCTAssertEqual(XCTWaiter().wait(for: [paused], timeout: 10), .completed, "Auto-Clean switch value is \(pause.value ?? "nil")")
    }

    /// Tapping a robot opens its sheet.
    func testVacuumsPageTileOpensPage() {
        let app = launch()
        let tile = element("vacuums.tile.\(Self.mainFloor)", in: app)
        reveal(tile, in: app, down: false)
        tile.tap()
        XCTAssertTrue(element("vacuum.tabs", in: app).appears(timeout: 10))
        XCTAssertTrue(app.navigationBars["Main Floor Robot Vacuum"].exists)
    }

    func testPagePassesAudit() throws { try audit(nil) }
    func testPagePassesAuditInIPadLandscape() throws { try audit(nil, pose: .iPadLandscape) }

    /// Robots that stopped answering: their tiles show Unavailable (the live Media room did in the 2026-10-15 sweep).
    func testUnavailablePagePassesAudit() throws { try audit(nil, scenario: "unavailable") }
    func testUnavailablePagePassesAuditInIPadLandscape() throws { try audit(nil, scenario: "unavailable", pose: .iPadLandscape) }
}
