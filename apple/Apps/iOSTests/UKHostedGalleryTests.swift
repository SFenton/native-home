import HassCore
import UIKit
import XCTest
@testable import HassUI

/// Builds every gallery page through the lane routers (what `FENTON_GALLERY=<page>` does) and checks each draws real content on the
/// phone, on the iPad width and at the largest accessibility text size. The gallery pages exercise the design components in each
/// state, so a page that fails to build or draws nothing is a regression in those components.
@MainActor
final class UKHostedGalleryTests: DemoHouseTestCase {
    private static let presentsItsOwnSurface: Set<ComponentGallery.Page> = [.liveActivity, .location, .profile, .setup]
    private typealias Lane = (ComponentGallery.Page) -> UIViewController?

    private var lanes: [Lane] {
        [
            UKGallery.design, UKGallery.designLists, UKGallery.designControls, UKGallery.shell, UKGallery.home, UKGallery.security, UKGallery.climate,
            UKGallery.chores, UKGallery.settings, UKGallery.household, UKGallery.rooms, UKGallery.vacuums, UKGallery.food, UKGallery.setup, UKGallery.liveActivity,
        ]
    }

    private func controller(for page: ComponentGallery.Page) -> UIViewController? {
        for lane in lanes {
            if let controller = lane(page) { return controller }
        }
        return nil
    }

    private func sweep(size: CGSize, largeText: Bool, file: StaticString = #filePath, line: UInt = #line) {
        var built = 0
        for page in ComponentGallery.Page.allCases where page != .backdrop {
            guard let root = controller(for: page) else { continue }
            if largeText { root.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge }
            let window = HostedPage.show(root, size: size)
            if Self.presentsItsOwnSurface.contains(page) {
                // These pages open a sheet or a Live Activity preview over an empty host rather than drawing in it.
                hostedSettle(0.4)
            } else {
                let views = HostedPage.descendants(of: root.view)
                XCTAssertGreaterThan(views.count, 8, "the \(page.rawValue) gallery page draws content", file: file, line: line)
                XCTAssertFalse(HostedPage.labels(in: root.view).isEmpty, "the \(page.rawValue) gallery page shows text", file: file, line: line)
            }
            window.isHidden = true
            built += 1
        }
        XCTAssertGreaterThan(built, 20, "most gallery pages are routed by a lane", file: file, line: line)
    }

    func testEveryGalleryPageDrawsOnThePhone() { sweep(size: CGSize(width: 393, height: 852), largeText: false) }
    func testEveryGalleryPageDrawsOnTheTablet() { sweep(size: CGSize(width: 1024, height: 768), largeText: false) }
    func testEveryGalleryPageDrawsAtTheLargestTextSize() { sweep(size: CGSize(width: 393, height: 852), largeText: true) }
    func testEveryGalleryPageDrawsOnTheNarrowDuoPane() { sweep(size: CGSize(width: 540, height: 720), largeText: false) }
}
