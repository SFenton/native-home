import XCTest

/// Screenshots of the Climate page, hub picker, each sheet tab and every detail kind (a Capture plan class: no source rule selects it).
@MainActor
final class ClimateCaptureJourneyTests: ClimateJourneyTestCase {
    // MARK: - Screenshots

    /// A host capture named `name` already exists (a rerun after a simulator crash resumes where it stopped).
    private func captured(_ name: String) -> Bool {
        guard let folder = ProcessInfo.processInfo.environment["FENTON_CAPTURE_DIR"], !folder.isEmpty else { return false }
        return FileManager.default.fileExists(atPath: URL(fileURLWithPath: folder).appendingPathComponent("\(name).png").path)
    }

    /// Captures one view, named `climate-<name>-<orientation>` (iPad: portrait and landscape). `hubPicker` opens the hub's mode menu first.
    private func capture(_ name: String, open: String? = nil, scenario: String? = nil, hubPicker: Bool = false) {
        let orientations: [UIDeviceOrientation] = FentonHomeApp.family == .iPad ? [.portrait, .landscapeLeft] : [.unknown]
        for orientation in orientations {
            if orientation != .unknown { XCUIDevice.shared.orientation = orientation }
            let suffix = orientation == .landscapeLeft ? "landscape" : orientation == .portrait ? "portrait" : "current"
            guard !captured("climate-\(name)-\(suffix)") else { continue }
            let app = launch(open: open, scenario: scenario, clean: true)
            settleScreen()
            if hubPicker {
                element("climate.hub.mode", in: app).tap()
                XCTAssertTrue(menuItem("Cool", in: app).appears(timeout: 5))
                settleScreen()
            }
            keepScreenshot(app, "climate-\(name)-\(suffix)")
        }
        if FentonHomeApp.family == .iPad { XCUIDevice.shared.orientation = .portrait }
    }

    func testCaptureClimatePage() { capture("page") }

    func testCaptureClimateHubPicker() { capture("hub-picker", hubPicker: true) }

    func testCaptureClimateRooms() { capture("rooms", open: "rooms") }

    func testCaptureClimateAutomation() { capture("automation", open: "automation") }

    func testCaptureClimateTracking() { capture("tracking", open: "tracking") }

    func testCaptureClimateRoom() { capture("room", open: "room:living_room") }

    func testCaptureClimatePredictive() { capture("predictive", open: "predictive") }

    func testCaptureClimateEcoOption() { capture("eco-option", open: "eco-away") }

    func testCaptureClimateTrackingDetail() { capture("tracking-detail", open: "selected-rooms") }

    func testCaptureClimateAwayPage() { capture("page-away", scenario: "away") }
}
