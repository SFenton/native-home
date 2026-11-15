import HassCore
import UIKit
import XCTest
@testable import HassUI

/// Every gallery page in each fixture scenario the gallery offers (`FENTON_GALLERY_*`): the sheets that open at launch (climate,
/// weather, bedroom, humidifier, media remote, vacuum, sprinklers, custom lights), the device scenarios (vacuum cleaning, error, dock,
/// bedroom ringing, alarm triggered, door open, vacation states) and the Home banner variants. A scenario that no longer builds or draws
/// nothing is a regression in the pages and sheets behind it.
@MainActor
final class UKHostedGalleryVariantTests: DemoHouseTestCase {
    private struct Variant {
        var page: ComponentGallery.Page
        var env: [String: String]
        var opensSheet = false
        init(_ page: ComponentGallery.Page, _ env: [String: String] = [:], sheet: Bool = false) {
            self.page = page; self.env = env; opensSheet = sheet
        }
    }

    private let lanes: [@MainActor (ComponentGallery.Page) -> UIViewController?] = [
        UKGallery.design, UKGallery.designLists, UKGallery.designControls, UKGallery.shell, UKGallery.components, UKGallery.setup, UKGallery.liveActivity,
    ]

    private func run(_ variants: [Variant], size: CGSize = CGSize(width: 393, height: 852), file: StaticString = #filePath, line: UInt = #line) {
        for variant in variants {
            for (key, value) in variant.env { setenv(key, value, 1) }
            defer { for key in variant.env.keys { unsetenv(key) } }
            XCTAssertEqual(ProcessInfo.processInfo.environment[variant.env.keys.first ?? "PATH"] == nil, false, file: file, line: line)
            var built: UIViewController?
            for lane in lanes { if let controller = lane(variant.page) { built = controller; break } }
            guard let root = built else { XCTFail("no lane builds \(variant.page.rawValue)", file: file, line: line); continue }
            let window = HostedPage.show(root, size: size)
            hostedSettle(variant.opensSheet ? 0.9 : 0.3)
            let name = "\(variant.page.rawValue) \(variant.env)"
            XCTAssertFalse(HostedPage.descendants(of: root.view).isEmpty, "\(name) draws", file: file, line: line)
            if variant.opensSheet {
                let top = Self.topmost(root)
                XCTAssertNotEqual(top, root, "\(name) opens its sheet at launch", file: file, line: line)
                top.dismiss(animated: false)
            }
            window.rootViewController?.dismiss(animated: false)
            window.isHidden = true
        }
    }

    private static func topmost(_ controller: UIViewController) -> UIViewController {
        var top = controller
        while let next = top.presentedViewController { top = next }
        return top
    }

    func testRoomDeviceSheets() {
        let variants = RoomDeviceFixture.all().filter { $0.kind == .grill }.map { Variant(.roomDevices, ["FENTON_GALLERY_DEVICE": $0.id], sheet: true) }
        run(variants)
    }

    func testPerformanceWorkloadsAndDesignExtras() {
        run([Variant(.performance, ["FENTON_GALLERY_PERF": "gate", "FENTON_GALLERY_GATE_DELAY_MS": "50"]),
             Variant(.performance, ["FENTON_GALLERY_PERF": "grid"]), Variant(.performance, ["FENTON_GALLERY_PERF": "chips"]),
             Variant(.performance, ["FENTON_GALLERY_PERF": "screen"])])
        run([Variant(.floatingActions, ["FENTON_UK_EXTRAS": "1"]), Variant(.modalSizing, ["FENTON_GALLERY_MODAL_OPEN": "1"]),
             Variant(.liveActivity, ["FENTON_GALLERY_SCENARIO": "stack"]), Variant(.liveActivity, ["FENTON_GALLERY_SCENARIO": "alarm"])])
    }

    func testTabletAndDuoLayouts() {
        let variants = [Variant(.cameraViewer), Variant(.roomDevices)]
        run(variants, size: CGSize(width: 1180, height: 820))
        run(variants, size: CGSize(width: 820, height: 1180))
        run(variants, size: CGSize(width: 720, height: 540))
    }
}
