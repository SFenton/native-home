import XCTest

/// Screenshots of every room device sheet (a Capture plan class: no source rule selects it). One test per sheet; run the
/// `room-devices-capture` suite for the set.
@MainActor
final class RoomDevicesCaptureJourneyTests: RoomDevicesJourneyTestCase {

    /// One sheet in the current pose (iPad: both orientations), named `device-<fixture>-<tab>-<orientation>`.
    private func captureDevice(_ device: String, ready: String, tab: String = "controls") {
        let orientations: [UIDeviceOrientation] = FentonHomeApp.family == .iPad ? [.portrait, .landscapeLeft] : [.unknown]
        for orientation in orientations {
            if orientation != .unknown { XCUIDevice.shared.orientation = orientation }
            let suffix = orientation == .landscapeLeft ? "landscape" : orientation == .portrait ? "portrait" : "current"
            let app = launch(device, ready: ready, tab: tab, clean: true)
            keepScreenshot(app, "device-\(device)-\(tab)-\(suffix)")
        }
    }

    func testCaptureDeviceFanGuest() { captureDevice("fan-guest", ready: "fan.power") }
    func testCaptureDeviceFanMaster() { captureDevice("fan-master", ready: "fan.power") }
    func testCaptureDevicePurifierAuto() { captureDevice("purifier-auto", ready: "purifier.mode") }
    func testCaptureDeviceGrill() { captureDevice("grill", ready: "grill.header") }
    func testCaptureDeviceHumidifierControls() { captureDevice("humidifier", ready: "humidifier.power") }
    func testCaptureDeviceHumidifierSchedules() { captureDevice("humidifier", ready: "humidifier.power", tab: "schedules") }
    func testCaptureDeviceHumidifierInfo() { captureDevice("humidifier", ready: "humidifier.power", tab: "info") }
    func testCaptureDeviceHumidifierFault() { captureDevice("humidifier-fault", ready: "humidifier.power") }
}
