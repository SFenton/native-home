import XCTest

/// Screenshots of every Bedroom sheet, tab and pushed page (a Capture plan class: no source rule selects it).
@MainActor
final class BedroomCaptureJourneyTests: BedroomJourneyTestCase {
    // MARK: - Screenshots

    /// One test per sheet, tab and scenario, each in the current pose (iPad: both orientations), named
    /// `bedroom-<screen>-<orientation>`. One screen per test so a simulator crash retries one short run.
    func testCaptureBedroomTiles() { capture("tiles", sheet: nil, tab: nil, scenario: "default") }
    func testCaptureBedroomBedTemperature() { capture("bed-temperature", sheet: expectations[.bedFirstSheetId], tab: nil, scenario: "default") }
    func testCaptureBedroomBedRinging() { capture("bed-ringing", sheet: expectations[.bedFirstSheetId], tab: nil, scenario: "ringing") }
    func testCaptureBedroomBedSpecialModes() { capture("bed-special-modes", sheet: expectations[.bedSecondSheetId], tab: "special-modes", scenario: "hot-flash") }
    func testCaptureBedroomBedAlarms() { capture("bed-alarms", sheet: expectations[.bedFirstSheetId], tab: "alarms", scenario: "default") }
    func testCaptureBedroomBedStatus() { capture("bed-status", sheet: expectations[.bedFirstSheetId], tab: "status", scenario: "default") }
    func testCaptureBedroomSoloTripHome() { capture("bed-solo-trip-home", sheet: expectations[.bedFirstSheetId], tab: nil, scenario: "solo-trip") }
    func testCaptureBedroomSoloTripTraveler() { capture("bed-solo-trip-traveler", sheet: expectations[.bedSecondSheetId], tab: nil, scenario: "solo-trip") }
    func testCaptureBedroomBedUnavailable() { capture("bed-unavailable", sheet: expectations[.bedFirstSheetId], tab: nil, scenario: "unavailable") }
    func testCaptureBedroomWakeAlarms() { capture("wake-alarms", sheet: "wake-light", tab: nil, scenario: "default") }
    func testCaptureBedroomWakeActive() { capture("wake-active", sheet: "wake-light", tab: nil, scenario: "waking") }
    func testCaptureBedroomWakeDefaults() { capture("wake-defaults", sheet: "wake-light", tab: "defaults", scenario: "default") }

    // MARK: - Pushed pages and prompts

    /// The alarm day page, then the editor pushed from it: one flow, two shots.
    func testCaptureBedroomPushedBedAlarmDayAndEditor() {
        forEachCaptureOrientation { suffix in
            let app = launch(sheet: expectations[.bedFirstSheetId], tab: "alarms", clean: true)
            tap("bed.alarms.monday", in: app)
            settleScreen()
            keepScreenshot(app, "bedroom-bed-alarm-day-\(suffix)")
            tap("bed.day.alarm.06:30", in: app)
            settleScreen()
            keepScreenshot(app, "bedroom-bed-alarm-editor-\(suffix)")
        }
    }

    func testCaptureBedroomPushedBedScopePrompt() {
        forEachCaptureOrientation { suffix in
            let app = launch(sheet: expectations[.bedFirstSheetId], clean: true)
            tap("bed.stage.asleep.up", in: app)
            XCTAssertTrue(element("bed.scope.allNights", in: app).appears(timeout: 5))
            settleScreen()
            keepScreenshot(app, "bedroom-bed-scope-prompt-\(suffix)")
        }
    }

    func testCaptureBedroomPushedWakeEditor() {
        forEachCaptureOrientation { suffix in
            let app = launch(sheet: "wake-light", clean: true)
            tap("wake.add", in: app)
            settleScreen()
            keepScreenshot(app, "bedroom-wake-editor-\(suffix)")
        }
    }

    private func capture(_ name: String, sheet: String?, tab: String?, scenario: String) {
        forEachCaptureOrientation { suffix in
            let app = launch(sheet: sheet, tab: tab, scenario: scenario, clean: true)
            keepScreenshot(app, "bedroom-\(name)-\(suffix)")
        }
    }

    /// Runs `body` in each orientation the family captures (iPad: portrait, then landscape; others: the current
    /// pose) with its file-name suffix.
    private func forEachCaptureOrientation(_ body: (String) -> Void) {
        guard FentonHomeApp.family == .iPad else { return body("current") }
        for (orientation, suffix) in [(UIDeviceOrientation.portrait, "portrait"), (.landscapeLeft, "landscape")] {
            XCUIDevice.shared.orientation = orientation
            body(suffix)
        }
    }
}
