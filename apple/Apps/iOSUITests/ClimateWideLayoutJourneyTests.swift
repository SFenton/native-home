import XCTest

/// The Climate audit that depends on width: the sheet's tabs and a detail page in iPad landscape. Its own class, named to sort last: it rotates the iPad.
@MainActor
final class ClimateWideLayoutJourneyTests: ClimateJourneyTestCase {
    // MARK: - Audits

    /// iPad landscape: the sheet tabs audit.
    func testSheetPassesAuditInIPadLandscapeAutomation() throws {
        guard FentonHomeApp.family == .iPad else { throw XCTSkip("iPad only") }
        XCUIDevice.shared.orientation = .landscapeLeft
        settleScreen()
        try audit(open: "automation")
    }

    /// iPad landscape: a detail page audits too.
    func testSheetPassesAuditInIPadLandscapeLivingRoom() throws {
        guard FentonHomeApp.family == .iPad else { throw XCTSkip("iPad only") }
        XCUIDevice.shared.orientation = .landscapeLeft
        settleScreen()
        try audit(open: "room:living_room")
    }
}
