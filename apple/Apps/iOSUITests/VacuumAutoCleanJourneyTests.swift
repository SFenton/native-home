import XCTest

/// The Auto-Clean section: check-disc selection tiles and the audit.
@MainActor
final class VacuumAutoCleanJourneyTests: VacuumJourneyTestCase {
    /// The first Auto-Clean tile, revealed.
    private func firstTile(in app: XCUIApplication) -> XCUIElement {
        let tile = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "vacuum.autoCleanRoom.")).firstMatch
        XCTAssertTrue(tile.appears(timeout: 10))
        reveal(tile, in: app)
        assertTarget(tile)
        return tile
    }

    /// Auto-Clean rooms are selection tiles with a check disc: checked means included.
    func testAutoCleanTilesRead() {
        let app = launch(Self.mainFloor, tab: "autoClean")
        let tile = firstTile(in: app)
        XCTAssertTrue(tile.label.hasSuffix("auto-clean"), tile.label)
        XCTAssertEqual(tile.value as? String, "Included")
        XCTAssertTrue(tile.isSelected, "Checked means included")
    }

    /// Tapping an included tile flips the entity and the tile reads Skipped.
    func testAutoCleanTilesToggle() {
        let app = launch(Self.mainFloor, tab: "autoClean")
        let tile = firstTile(in: app)
        let entity = tile.identifier.replacingOccurrences(of: "vacuum.autoCleanRoom.", with: "")
        tile.tap()
        expectCall("switch.turn_on entity_id=\(entity)", in: app)
        let skipped = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Skipped"), object: tile)
        XCTAssertEqual(XCTWaiter().wait(for: [skipped], timeout: 10), .completed, "Tile reads \(tile.value ?? "nil")")
        XCTAssertFalse(tile.isSelected)
    }

    func testAutoCleanPassesAudit() throws { try audit(Self.mainFloor, tab: "autoClean") }
    func testAutoCleanPassesAuditInIPadLandscape() throws { try audit(Self.mainFloor, tab: "autoClean", pose: .iPadLandscape) }
}
