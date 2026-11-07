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
        UKGallery.design, UKGallery.designLists, UKGallery.designControls, UKGallery.shell, UKGallery.home, UKGallery.security, UKGallery.climate,
        UKGallery.chores, UKGallery.settings, UKGallery.household, UKGallery.rooms, UKGallery.vacuums, UKGallery.food, UKGallery.setup, UKGallery.liveActivity,
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

    func testClimateSheetsAndScenarios() {
        var variants = [Variant(.climate, ["FENTON_GALLERY_CLIMATE_SCENARIO": "away"])]
        for tab in ClimateConfig.Tab.allCases { variants.append(Variant(.climate, ["FENTON_GALLERY_CLIMATE_OPEN": tab.rawValue], sheet: true)) }
        variants.append(Variant(.climate, ["FENTON_GALLERY_CLIMATE_SCENARIO": "away", "FENTON_GALLERY_CLIMATE_OPEN": ClimateConfig.Tab.allCases[0].rawValue], sheet: true))
        run(variants)
    }

    func testWeatherAndHomeVariants() {
        var variants: [Variant] = []
        for mode in ["normal", "loading", "error", "empty"] {
            variants.append(Variant(.home, ["FENTON_GALLERY_WEATHER_STATE": mode]))
            variants.append(Variant(.weather, ["FENTON_GALLERY_WEATHER_STATE": mode, "FENTON_GALLERY_WEATHER_OPEN": "1"], sheet: true))
        }
        for condition in ["rainy", "clear-night", "snowy", "lightning", "fog", "windy", "sunny", "cloudy", "partlycloudy", "hail"] {
            variants.append(Variant(.weather, ["FENTON_GALLERY_WEATHER_CONDITION": condition]))
        }
        variants.append(Variant(.weather, ["FENTON_GALLERY_WEATHER_NIGHT": "1", "FENTON_GALLERY_WEATHER_NOAQI": "1", "FENTON_GALLERY_WEATHER_FILL": "0.5"]))
        run(variants)
    }

    func testBedroomSheetsAndScenarios() {
        var variants: [Variant] = []
        for scenario in ["ringing", "unavailable", "waking", "solo-trip", "hot-flash"] { variants.append(Variant(.bedroom, ["FENTON_GALLERY_SCENARIO": scenario])) }
        for tab in WakeLightSheet.Tab.allCases {
            variants.append(Variant(.bedroom, ["FENTON_GALLERY_SHEET": "wake-light", "FENTON_GALLERY_TAB": tab.rawValue], sheet: true))
        }
        for bed in MasterBedroom.beds {
            for tab in BedSideSheet.Tab.allCases {
                variants.append(Variant(.bedroom, ["FENTON_GALLERY_SHEET": bed.id, "FENTON_GALLERY_TAB": tab.rawValue], sheet: true))
            }
        }
        variants.append(Variant(.bedroom, ["FENTON_GALLERY_SCENARIO": "ringing", "FENTON_GALLERY_SHEET": "wake-light"], sheet: true))
        variants.append(Variant(.bedroom, ["FENTON_GALLERY_SCENARIO": "unavailable", "FENTON_GALLERY_SHEET": MasterBedroom.beds[0].id], sheet: true))
        run(variants)
    }

    func testRoomDeviceSheets() {
        var variants: [Variant] = []
        for device in RoomDeviceFixture.all() {
            variants.append(Variant(.roomDevices, ["FENTON_GALLERY_DEVICE": device.id], sheet: true))
            for tab in HumidifierTab.allCases {
                variants.append(Variant(.roomDevices, ["FENTON_GALLERY_DEVICE": device.id, "FENTON_GALLERY_TAB": tab.rawValue], sheet: true))
            }
        }
        run(variants)
    }

    func testMediaRemoteTabsAndRemotes() {
        var variants: [Variant] = []
        for remote in MediaRemotes.all {
            for tab in MediaRemoteTab.allCases {
                variants.append(Variant(.mediaPage, ["FENTON_GALLERY_REMOTE": remote.id, "FENTON_GALLERY_TAB": tab.rawValue], sheet: true))
            }
        }
        for tab in MediaRemoteTab.allCases { variants.append(Variant(.mediaRemote, ["FENTON_GALLERY_TAB": tab.rawValue])) }
        run(variants)
    }

    func testVacuumScenariosTabsAndAreaEditor() {
        var variants: [Variant] = []
        for scenario in ["docked", "cleaning", "paused", "error", "resumable", "unavailable", "dockWash", "dockPrep", "noMop", "modeVacuum", "modeMop", "areaDrawn", "autoUnavailable"] {
            variants.append(Variant(.vacuums, ["FENTON_GALLERY_SCENARIO": scenario]))
            for tab in VacuumTab.allCases {
                variants.append(Variant(.vacuums, ["FENTON_GALLERY_SCENARIO": scenario, "FENTON_GALLERY_VACUUM": Vacuums.all[0].vacuumMapId ?? "", "FENTON_GALLERY_TAB": tab.rawValue], sheet: true))
            }
        }
        run(variants)
    }

    func testRoomsSprinklersAndCustomLights() {
        var variants: [Variant] = []
        for room in RoomsConfig.pages { variants.append(Variant(.rooms, ["FENTON_GALLERY_ROOM": room.id])) }
        variants.append(Variant(.rooms, ["FENTON_GALLERY_QUICK_LINKS": "1"]))
        for controller in ["frontYard", "backyard"] {
            variants.append(Variant(.sprinklers, ["FENTON_GALLERY_SPRINKLER": controller], sheet: true))
            for zone in 1...3 {
                variants.append(Variant(.sprinklers, ["FENTON_GALLERY_SPRINKLER": controller, "FENTON_GALLERY_DETAIL": "water-\(zone)"], sheet: true))
                variants.append(Variant(.sprinklers, ["FENTON_GALLERY_SPRINKLER": controller, "FENTON_GALLERY_DETAIL": "schedule-\(zone)"], sheet: true))
            }
        }
        for light in CustomLightsConfig.lights { variants.append(Variant(.customLights, ["FENTON_GALLERY_LIGHT": light.entityId], sheet: true)) }
        run(variants)
    }

    func testSecurityHouseholdAndShellScenarios() {
        var variants: [Variant] = []
        for scenario in ["unavailable", "triggered", "openHome", "openAway", "openArmed"] { variants.append(Variant(.security, ["FENTON_GALLERY_SCENARIO": scenario])) }
        variants.append(Variant(.security, ["FENTON_GALLERY_FAIL": "1"]))
        for scenario in VacationFixtures.Scenario.allCases { variants.append(Variant(.vacation, ["FENTON_GALLERY_AWAY": scenario.rawValue])) }
        variants.append(Variant(.householdSettings, ["FENTON_GALLERY_UNAVAILABLE": "1"]))
        for page in HouseholdSettingsPage.allCases { variants.append(Variant(.householdSettings, ["FENTON_GALLERY_HOUSEHOLD": page.rawValue])) }
        for extra in [["FENTON_GALLERY_PHONE": "1"], ["FENTON_GALLERY_PHOTOS": "1"], ["FENTON_GALLERY_BADGE": "3"], ["FENTON_GALLERY_OFFLINE": "1"],
                      ["FENTON_GALLERY_RECONNECTING": "1"], ["FENTON_GALLERY_SCHEME": "light"], ["FENTON_GALLERY_PUSHED": "1"], ["FENTON_GALLERY_PLAIN": "1"],
                      ["FENTON_GALLERY_SCROLL": "1", "FENTON_GALLERY_SCROLL_TO": "10"]] {
            variants.append(Variant(.shellHeader, extra))
        }
        variants.append(Variant(.shellHeader, ["FENTON_GALLERY_PROFILE": "Sam"]))
        run(variants)
    }

    func testPerformanceWorkloadsAndDesignExtras() {
        run([Variant(.performance, ["FENTON_GALLERY_PERF": "gate", "FENTON_GALLERY_GATE_DELAY_MS": "50"]),
             Variant(.performance, ["FENTON_GALLERY_PERF": "grid"]), Variant(.performance, ["FENTON_GALLERY_PERF": "chips"]),
             Variant(.performance, ["FENTON_GALLERY_PERF": "screen"])])
        run([Variant(.floatingActions, ["FENTON_UK_EXTRAS": "1"]), Variant(.modalSizing, ["FENTON_GALLERY_MODAL_OPEN": "1"]),
             Variant(.settings, ["FENTON_GALLERY_FLYOUT": "1"]), Variant(.chores, ["FENTON_GALLERY_EMPTY": "1"]),
             Variant(.chores, ["FENTON_GALLERY_VIEWER": "resident_2", "FENTON_GALLERY_CHORES": "30"]), Variant(.chores, ["FENTON_GALLERY_FAIL_COMPLETE": "1"]),
             Variant(.food, ["FENTON_GALLERY_FOOD_MODE": "error"]), Variant(.food, ["FENTON_GALLERY_FOOD_MODE": "empty"]),
             Variant(.inventory, ["FENTON_GALLERY_STATE": "empty"]), Variant(.inventory, ["FENTON_GALLERY_SORT": "expiry", "FENTON_GALLERY_SPACE": "fridge"]),
             Variant(.liveActivity, ["FENTON_GALLERY_SCENARIO": "stack"]), Variant(.liveActivity, ["FENTON_GALLERY_SCENARIO": "alarm"])])
    }

    func testTabletAndDuoLayouts() {
        let variants = [Variant(.home), Variant(.rooms), Variant(.security), Variant(.vacuums), Variant(.climate), Variant(.settings, ["FENTON_GALLERY_FLYOUT": "1"]),
                        Variant(.cameraViewer)]
        run(variants, size: CGSize(width: 1180, height: 820))
        run(variants, size: CGSize(width: 820, height: 1180))
        run(variants, size: CGSize(width: 720, height: 540))
    }
}
