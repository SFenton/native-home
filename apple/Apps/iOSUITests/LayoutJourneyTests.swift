import XCTest

/// Orientation and split rules per device family (owner, 2026-10-10;
/// `.agents/design/apple/split-view.md`).
@MainActor
final class LayoutJourneyTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    /// Only iPad and iPhone rotate here; setting the orientation on an unfolded Duo hangs the runner (devices.md).
    override func tearDown() {
        MainActor.assumeIsolated {
            if FentonHomeApp.family != .iPhoneDuo { XCUIDevice.shared.orientation = .portrait }
        }
    }

    /// iPhone is locked to portrait.
    func testIPhoneStaysPortrait() throws {
        guard FentonHomeApp.family == .iPhone else { throw XCTSkip("iPhone only") }
        let app = FentonHomeApp.launchSignedOut()
        XCUIDevice.shared.orientation = .landscapeLeft
        settleScreen()
        let frame = app.windows.firstMatch.frame
        XCTAssertGreaterThan(frame.height, frame.width, "iPhone rotated to landscape")
    }

    /// iPad follows the device into landscape.
    func testIPadRotates() throws {
        guard FentonHomeApp.family == .iPad else { throw XCTSkip("iPad only") }
        let app = FentonHomeApp.launchSignedOut()
        XCUIDevice.shared.orientation = .landscapeLeft
        settleScreen()
        let frame = app.windows.firstMatch.frame
        XCTAssertGreaterThan(frame.width, frame.height, "iPad did not rotate")
    }

    private enum Pose { case upright, iPadLandscape }

    /// Audits the sign-in screen in one pose. Upright runs on every family (iPad is set to portrait first);
    /// `.iPadLandscape` is iPad only. iPhone Duo poses are set in Device Hub before the run (XCUIDevice cannot fold or
    /// rotate the Duo); the test audits whatever pose it is in.
    private func signInAudit(pose: Pose) throws {
        if pose == .iPadLandscape, FentonHomeApp.family != .iPad { throw XCTSkip("iPad only") }
        let app = FentonHomeApp.launchSignedOut()
        XCTAssertTrue(app.textFields["login.username"].appears(timeout: 10))
        if FentonHomeApp.family == .iPad {
            XCUIDevice.shared.orientation = pose == .upright ? .portrait : .landscapeLeft
            settleScreen()
        }
        try FentonHomeApp.audit(app)
    }

    /// Every family audits clean in the pose it launches in (iPad: portrait).
    func testSignInAuditsInSupportedOrientations() throws {
        try signInAudit(pose: .upright)
    }

    /// iPad audits clean in landscape too.
    func testSignInAuditsInSupportedOrientationsInIPadLandscape() throws {
        try signInAudit(pose: .iPadLandscape)
    }
}
