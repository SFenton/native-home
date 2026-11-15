import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

/// The Location permission walk-through, hosted.
@MainActor
final class UKHostedHouseholdTests: DemoHouseTestCase {
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

/// The permission each stage of the location page shows (the gallery's stage table, kept for these tests).
private enum LocationGallery {
    static func answer(to permission: LocationPermission) -> LocationPermission {
        switch permission.authorization {
        case .notDetermined: LocationPermission(authorization: .whenInUse)
        case .whenInUse: LocationPermission(authorization: .always)
        case .always, .denied, .restricted: permission
        }
    }

    static func permission(for stage: LocationPermission.Stage) -> LocationPermission {
        switch stage {
        case .notDetermined: .notDetermined
        case .whenInUse: LocationPermission(authorization: .whenInUse)
        case .always: LocationPermission(authorization: .always)
        case .denied: LocationPermission(authorization: .denied)
        case .reducedAccuracy: LocationPermission(authorization: .always, isPrecise: false)
        }
    }
}
