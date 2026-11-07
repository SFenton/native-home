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
        UKGallery.design, UKGallery.designLists, UKGallery.designControls, UKGallery.shell, UKGallery.home, UKGallery.security, UKGallery.climate,
        UKGallery.chores, UKGallery.settings, UKGallery.household, UKGallery.rooms, UKGallery.vacuums, UKGallery.food, UKGallery.setup, UKGallery.liveActivity,
    ]

    /// Presses everything on the page, then on whatever it presented, up to `depth` levels.
    private func drive(_ root: UIViewController, depth: Int = 3) {
        for pass in 0..<2 {
            let top = HostedDriver.topmost(root)
            HostedDriver.useAll(in: top.view, except: ["close", "done", "dismiss", "back", "delete", "remove", "sign out", "reset", "clear all"], settle: 0.03)
            hostedSettle(0.25)
            let after = HostedDriver.topmost(root)
            if after !== top, depth > 0, pass == 0 { drive(root, depth: depth - 1) }
            if after !== top, let presented = after.presentingViewController, depth == 0 { presented.dismiss(animated: false) }
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
            root.dismiss(animated: false)
            window.isHidden = true
        }
    }

    func testEveryRoomPageAndItsSheetsTakeInput() {
        run(RoomsConfig.pages.map { Variant(.rooms, ["FENTON_GALLERY_ROOM": $0.id]) } + [Variant(.rooms, ["FENTON_GALLERY_QUICK_LINKS": "1"]), Variant(.rooms)],
            size: CGSize(width: 393, height: 2400))
    }

    func testMediaRemotesSprinklersAndCustomLightsTakeInput() {
        var variants: [Variant] = [Variant(.mediaPage), Variant(.mediaRemote)]
        for remote in MediaRemotes.all { variants.append(Variant(.mediaRemote, ["FENTON_GALLERY_REMOTE": remote.id])) }
        for controller in ["frontYard", "backyard"] {
            variants.append(Variant(.sprinklers, ["FENTON_GALLERY_SPRINKLER": controller]))
            for zone in 1...3 {
                variants.append(Variant(.sprinklers, ["FENTON_GALLERY_SPRINKLER": controller, "FENTON_GALLERY_DETAIL": "water-\(zone)"]))
                variants.append(Variant(.sprinklers, ["FENTON_GALLERY_SPRINKLER": controller, "FENTON_GALLERY_DETAIL": "schedule-\(zone)"]))
            }
        }
        for light in CustomLightsConfig.lights { variants.append(Variant(.customLights, ["FENTON_GALLERY_LIGHT": light.entityId])) }
        run(variants, size: CGSize(width: 393, height: 2400))
    }

    func testWeatherHomeAndSecurityTakeInputInEveryState() {
        var variants: [Variant] = []
        for mode in ["normal", "loading", "error", "empty"] {
            variants.append(Variant(.weather, ["FENTON_GALLERY_WEATHER_STATE": mode, "FENTON_GALLERY_WEATHER_OPEN": "1"]))
            variants.append(Variant(.home, ["FENTON_GALLERY_WEATHER_STATE": mode]))
        }
        for condition in ["rainy", "clear-night", "snowy", "lightning", "fog", "windy", "sunny", "cloudy", "partlycloudy", "hail"] {
            variants.append(Variant(.weather, ["FENTON_GALLERY_WEATHER_CONDITION": condition, "FENTON_GALLERY_WEATHER_OPEN": "1"]))
        }
        variants.append(Variant(.weather, ["FENTON_GALLERY_WEATHER_NIGHT": "1", "FENTON_GALLERY_WEATHER_NOAQI": "1", "FENTON_GALLERY_WEATHER_OPEN": "1"]))
        for scenario in ["standard", "unavailable", "triggered", "openHome", "openAway", "openArmed"] { variants.append(Variant(.security, ["FENTON_GALLERY_SCENARIO": scenario])) }
        variants.append(Variant(.security, ["FENTON_GALLERY_FAIL": "1"]))
        run(variants, size: CGSize(width: 393, height: 2400))
    }

    func testBedroomAndRoomDeviceSheetsTakeInput() {
        var variants: [Variant] = []
        for scenario in ["ringing", "unavailable", "waking", "solo-trip", "hot-flash"] { variants.append(Variant(.bedroom, ["FENTON_GALLERY_SCENARIO": scenario])) }
        for device in RoomDeviceFixture.all() {
            variants.append(Variant(.roomDevices, ["FENTON_GALLERY_DEVICE": device.id]))
            for tab in HumidifierTab.allCases { variants.append(Variant(.roomDevices, ["FENTON_GALLERY_DEVICE": device.id, "FENTON_GALLERY_TAB": tab.rawValue])) }
        }
        run(variants, size: CGSize(width: 393, height: 2400))
    }

    func testDesignControlsAndListsGalleriesTakeInput() {
        run([Variant(.thermostatDial), Variant(.motion), Variant(.cameraViewer), Variant(.floatingActions, ["FENTON_UK_EXTRAS": "1"]), Variant(.modalSizing, ["FENTON_GALLERY_MODAL_OPEN": "1"])],
            size: CGSize(width: 393, height: 2400))
    }
}
