import HassCore
import UIKit
import XCTest
@testable import HassUI

/// The Music Room remote's Hue Sync brightness slider: it shows the entity's value, snaps to the step, sends one `number.set_value`
/// when the finger lifts, and VoiceOver can adjust it by whole steps.
@MainActor
final class UKHostedHueSyncBrightnessTests: DemoHouseTestCase {
    private func open() throws -> (UIViewController, LoggingResponder, UIWindow, UKRemoteSlider) {
        let log = LoggingResponder()
        let store = MediaRemoteFixtures.store()
        let context = UKGalleryChrome.context(store: store, caller: log)
        let sheet = UKMediaRemoteSheet.make(config: MediaRemotes.sourceSelectRemote, store: store, caller: log, imageServer: nil, initialTab: .hueSync, context: context)
        let window = HostedPage.show(sheet, size: HostedDriver.tall)
        FeatureHost.settle(0.6)
        let slider = try XCTUnwrap(HostedPage.descendants(of: sheet.view).first { $0.accessibilityIdentifier == "remote.hue.brightness" } as? UKRemoteSlider,
                                   "the light-sync tab has a brightness slider")
        return (sheet, log, window, slider)
    }

    func testBrightnessShowsTheEntityValueAndSendsOneCommandWhenTheFingerLifts() throws {
        let (_, log, window, slider) = try open()
        defer { window.isHidden = true }
        XCTAssertEqual(slider.value, 50, accuracy: 0.5, "the slider starts at the sync box's brightness")
        XCTAssertEqual(slider.accessibilityValue, "50")

        slider.sendActions(for: .touchDown)
        slider.value = 72.4
        slider.sendActions(for: .valueChanged)
        XCTAssertEqual(slider.value, 72, accuracy: 0.01, "it snaps to whole steps")
        XCTAssertTrue(log.calls.isEmpty, "nothing is sent while the finger is down")
        slider.sendActions(for: .touchUpInside)
        XCTAssertTrue(HostedPage.until(3) { log.calls.contains("number.set_value") }, "lifting sends the new brightness; saw \(log.calls)")
        XCTAssertEqual(slider.accessibilityValue, "72")
    }

    func testVoiceOverAdjustsByOneStep() throws {
        let (_, log, window, slider) = try open()
        defer { window.isHidden = true }
        slider.accessibilityIncrement()
        XCTAssertEqual(slider.value, 51, accuracy: 0.01)
        slider.accessibilityDecrement()
        slider.accessibilityDecrement()
        XCTAssertEqual(slider.value, 49, accuracy: 0.01)
        XCTAssertTrue(HostedPage.until(4) { !log.calls.isEmpty }, "adjusting by VoiceOver commits the change")
    }
}
