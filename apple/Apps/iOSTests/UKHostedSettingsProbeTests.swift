import HassCore
import UIKit
import XCTest
@testable import HassUI

/// The Settings page's debug probes (`FENTON_DEBUG_SETTINGS_PANE`, `FENTON_DEBUG_SETTINGS_OPEN`): a host script opens a topic or a
/// sheet without a tap, the way a person's tap would.
@MainActor
final class UKHostedSettingsProbeTests: DemoHouseTestCase {
    override func tearDown() {
        unsetenv("FENTON_DEBUG_SETTINGS_PANE")
        unsetenv("FENTON_DEBUG_SETTINGS_OPEN")
        super.tearDown()
    }

    func testThePaneProbeOpensTheNamedTopicLikeATap() throws {
        setenv("FENTON_DEBUG_SETTINGS_PANE", "vacation", 1)
        let context = UKGalleryChrome.context()
        let page = UKSettingsViewController(context: context)
        let window = HostedPage.show(UKGalleryChrome.wrap(page, context: context))
        defer { window.isHidden = true }
        XCTAssertTrue(HostedPage.until(8) { FeatureHost.view("settings.gallery.pushed", in: window) != nil }, "the Vacation topic is pushed after the probe's delay")
        XCTAssertTrue(HostedPage.labels(in: window).contains { $0.contains("vacation") })
    }

    func testTheOpenProbeShowsTheAppIconSheet() throws {
        setenv("FENTON_DEBUG_SETTINGS_OPEN", "appIcon", 1)
        let context = UKGalleryChrome.context()
        let page = UKSettingsViewController(context: context)
        let window = HostedPage.show(UKGalleryChrome.wrap(page, context: context))
        defer { window.isHidden = true }
        XCTAssertTrue(HostedPage.until(8) { page.presentedViewController != nil || window.rootViewController?.presentedViewController != nil },
                      "the app icon picker is presented without a tap")
    }
}
