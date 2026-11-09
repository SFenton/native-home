import XCTest

/// The Info section: its audit and the section at the largest text size.
@MainActor
final class VacuumInfoJourneyTests: VacuumJourneyTestCase {
    func testInfoPassesAudit() throws { try audit(Self.musicRoom, tab: "info") }
    func testInfoPassesAuditInIPadLandscape() throws { try audit(Self.musicRoom, tab: "info", pose: .iPadLandscape) }

    /// At AX5 the Info section opens from the section bar and its rows stay reachable by scrolling.
    func testLargestTextKeepsInfoReachable() {
        let app = launch(Self.mainFloor, arguments: FentonHomeApp.ax5)
        tab("Info", in: app)
        reveal(app.staticTexts["Main Filter"].firstMatch, in: app)
    }
}
