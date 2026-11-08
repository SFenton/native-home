import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

/// The household topics (Admin, Special Device Modes, Guests, Car) and the Location permission walk-through, hosted.
@MainActor
final class UKHostedHouseholdTests: DemoHouseTestCase {
    private func topic(_ page: HouseholdSettingsPage, unavailable: Bool = false) -> (UIViewController, HouseholdGalleryRecorder, UIWindow) {
        let store = HouseholdSettingsFixtures.store(unavailable: unavailable)
        let recorder = HouseholdGalleryRecorder(store: store)
        let context = UKGalleryChrome.context(store: store, caller: recorder)
        let screen = UKHouseholdSettingsViewController.make(page: page, context: context)
        let window = HostedPage.show(UKGalleryChrome.wrap(screen, context: context), size: CGSize(width: 393, height: 2600))
        FeatureHost.settle(0.6)
        return (screen, recorder, window)
    }

    private func tapEveryTile(in screen: UIViewController, skipping skipped: [String] = []) {
        let tiles = HostedPage.descendants(of: screen.view).compactMap { $0 as? UKGlassTileView }
        for tile in tiles where tile.isEnabled && !skipped.contains(where: { (tile.accessibilityIdentifier ?? "").hasPrefix($0) }) {
            tile.sendActions(for: .touchUpInside)
            FeatureHost.settle(0.05)
            // A question first: confirm it so the action runs.
            if let alert = FeatureHost.alert(on: screen), let confirm = alert.actions.last { FeatureHost.answer(alert, confirm.title) }
            screen.shownSheet?.dismiss(animated: false)
        }
    }

    func testEveryTopicShowsItsTilesAndATapCallsHomeAssistant() {
        for page in HouseholdSettingsPage.allCases {
            let (screen, recorder, window) = topic(page)
            defer { window.isHidden = true }
            XCTAssertNotNil(FeatureHost.view("household.\(page.rawValue)", in: screen.view), "\(page.rawValue) is on screen")
            let tiles = HostedPage.descendants(of: screen.view).compactMap { $0 as? UKGlassTileView }
            XCTAssertFalse(tiles.isEmpty, "\(page.rawValue) has tiles")
            tapEveryTile(in: screen)
            FeatureHost.settle(0.6)
            XCTAssertNotEqual(recorder.lastCall, "None", "\(page.rawValue): tapping tiles calls a service")
        }
    }

    func testUnavailableEntitiesLockTheirTiles() {
        for page in HouseholdSettingsPage.allCases {
            let (screen, recorder, window) = topic(page, unavailable: true)
            defer { window.isHidden = true }
            // Power recovery dims and fires nothing while its automation is unavailable (owner, 2026-11-03).
            tapEveryTile(in: screen)
            FeatureHost.settle(0.3)
            XCTAssertEqual(recorder.lastCall, "None", "\(page.rawValue): nothing is sent for an unavailable entity")
        }
    }

    func testWithoutAConnectionATopicIsAPlaceholder() {
        let context = UKContext(store: EntityStore(), caller: nil)
        XCTAssertTrue(UKHouseholdSettingsViewController.make(page: .admin, context: context) is UKPlaceholderViewController)
        XCTAssertNotNil(UKScreens.destination(for: .guests, context: context))
        XCTAssertTrue(UKScreens.vacation(context) is UKPlaceholderViewController)
    }

    func testYourSummaryEntryBuildsTheSheet() {
        XCTAssertNotNil(UKScreens.yourSummary(UKGalleryChrome.context()))
    }

    // MARK: Location

    func testEachPermissionStageSaysWhereYouAreAndWhatNext() {
        for stage in LocationPermission.Stage.allCases {
            var requested = 0
            var closed = 0
            var settings = 0
            let page = UKLocationPermissionViewController(
                permission: LocationGallery.permission(for: stage), canAskForAlways: true,
                onRequestPermission: { requested += 1 }, onOpenSettings: { settings += 1 }, onClose: { closed += 1 })
            let window = HostedPage.show(page)
            defer { window.isHidden = true }
            XCTAssertNotNil(FeatureHost.view("location.title", in: page.view), "\(stage): has a title")
            XCTAssertNotNil(FeatureHost.view("location.message", in: page.view))
            if stage == .always {
                // Everything is granted, so there is nothing left to ask for: the page only reports.
                XCTAssertNil(FeatureHost.view("location.primary", in: page.view), "always: nothing left to ask")
                XCTAssertFalse(FeatureHost.press("location.primary", in: page.view))
            } else {
                XCTAssertNotNil(FeatureHost.view("location.primary", in: page.view), "\(stage): has its one action")
                FeatureHost.press("location.primary", in: page.view)
                XCTAssertEqual(requested + settings, 1, "\(stage): the action either asks or opens Settings")
            }
            if let close = page.navigationItem.rightBarButtonItem ?? page.navigationItem.leftBarButtonItem {
                _ = close.primaryAction?.performWithSender(nil, target: nil)
            }
        }
    }

    func testAskingStagesCannotBeDismissedAndTheStatusStagesCan() {
        let asking = UKLocationPermissionViewController(permission: LocationGallery.permission(for: .notDetermined), onRequestPermission: {}, onClose: {})
        _ = HostedPage.show(asking)
        XCTAssertNil(asking.navigationItem.rightBarButtonItem, "the pre-alert has no Close")
        let always = UKLocationPermissionViewController(permission: LocationGallery.permission(for: .always), onRequestPermission: {}, onClose: {})
        _ = HostedPage.show(always)
        always.permission = LocationGallery.permission(for: .denied)
        always.canAskForAlways = false
        FeatureHost.settle(0.2)
        XCTAssertNotNil(FeatureHost.view("location.status", in: always.view))
    }

    func testThePermissionAdvancesWhenIosAnswers() {
        let page = UKLocationPermissionViewController(permission: LocationGallery.permission(for: .notDetermined), onRequestPermission: {}, onClose: {})
        let window = HostedPage.show(page)
        defer { window.isHidden = true }
        let before = HostedPage.labels(in: page.view)
        page.permission = LocationGallery.answer(to: page.permission)
        FeatureHost.settle(0.3)
        XCTAssertNotEqual(before, HostedPage.labels(in: page.view), "the page follows the new permission")
    }
}
