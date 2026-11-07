import XCTest

/// The Vacuums page splits only where allowed (unfolded Duo landscape, iPad landscape). Its own class, named to sort after every other
/// Vacuum class: on the Duo the runner has restarted during this test's tear-down, and a restart returns the Duo to folded.
@MainActor
final class VacuumSplitPoseJourneyTests: VacuumJourneyTestCase {
    /// Splits only where allowed: unfolded Duo landscape and iPad landscape. Named to sort last: on the Duo the
    /// runner has restarted during this test's tear-down (folded and unfolded landscape, 2026-10-11), and a restart
    /// returns the Duo to folded, which would put every later test in the wrong pose.
    func testSplitFollowsThePose() {
        if FentonHomeApp.family == .iPad { XCUIDevice.shared.orientation = .landscapeLeft }
        let app = launch()
        let split = element("vacuums.layout.split", in: app).exists
        let window = app.windows.firstMatch.frame
        switch FentonHomeApp.family {
        case .iPad: XCTAssertTrue(split, "iPad landscape splits")
        case .iPhone: XCTAssertFalse(split, "iPhone never splits")
        case .iPhoneDuo: XCTAssertEqual(split, window.width > window.height && window.width > 700, "Duo window \(window.size)")
        }
    }
}
