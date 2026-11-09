import HassCore
import UIKit
import XCTest
@testable import HassUI

/// The media remote sheet on a wide window: the directional pad moves into a column beside the section, and goes back under it when
/// the window narrows.
@MainActor
final class UKHostedMediaRemoteWideTests: DemoHouseTestCase {
    func testAWideWindowPutsThePadBesideTheSectionAndANarrowOneStacksThem() throws {
        let config = try XCTUnwrap(MediaRemotes.all.first)
        let controller = MediaRemoteController(config: config, store: MediaRemoteFixtures.store(), caller: LoggingResponder())
        let context = UKGalleryChrome.context(store: controller.store)
        let root = UKMediaRemoteSheet.root(controller: controller, imageServer: nil, initialTab: .controls, context: context)
        let nav = UINavigationController(rootViewController: root)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1180, height: 820))
        HostedPage.track(window)
        defer { window.isHidden = true }
        // The sheet reads the window's own size class, so it is set before the first layout.
        window.traitOverrides.horizontalSizeClass = .regular
        window.rootViewController = nav
        window.makeKeyAndVisible()
        FeatureHost.settle(0.5)
        nav.view.layoutIfNeeded()
        FeatureHost.settle(0.3)
        XCTAssertNotNil(FeatureHost.view("remote.layout.twoColumn", in: window), "a wide regular window uses two columns")

        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.traitOverrides.horizontalSizeClass = .compact
        nav.view.setNeedsLayout()
        FeatureHost.settle(0.5)
        nav.view.layoutIfNeeded()
        FeatureHost.settle(0.3)
        XCTAssertNotNil(FeatureHost.view("remote.layout.singleColumn", in: window), "a narrow window goes back to one column")
    }

    func testAHueSyncRowActivatesForVoiceOverAndSaysWhenItIsOff() throws {
        let log = LoggingResponder()
        let store = MediaRemoteFixtures.store()
        let context = UKGalleryChrome.context(store: store, caller: log)
        let sheet = UKMediaRemoteSheet.make(config: MediaRemotes.sourceSelectRemote, store: store, caller: log, imageServer: nil, initialTab: .hueSync, context: context)
        let window = HostedPage.show(sheet, size: HostedDriver.tall)
        defer { window.isHidden = true }
        FeatureHost.settle(0.6)
        let rows = HostedPage.descendants(of: sheet.view).compactMap { $0 as? UKRemoteHueToggleRow }
        let row = try XCTUnwrap(rows.first { $0.isEnabled && $0.isUserInteractionEnabled }, "the light-sync tab draws a usable switch row")
        XCTAssertFalse(row.accessibilityTraits.contains(.notEnabled))
        var activated = 0
        row.addAction(UIAction { _ in activated += 1 }, for: .touchUpInside)
        XCTAssertTrue(row.accessibilityActivate(), "a VoiceOver double tap runs the row's action")
        XCTAssertEqual(activated, 1)

        row.isEnabled = false
        XCTAssertTrue(row.accessibilityTraits.contains(.notEnabled), "a row that cannot be used says so")
        XCTAssertFalse(row.accessibilityActivate())
        XCTAssertEqual(activated, 1)
    }
}
