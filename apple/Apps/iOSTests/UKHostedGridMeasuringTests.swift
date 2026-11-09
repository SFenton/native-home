import HassCore
import UIKit
import XCTest
@testable import HassUI

/// Every view a Rooms-family page lays out in a dynamic grid measures itself two ways, `gridHeight(forWidth:)` for the grid and
/// `sizeThatFits(_:)` for Auto Layout and the sheet fitter. The two must agree, or a tile is cut off in one place and padded in another.
@MainActor
final class UKHostedGridMeasuringTests: DemoHouseTestCase {
    private func measuring(in root: UIView) -> [UIView] {
        HostedPage.descendants(of: root).filter { $0 is any UKGridMeasuring }
    }

    private func assertSizesAgree(_ screen: UIViewController, _ name: String, width: CGFloat = 340) {
        let views = measuring(in: screen.view)
        XCTAssertFalse(views.isEmpty, "\(name) lays out grid-measured views")
        for view in views {
            guard let measured = view as? any UKGridMeasuring else { continue }
            let size = view.sizeThatFits(CGSize(width: width, height: 10))
            let height = measured.gridHeight(forWidth: size.width)
            // A view that has no opinion of its own falls back to UIKit's `sizeThatFits`, which is the size it was given.
            guard size.height != 10 else { continue }
            XCTAssertEqual(size.height, height, accuracy: 1, "\(name): \(type(of: view)) reports one height to the grid and another to Auto Layout")
        }
    }

    func testRoomsPagesAndTheirSheetsAgreeOnTheirMeasures() {
        let store = RoomsFixtures.store()
        let log = LoggingResponder(RoomsGalleryCaller(recorder: GalleryServiceRecorder(store: store), bedroom: BedroomGalleryRecorder(store: store)))
        let context = UKGalleryChrome.context(store: store, caller: log)
        let screens: [(String, UIViewController)] = [
            ("sprinklers", UKScreens.sprinklers(context)),
            ("custom lights", UKScreens.customLights(context)),
            ("media", UKScreens.media(context)),
        ] + RoomsConfig.pages.prefix(6).map { ($0.id, UKScreens.room($0.id, context)) }
        for (name, screen) in screens {
            let nav = UINavigationController(rootViewController: screen)
            let window = HostedPage.show(nav, size: CGSize(width: 393, height: 2400))
            FeatureHost.settle(0.4)
            assertSizesAgree(screen, name)
            window.isHidden = true
        }
    }

    func testTheLightingModeButtonSpeaksAsOneButtonWithItsMode() throws {
        let store = RoomsFixtures.store()
        let context = UKGalleryChrome.context(store: store, caller: LoggingResponder())
        let page = UKScreens.customLights(context)
        let window = HostedPage.show(UINavigationController(rootViewController: page), size: CGSize(width: 393, height: 1400))
        defer { window.isHidden = true }
        FeatureHost.settle(0.4)
        let button = HostedPage.descendants(of: page.view).first { $0.accessibilityLabel == CustomLightsConfig.lightingModeTitle }
        let found = try XCTUnwrap(button, "the Lighting Mode button is on the page")
        XCTAssertEqual(found.accessibilityHint, "Shows the lighting modes.")
        XCTAssertTrue(found.accessibilityTraits.contains(.button))
        XCTAssertNotNil(found.accessibilityValue, "it speaks the current mode")
    }
}
