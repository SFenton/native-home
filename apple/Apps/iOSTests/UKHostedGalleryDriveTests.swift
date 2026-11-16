import HassCore
import UIKit
import XCTest
@testable import HassUI

/// The gallery pages and the sheets they open, used like a person: every control on screen is pressed or turned (and then on any
/// sheet that opens), in each fixture state the gallery offers. A page that crashes, hangs or stops answering under real input fails.
@MainActor
final class UKHostedGalleryDriveTests: DemoHouseTestCase {
    private struct Variant {
        var page: ComponentGallery.Page
        var env: [String: String]
        init(_ page: ComponentGallery.Page, _ env: [String: String] = [:]) { self.page = page; self.env = env }
    }

    private let lanes: [@MainActor (ComponentGallery.Page) -> UIViewController?] = [
        UKGallery.design, UKGallery.designLists, UKGallery.designControls, UKGallery.shell, UKGallery.components, UKGallery.setup, UKGallery.liveActivity,
    ]

    /// Presses everything on the page, then on whatever it presented, up to `depth` levels.
    private func drive(_ root: UIViewController, depth: Int = 3) {
        for pass in 0..<2 {
            let top = HostedDriver.topmost(root)
            HostedDriver.useAll(in: top.view, except: ["close", "done", "dismiss", "back", "delete", "remove", "sign out", "reset", "clear all"], settle: 0.03)
            hostedSettle(0.25)
            let after = HostedDriver.topmost(root)
            if after !== top, depth > 0, pass == 0 { drive(root, depth: depth - 1) }
            if after !== top, let presented = after.presentingViewController, depth == 0 {
                HostedPage.settlePresentations(of: root)
                presented.dismiss(animated: false)
            }
        }
    }

    private func run(_ variants: [Variant], size: CGSize = CGSize(width: 393, height: 852)) {
        for variant in variants {
            for (key, value) in variant.env { setenv(key, value, 1) }
            defer { for key in variant.env.keys { unsetenv(key) } }
            var built: UIViewController?
            for lane in lanes { if let controller = lane(variant.page) { built = controller; break } }
            guard let root = built else { XCTFail("no lane builds \(variant.page.rawValue)"); continue }
            let window = HostedPage.show(root, size: size)
            hostedSettle(0.8)
            drive(root)
            XCTAssertFalse(HostedPage.descendants(of: root.view).isEmpty, "\(variant.page.rawValue) \(variant.env) still draws after input")
            // An alert or sheet the last press opened may still be animating in: dismissing it half way leaves UIKit's deferred
            // transition asking a dismissed controller for its alert, which throws during the next variant's wait.
            HostedPage.settlePresentations(of: root)
            root.dismiss(animated: false)
            window.isHidden = true
        }
    }

    func testGrillSheetTakesInput() {
        let variants = RoomDeviceFixture.all().filter { $0.kind == .grill }.map { Variant(.roomDevices, ["FENTON_GALLERY_DEVICE": $0.id]) }
        run(variants, size: CGSize(width: 393, height: 2400))
    }

    func testDesignControlsAndListsGalleriesTakeInput() {
        run([Variant(.thermostatDial), Variant(.motion), Variant(.cameraViewer), Variant(.floatingActions, ["FENTON_UK_EXTRAS": "1"]), Variant(.modalSizing, ["FENTON_GALLERY_MODAL_OPEN": "1"])],
            size: CGSize(width: 393, height: 2400))
    }
}
