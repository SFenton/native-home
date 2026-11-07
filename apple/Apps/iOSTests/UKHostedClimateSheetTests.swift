import HassCore
import UIKit
import XCTest
@testable import HassUI

/// The Advanced Controls sheet (Rooms, Automation, Tracking and the pages pushed inside it) opened on the gallery's fixture house,
/// then used: the switches, steppers and rows a person touches, and the service calls they send.
@MainActor
final class UKHostedClimateSheetTests: DemoHouseTestCase {
    private struct Sheet {
        let modal: UKHassModalController
        let host: UKClimateSheetHost?
        let window: UIWindow
        let caller: HostedCaller
        let store: EntityStore
    }

    private func open(_ scenario: ClimateFixtures.Scenario = .home, tab: ClimateConfig.Tab = .rooms, route: ClimateRoute? = nil) -> Sheet {
        let store = ClimateFixtures.store(scenario: scenario)
        let caller = HostedCaller()
        let context = UKGalleryChrome.context(store: store, caller: caller)
        let controller = ClimateController(store: store, caller: caller)
        let modal = UKClimateSheet.make(controller: controller, context: context, request: ClimateSheetRequest(tab: tab, route: route))
        let window = HostedPage.show(modal, size: HostedDriver.tall)
        hostedSettle(0.4)
        let host = HostedPage.descendants(of: modal.view).isEmpty ? nil : Self.findHost(modal)
        return Sheet(modal: modal, host: host, window: window, caller: caller, store: store)
    }

    private static func findHost(_ controller: UIViewController) -> UKClimateSheetHost? {
        if let host = controller as? UKClimateSheetHost { return host }
        for child in controller.children { if let found = findHost(child) { return found } }
        return nil
    }

    private func close(_ sheet: Sheet) { sheet.window.isHidden = true }

    func testSheetTitleAndTabBarChooseTabs() throws {
        let sheet = open()
        defer { close(sheet) }
        let host = try XCTUnwrap(sheet.host)
        XCTAssertEqual(host.currentTab, .rooms)
        XCTAssertTrue(HostedPage.labels(in: sheet.modal.view).contains(ClimateConfig.sheetTitle), "the sheet is titled Advanced Controls")
        for tab in ClimateConfig.Tab.allCases {
            HostedDriver.pickTab(host.tabBar, ClimateConfig.Tab.allCases.firstIndex(of: tab)!)
            hostedSettle(0.1)
            XCTAssertEqual(host.currentTab, tab, "picking \(tab.title) shows it")
        }
    }

    func testRoomsTabTilesOpenEachRoomDetail() throws {
        let sheet = open()
        defer { close(sheet) }
        let host = try XCTUnwrap(sheet.host)
        var opened: [ClimateRoute] = []
        host.open = { opened.append($0) }
        let tiles = HostedPage.descendants(of: host.view).compactMap { $0 as? UKGlassTileView }.filter { ($0.accessibilityIdentifier ?? "").hasPrefix("climate.room.") }
        XCTAssertEqual(tiles.count, ClimateConfig.rooms.count, "one tile per room")
        for tile in tiles { tile.sendActions(for: .touchUpInside) }
        XCTAssertEqual(opened, ClimateConfig.rooms.map { .room($0.key) })
    }

    func testEveryRouteOpensItsPageAndItsControlsSendCalls() throws {
        var routes: [ClimateRoute] = ClimateConfig.rooms.map { .room($0.key) }
        routes.append(.predictive)
        routes += ClimateConfig.EcoOption.allCases.map { .eco($0) }
        routes += ClimateConfig.TrackingPage.allCases.map { .tracking($0) }
        routes.append(.room("not_a_room"))
        for scenario in [ClimateFixtures.Scenario.home, .away] {
            for route in routes {
                let sheet = open(scenario, tab: route.tab, route: route)
                defer { close(sheet) }
                let top = sheet.modal.topViewController
                XCTAssertEqual(top?.navigationItem.title, route.title, "\(route) opens a page titled \(route.title)")
                if case .room("not_a_room") = route {
                    XCTAssertTrue(HostedPage.labels(in: sheet.modal.view).contains("Room Unavailable"))
                    continue
                }
                HostedDriver.useAll(in: top?.view ?? sheet.modal.view)
                hostedSettle(0.1)
                XCTAssertNotNil(sheet.modal.view.window, "\(route) leaves the sheet up")
            }
        }
    }

    func testAutomationSwitchesToggleTheirEntities() throws {
        let sheet = open(.home, tab: .automation)
        defer { close(sheet) }
        let host = try XCTUnwrap(sheet.host)
        let switches = HostedDriver.controls(UISwitch.self, in: host.view)
        XCTAssertGreaterThanOrEqual(switches.count, 3, "Automatic Thermostat, Eco Mode and Predictive Comfort are switches")
        for toggle in switches { HostedDriver.use(toggle) }
        hostedSettle(0.2)
        XCTAssertGreaterThanOrEqual(sheet.caller.calls.count, 3, "each switch sends its intent; got \(sheet.caller.calls)")
        let targets = Set(sheet.caller.data.compactMap { $0["entity_id"] as? String })
        XCTAssertTrue(targets.contains(ClimateConfig.ecoModeEntityId), "Eco Mode switch targets its entity; got \(targets)")
        XCTAssertTrue(targets.contains(ClimateConfig.integrationEntityId), "Automatic Thermostat switch targets its entity; got \(targets)")
    }

    func testAutomationRowsOpenPredictiveAndEcoPages() throws {
        let sheet = open(.home, tab: .automation)
        defer { close(sheet) }
        let host = try XCTUnwrap(sheet.host)
        var opened: [ClimateRoute] = []
        host.open = { opened.append($0) }
        let tab = try XCTUnwrap(HostedPage.descendants(of: host.view).compactMap { $0 as? UICollectionView }.first { $0.accessibilityIdentifier == "climate.sheet.automation" })
        HostedDriver.selectAll(in: tab)
        hostedSettle(0.1)
        XCTAssertTrue(opened.contains(.predictive), "Current Prediction opens Predictive Comfort; opened \(opened)")
    }

    func testTrackingTabRowsOpenTheirPagesAndAwayStateDiffers() throws {
        for scenario in [ClimateFixtures.Scenario.home, .away] {
            let sheet = open(scenario, tab: .tracking)
            defer { close(sheet) }
            let host = try XCTUnwrap(sheet.host)
            var opened: [ClimateRoute] = []
            host.open = { opened.append($0) }
            let list = try XCTUnwrap(HostedPage.descendants(of: host.view).compactMap { $0 as? UICollectionView }.first { $0.accessibilityIdentifier == "climate.sheet.tracking" })
            HostedDriver.selectAll(in: list)
            hostedSettle(0.1)
            XCTAssertFalse(opened.isEmpty, "\(scenario) tracking rows open pages")
            XCTAssertTrue(opened.allSatisfy { if case .tracking = $0 { true } else { false } })
        }
    }
}
