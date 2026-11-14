import UIKit
import XCTest
@testable import HassUI

/// The teardown rule of the hosted driver: a presentation still animating in is let finish before the page is dismissed
/// (``HostedPage/settlePresentations(of:timeout:)``), so UIKit's deferred alert transition never meets a dismissed alert
/// (`UKHostedGalleryDriveTests.testMediaRemotesSprinklersAndCustomLightsTakeInput`, nightly 2026-11-14).
@MainActor
final class UKHostedPresentationSettleTests: DemoHouseTestCase {
    private func alert() -> UIAlertController {
        let alert = UIAlertController(title: "Stop watering?", message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        return alert
    }

    func testAnIdlePageIsNotTransitioning() {
        let root = UIViewController()
        let window = HostedPage.show(root)
        defer { window.isHidden = true }
        XCTAssertFalse(HostedPage.isTransitioning(root))
    }

    func testAnAlertStillAnimatingInIsTransitioningUntilSettled() {
        let root = UIViewController()
        let window = HostedPage.show(root)
        defer { window.isHidden = true }
        root.present(alert(), animated: true)
        XCTAssertTrue(HostedPage.isTransitioning(root), "the alert is mid-presentation straight after present(_:animated:)")
        HostedPage.settlePresentations(of: root)
        XCTAssertFalse(HostedPage.isTransitioning(root), "settling waits for the presentation to finish")
        XCTAssertTrue(root.presentedViewController is UIAlertController, "settling leaves the alert on screen")
    }

    func testDismissingAfterSettlingLeavesNoTransitionBehind() {
        let root = UIViewController()
        let window = HostedPage.show(root)
        defer { window.isHidden = true }
        root.present(alert(), animated: true)
        HostedPage.settlePresentations(of: root)
        root.dismiss(animated: false)
        HostedPage.wait(0.6)
        XCTAssertNil(root.presentedViewController)
        XCTAssertFalse(HostedPage.isTransitioning(root))
    }
}
