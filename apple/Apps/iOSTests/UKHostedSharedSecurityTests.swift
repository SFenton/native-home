import HassCore
import UIKit
import XCTest
@testable import HassUI

/// The Security page with its cameras on: a tapped camera opens the viewer, the chips open the alarm controls and the contacts
/// overview, and a hinge moves every section off the fold.
@MainActor
final class UKHostedSharedSecurityTests: DemoHouseTestCase {
    private func page(shell: UKShellEnvironment? = nil) -> (UKSecurityViewController, UIWindow) {
        let store = SecurityFixtures.store(.standard)
        let recorder = GalleryServiceRecorder(store: store)
        var context = UKGalleryChrome.context(store: store, caller: recorder)
        context.shell = shell
        let pool = CameraStreamPool(modes: [], retainsShownStreams: true, observesApp: false, opener: { _, _, _, _ in },
                                    retryDelays: [], pauseAfterHidden: .seconds(600), stallAfter: .seconds(600),
                                    stallCheckInterval: .seconds(600), upgradeDelays: [], frameCounter: { _ in 1 }, prepareConnection: { _ in })
        let page = UKSecurityViewController(context: context, caller: recorder, canSend: { true }, showsCameras: true, showsVehicle: false, pool: pool)
        let window = HostedPage.show(UKGalleryChrome.wrap(page, context: context), size: CGSize(width: 393, height: 2600))
        HostedPage.wait(0.4)
        return (page, window)
    }

    func testTappingACameraOpensItsViewerAndTheSecurityChipOpensTheAlarmControls() {
        let (page, window) = page()
        defer { window.isHidden = true }
        let tiles = HostedPage.descendants(of: page.view).compactMap { $0 as? UKCameraTileView }
        XCTAssertEqual(tiles.count, HomeConfig.cameras.count, "every configured camera has a card")
        tiles.first?.sendActions(for: .touchUpInside)
        XCTAssertTrue(HostedPage.until { page.presentedViewController != nil }, "the camera opens in a viewer")
        HostedPage.wait(0.5)
        XCTAssertTrue(HostedPage.labels(in: page.presentedViewController?.view ?? UIView()).contains { $0.contains("Front Door") },
                      "and it is the tapped camera")
        page.presentedViewController?.dismiss(animated: false)
        XCTAssertTrue(HostedPage.until { page.presentedViewController == nil })

        let chip = HostedPage.descendants(of: page.view).compactMap { $0 as? UKStatusChipView }.first { ($0.accessibilityIdentifier ?? "").hasSuffix("security") }
        chip?.sendActions(for: .touchUpInside)
        XCTAssertTrue(HostedPage.until { page.presentedViewController != nil }, "the Security chip opens the alarm controls")
    }

    func testTheContactsChipOpensARoomOverviewAndAHingeMovesTheSectionsOffTheFold() {
        let shell = UKShellEnvironment()
        let (page, window) = page(shell: shell)
        defer { window.isHidden = true }
        page.open(.contacts)
        XCTAssertTrue(HostedPage.until { page.presentedViewController != nil }, "contacts open a room overview sheet")
        page.presentedViewController?.dismiss(animated: false)
        XCTAssertTrue(HostedPage.until { page.presentedViewController == nil })

        let cameras = HostedPage.descendants(of: page.view).compactMap { $0 as? UKCameraGridSectionView }.first
        shell.windowHinge = CGRect(x: 180, y: 0, width: 24, height: 2600)
        HostedPage.wait(0.3)
        XCTAssertEqual(cameras?.hinge, CGRect(x: 180, y: 0, width: 24, height: 2600), "the camera grid learns about the hinge")
        shell.windowHinge = nil
        HostedPage.wait(0.3)
        XCTAssertNil(cameras?.hinge)
    }
}
