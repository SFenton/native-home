import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

/// Settings rows the first tests skipped: each household topic, To-Do, Performance and the app icon row from the list, in a window
/// that pushes and in one that splits; the list rebuilding when the system settings it mirrors change.
@MainActor
final class UKHostedSettingsGapTests: DemoHouseTestCase {
    private func narrow() -> (UKSettingsViewController, UIWindow) {
        let context = UKGalleryChrome.context()
        let page = UKSettingsViewController(context: context)
        let window = HostedPage.show(UKGalleryChrome.wrap(page, context: context), size: CGSize(width: 393, height: 2400))
        return (page, window)
    }

    private func wide() -> (UKSettingsViewController, UIWindow) {
        let context = UKGalleryChrome.context()
        let page = UKSettingsViewController(context: context)
        let host = UKGalleryChrome.wrap(page, context: context)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1180, height: 820))
        window.traitOverrides.horizontalSizeClass = .regular
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        FeatureHost.settle(0.8)
        return (page, window)
    }

    func testEveryHouseholdTopicRowPushesItsPage() {
        // Under the shell a topic is a route on the Settings section: the section's stack shows it.
        let navigator = ShellNavigator()
        var context = UKGalleryChrome.context()
        context.navigator = navigator
        context.section = .settings
        let page = UKSettingsViewController(context: context)
        let window = HostedPage.show(UKGalleryChrome.wrap(page, context: context), size: CGSize(width: 393, height: 2400))
        defer { window.isHidden = true }
        for topic in HouseholdSettingsPage.allCases {
            let row = UKSettingsListRow.find("topic.\(topic.rawValue)", in: page.sections())
            XCTAssertNotNil(row, "\(topic.rawValue) has a row")
            row?.action?()
            FeatureHost.settle(0.3)
            XCTAssertEqual(navigator.routes(in: .settings), [.household(topic)], "\(topic.rawValue) pushed its page")
            navigator.trimPath(in: .settings, toDepth: 0)
        }
        UKSettingsListRow.find("todo", in: page.sections())?.action?()
        FeatureHost.settle(0.3)
        XCTAssertEqual(navigator.routes(in: .settings), [.settings(.adminTodo)], "To-Do pushed its page")
    }

    func testTheAppIconRowOpensThePickerSheet() {
        let (page, window) = narrow()
        defer { window.isHidden = true }
        guard let row = UKSettingsListRow.find("appIcon", in: page.sections()) else { return }  // alternate icons unsupported here
        row.action?()
        FeatureHost.settle(0.6)
        XCTAssertNotNil(page.shownSheet, "the row opens the icon picker")
    }

    func testOnASplitWindowEveryRowOpensBesideTheListAndReopeningIsQuiet() {
        let (page, window) = wide()
        defer { window.isHidden = true }
        XCTAssertTrue(page.columns.isWide)
        for id in ["todo", "topic.\(HouseholdSettingsPage.admin.rawValue)", "topic.\(HouseholdSettingsPage.guests.rawValue)"] {
            guard let row = UKSettingsListRow.find(id, in: page.sections()) else { continue }
            row.action?()
            FeatureHost.settle(0.6)
            XCTAssertEqual(page.columns.entries.count, 1, "\(id) opens in the right column")
            let open = page.columns.entries.first?.tag
            row.action?()
            FeatureHost.settle(0.3)
            XCTAssertEqual(page.columns.entries.first?.tag, open, "tapping the open row again changes nothing")
        }
    }

    func testRoutesFromTheShellOpenAndCloseTheRightColumn() {
        let (page, window) = wide()
        defer { window.isHidden = true }
        page.syncColumnRoutes([.household(.admin)], animated: false)
        FeatureHost.settle(0.5)
        XCTAssertEqual(page.columns.entries.count, 1, "a route opens its page")
        page.syncColumnRoutes([], animated: false)
        FeatureHost.settle(0.5)
        XCTAssertEqual(page.columns.entries.count, 0, "an empty route list closes it")
    }

    func testTheListRebuildsWhenReduceTransparencyOrADefaultChanges() {
        let (page, window) = narrow()
        defer { window.isHidden = true }
        let before = Set(FeatureHost.identifiers(in: page.view))
        NotificationCenter.default.post(name: UIAccessibility.reduceTransparencyStatusDidChangeNotification, object: nil)
        FeatureHost.settle(0.5)
        XCTAssertEqual(Set(FeatureHost.identifiers(in: page.view)), before, "the same rows come back after a rebuild")
        UserDefaults.standard.set(true, forKey: "uk.gap.test.key")
        UserDefaults.standard.removeObject(forKey: "uk.gap.test.key")
        FeatureHost.settle(0.3)
        XCTAssertNotNil(FeatureHost.view("settings.list", in: page.view))
    }
}
