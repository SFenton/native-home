import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

/// Admin's two sheets: Presence-Based Light Overrides (a room grid that pushes a four-mode list) and Presence Auto-Reset.
@MainActor
final class UKHostedHouseholdAdminTests: DemoHouseTestCase {
    private func admin(unavailable: Bool = false) -> (UIViewController, HouseholdGalleryRecorder, UIWindow) {
        let store = HouseholdSettingsFixtures.store(unavailable: unavailable)
        let recorder = HouseholdGalleryRecorder(store: store)
        let context = UKGalleryChrome.context(store: store, caller: recorder)
        let screen = UKHouseholdSettingsViewController.make(page: .admin, context: context)
        let window = HostedPage.show(UKGalleryChrome.wrap(screen, context: context), size: CGSize(width: 393, height: 2600))
        FeatureHost.settle(0.6)
        return (screen, recorder, window)
    }

    private func openSheet(_ identifier: String, on screen: UIViewController) async throws -> UIViewController {
        XCTAssertTrue(FeatureHost.press(identifier, in: screen.view), "\(identifier) is on Admin")
        await FeatureHost.settleAsync(1.0)
        return try XCTUnwrap(screen.presentedViewController, "\(identifier) opens a sheet")
    }

    /// The page a room pushed on the sheet (the push animation does not finish in a hosted window, so the sheet's own view lacks it).
    private func pushedPage(_ sheet: UIViewController) throws -> UIView {
        let modal = try XCTUnwrap(sheet as? UKHassModalController)
        XCTAssertEqual(modal.viewControllers.count, 2, "the room's modes are pushed on the sheet")
        return try XCTUnwrap(modal.topViewController?.view)
    }

    func testEveryRoomIsATileThatOpensItsFourModes() async throws {
        let (screen, _, window) = admin()
        defer { window.isHidden = true }
        let sheet = try await openSheet("admin.open.presenceOverrides", on: screen)
        for room in HouseholdSettingsConfig.Admin.presenceRooms {
            XCTAssertNotNil(FeatureHost.view("presence.room.\(room.presenceEntityId)", in: sheet.view), "\(room.title) has a tile")
        }
        let room = HouseholdSettingsConfig.Admin.presenceRooms[0]
        XCTAssertTrue(FeatureHost.press("presence.room.\(room.presenceEntityId)", in: sheet.view))
        await FeatureHost.settleAsync(0.8)
        let detail = try pushedPage(sheet)
        for mode in PresenceOverrideState.choices {
            XCTAssertNotNil(FeatureHost.view("presence.option.\(mode.rawValue)", in: detail), "\(mode.rawValue) is offered")
        }
        XCTAssertEqual(detail.accessibilityIdentifier, "presence.detail")
    }

    func testChoosingAModeSendsItForThatRoom() async throws {
        let (screen, recorder, window) = admin()
        defer { window.isHidden = true }
        let sheet = try await openSheet("admin.open.presenceOverrides", on: screen)
        let room = HouseholdSettingsConfig.Admin.presenceRooms[1]
        XCTAssertTrue(FeatureHost.press("presence.room.\(room.presenceEntityId)", in: sheet.view))
        await FeatureHost.settleAsync(0.8)
        XCTAssertTrue(FeatureHost.press("presence.option.paused", in: try pushedPage(sheet)))
        await FeatureHost.settleAsync(0.8)
        XCTAssertTrue(recorder.lastCall.contains("presence_based_lighting") && recorder.lastCall.contains("paused"), recorder.lastCall)
        XCTAssertTrue(recorder.lastCall.contains(room.presenceEntityId), "it names the room: \(recorder.lastCall)")
    }

    func testAnUnavailableRoomExplainsAndOffersNoChoice() async throws {
        let (screen, recorder, window) = admin(unavailable: true)
        defer { window.isHidden = true }
        let sheet = try await openSheet("admin.open.presenceOverrides", on: screen)
        let room = HouseholdSettingsConfig.Admin.presenceRooms[0]
        XCTAssertTrue(FeatureHost.press("presence.room.\(room.presenceEntityId)", in: sheet.view), "an unavailable room stays openable")
        await FeatureHost.settleAsync(0.8)
        XCTAssertTrue(HostedPage.labels(in: try pushedPage(sheet)).contains(PresenceOverrideState.unavailable.detail), "the detail says why")
        _ = FeatureHost.press("presence.option.paused", in: try pushedPage(sheet))
        await FeatureHost.settleAsync(0.5)
        XCTAssertEqual(recorder.lastCall, "None", "the choices are disabled")
    }

    func testAutoResetHasOneToggleForEveryRoomAndATapCallsHomeAssistant() async throws {
        let (screen, recorder, window) = admin()
        defer { window.isHidden = true }
        let sheet = try await openSheet("admin.open.autoReset", on: screen)
        let tiles = HostedPage.descendants(of: sheet.view).compactMap { $0 as? UKGlassTileView }
        XCTAssertEqual(tiles.count, HouseholdSettingsConfig.Admin.autoResetTiles.count, "one toggle per room")
        let tile = try XCTUnwrap(tiles.first { $0.isEnabled })
        tile.sendActions(for: .touchUpInside)
        await FeatureHost.settleAsync(0.8)
        XCTAssertNotEqual(recorder.lastCall, "None")
    }
}
