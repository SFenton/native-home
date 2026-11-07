import XCTest

/// Screenshots of the Vacuums page and every sheet section (a Capture plan class: no source rule selects it). One test per screen; each
/// loops the iPad's two orientations (phones and the Duo have one pose).
@MainActor
final class VacuumCaptureJourneyTests: VacuumJourneyTestCase {
    func testCaptureVacuumPage() { capture(nil, "controls", "docked", "page") }
    func testCaptureVacuumControls() { capture(Self.mainFloor, "controls", "docked", "controls") }
    func testCaptureVacuumRooms() { capture(Self.mainFloor, "zones", "docked", "rooms") }
    func testCaptureVacuumAutoClean() { capture(Self.mainFloor, "autoClean", "docked", "autoclean") }
    func testCaptureVacuumDock() { capture(Self.mainFloor, "more", "docked", "dock") }
    func testCaptureVacuumInfo() { capture(Self.mainFloor, "info", "docked", "info") }
    func testCaptureVacuumCleaning() { capture(Self.mainFloor, "controls", "cleaning", "cleaning") }
    func testCaptureVacuumError() { capture(Self.mainFloor, "controls", "error", "error") }
    func testCaptureVacuumReported() { capture(Self.musicRoom, "controls", "unavailable", "reported") }

    /// One screen in the current pose (iPad: both orientations), named `vacuums-<name>-<orientation>`.
    private func capture(_ vacuum: String?, _ tab: String, _ scenario: String, _ name: String) {
        let orientations: [UIDeviceOrientation] = FentonHomeApp.family == .iPad ? [.portrait, .landscapeLeft] : [.unknown]
        for orientation in orientations {
            if orientation != .unknown { XCUIDevice.shared.orientation = orientation }
            let suffix = orientation == .landscapeLeft ? "landscape" : orientation == .portrait ? "portrait" : "current"
            let app = launch(vacuum, tab: tab, scenario: scenario, clean: true)
            if vacuum != nil && tab != "controls" { scrollToTabContent(in: app) }
            keepScreenshot(FentonHomeApp.target(), "vacuums-\(name)-\(suffix)")
        }
    }
}
