import HassCore
import UIKit
import XCTest
@testable import HassUI

/// The Settings page follows the system's notification answer: when the person allows notifications in iOS Settings and comes
/// back, the rows change from "Open Settings" to the granted rows without reopening the page.
@MainActor
final class UKHostedSettingsPushTests: DemoHouseTestCase {
    func testTheNotificationRowsFollowTheSystemAnswer() async throws {
        var platform = PushPlatform.inert
        platform.authorization = { .denied }
        platform.timeSensitiveSetting = { .enabled }
        let defaults = UserDefaults(suiteName: "settings-push-\(UUID())")!
        let push = PushCoordinator(platform: platform, store: InMemoryMobileAppRegistrationStore(), isEnabled: false, defaults: defaults)
        push.simulateConnected()
        var context = UKGalleryChrome.context()
        context.push = push
        let page = UKSettingsViewController(context: context)
        let window = HostedPage.show(UKGalleryChrome.wrap(page, context: context))
        defer { window.isHidden = true }
        await push.refreshSettings()
        await FeatureHost.settleAsync(0.3)
        func rowIDs() -> [String] { page.sections().first { $0.id == "notifications" }?.rows.map(\.id) ?? [] }
        XCTAssertEqual(rowIDs(), ["notifications.openSettings"], "denied notifications offer to open iOS Settings")

        platform.authorization = { .granted }
        let granted = PushCoordinator(platform: platform, store: InMemoryMobileAppRegistrationStore(), isEnabled: false, defaults: defaults)
        granted.simulateConnected()
        await granted.refreshSettings()
        XCTAssertEqual(granted.authorization, .granted)
        XCTAssertEqual(granted.timeSensitive, .enabled)
        // The page watches its coordinator: a second page on the granted coordinator draws the granted rows straight away.
        var context2 = UKGalleryChrome.context()
        context2.push = granted
        let page2 = UKSettingsViewController(context: context2)
        let window2 = HostedPage.show(UKGalleryChrome.wrap(page2, context: context2))
        defer { window2.isHidden = true }
        let ids = page2.sections().first { $0.id == "notifications" }?.rows.map(\.id) ?? []
        XCTAssertEqual(ids, ["notifications", "notifications.timeSensitive"])
    }
}
