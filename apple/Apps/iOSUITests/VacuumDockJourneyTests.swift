import XCTest

/// The Dock section (the sheet's "more" tab): the dock action tiles and scripts, the washing state, the cleaning report and the audits.
@MainActor
final class VacuumDockJourneyTests: VacuumJourneyTestCase {
    /// The Main Floor dock: Clean Mop Dock sends its script.
    func testVacuumDockCleanDock() {
        let app = launch(Self.mainFloor, tab: "more")
        let dock = app.buttons["vacuum.action.cleanDock"]
        XCTAssertTrue(dock.appears(timeout: 10))
        reveal(dock, in: app)
        dock.tap()
        if app.alerts.firstMatch.appears(timeout: 2) { app.alerts.firstMatch.buttons.element(boundBy: 1).tap() }
        expectCall(expectations[.vacuumMainFloorDockCleanScript], in: app)
    }

    /// Dock commands are action tiles with their explanation as a footer under the tile.
    func testVacuumDockTilesHaveFooters() {
        let app = launch(Self.mainFloor, tab: "more")
        for id in ["cleanDock", "dryMops", "emptyBin"] {
            let tile = app.buttons["vacuum.action.\(id)"]
            XCTAssertTrue(tile.appears(timeout: 10), "No \(id) tile")
            reveal(tile, in: app)
            assertTarget(tile)
        }
        XCTAssertTrue(app.staticTexts["Start drying the attached mop pads."].firstMatch.exists, "The explanation is a footer under the tile")
    }

    /// Washing turns Clean Mop Dock into Stop Dock Clean; the other commands wait and the Dock status tile reads Washing.
    func testVacuumDockWashingShowsStop() {
        let washing = launch(Self.mainFloor, tab: "more", scenario: "dockWash")
        let stop = washing.buttons["vacuum.action.stopDockClean"]
        XCTAssertTrue(stop.appears(timeout: 10), "Washing shows Stop Dock Clean")
        XCTAssertEqual(stop.label, "Stop Dock Clean")
        XCTAssertFalse(washing.buttons["vacuum.action.cleanDock"].exists)
        XCTAssertFalse(washing.buttons["vacuum.action.dryMops"].exists, "A washing dock is busy: only the active command shows")
        XCTAssertEqual(element("vacuum.status.dock", in: washing).value as? String, "Washing")
    }

    /// The cleaning report on Controls opens room details.
    func testVacuumDockReportOutcome() {
        let app = launch(Self.mainFloor)
        let report = element("vacuum.report", in: app)
        reveal(report, in: app)
        report.tap()
        XCTAssertTrue(element("vacuum.outcome.living_room", in: app).appears(timeout: 10))
    }

    func testMorePassesAudit() throws { try audit(Self.mainFloor, tab: "more") }
    func testMorePassesAuditInIPadLandscape() throws { try audit(Self.mainFloor, tab: "more", pose: .iPadLandscape) }

    func testDockWashingPassesAudit() throws { try audit(Self.mainFloor, tab: "more", scenario: "dockWash") }
    func testDockWashingPassesAuditInIPadLandscape() throws { try audit(Self.mainFloor, tab: "more", scenario: "dockWash", pose: .iPadLandscape) }
}
