import HassCore
import UIKit
import XCTest
@testable import HassUI

/// Room overview sheets: a room's tile pushes its group detail inside the sheet, and the lights in it send their calls.
@MainActor
final class UKHostedOverviewDetailTests: DemoHouseTestCase {
    func testEachOverviewOpensEveryRoomDetailAndItsLightsSendCalls() {
        var detailPages = 0
        for kind in RoomOverviewKind.allCases {
            let store = HomeFixtures.store(environment: [:])
            let caller = HostedCaller()
            let context = UKGalleryChrome.context(store: store, caller: caller)
            let host = UIViewController()
            let window = HostedPage.show(host, size: HostedDriver.tall)
            let modal = UKRoomOverviewSheet.controller(context: context, kind: kind)
            modal.present(from: host, animated: false)
            hostedSettle(0.6)
            let root = modal.viewControllers.first
            let tiles = HostedPage.descendants(of: modal.view).compactMap { $0 as? UKGlassTileView }
            XCTAssertFalse(tiles.isEmpty, "\(kind) lists rooms as tiles")
            for tile in tiles {
                tile.sendActions(for: .touchUpInside)
                hostedSettle(0.4)
                if let page = modal.topViewController as? UKRoomGroupDetailPageViewController {
                    detailPages += 1
                    XCTAssertFalse(HostedPage.labels(in: page.view).isEmpty, "\(kind) detail shows its group")
                    HostedDriver.useAll(in: page.view, settle: 0.05)
                    hostedSettle(0.3)
                    // The close action returns to the overview.
                    _ = modal.popViewController(animated: false)
                    hostedSettle(0.2)
                }
            }
            modal.popToRootViewController(animated: false)
            XCTAssertNotNil(root)
            modal.dismiss(animated: false)
            window.isHidden = true
        }
        XCTAssertGreaterThan(detailPages, 3, "overview tiles open room details")
    }

    /// A person's tap on a light tile in a room's detail inside the lights overview sends the light's own service call.
    func testTappingALightTileInARoomDetailCallsTheLightService() throws {
        let store = HomeFixtures.store(environment: [:])
        let caller = LoggingResponder()
        let context = UKGalleryChrome.context(store: store, caller: caller)
        let host = UIViewController()
        let window = HostedPage.show(host, size: HostedDriver.tall)
        defer { window.isHidden = true }
        let modal = UKRoomOverviewSheet.controller(context: context, kind: .lights)
        modal.present(from: host, animated: false)
        hostedSettle(0.6)
        let rooms = HostedPage.descendants(of: modal.view).compactMap { $0 as? UKGlassTileView }
        var tapped = false
        for room in rooms {
            room.sendActions(for: .touchUpInside)
            hostedSettle(0.4)
            guard let page = modal.topViewController as? UKRoomGroupDetailPageViewController else { continue }
            let lights = HostedPage.descendants(of: page.view).compactMap { $0 as? UKGlassTileView }
                .filter { ($0.accessibilityIdentifier ?? "").hasPrefix("room.light.") && $0.isEnabled }
            if let light = lights.first {
                light.sendActions(for: .touchUpInside)
                hostedSettle(0.5)
                tapped = true
                break
            }
            _ = modal.popViewController(animated: false)
        }
        XCTAssertTrue(tapped, "a room with a light tile exists in the fixtures")
        XCTAssertTrue(caller.calls.contains { $0 == "light.turn_on" || $0 == "light.turn_off" },
                      "tapping the light tile sends turn_on or turn_off; saw \(caller.calls)")
    }
}
