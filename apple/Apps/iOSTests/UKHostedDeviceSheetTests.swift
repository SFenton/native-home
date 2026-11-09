import HassCore
import UIKit
import XCTest
@testable import HassUI

/// Room-device sheets (humidifier, purifier, bathroom fan, grill) and the Rooms pages' card sheets, opened on fixture state and used.
@MainActor
final class UKHostedDeviceSheetTests: DemoHouseTestCase {
    private func sheet(for fixture: RoomDeviceFixture, tab: HumidifierTab = .controls, caller: LoggingResponder) -> UKHassModalController {
        let context = UKGalleryChrome.context(store: fixture.store, caller: caller).with { $0.surface = .sheet }
        switch fixture.kind {
        case let .fan(config):
            return UKBathroomFanSheet.make(controller: BathroomFanController(config: config, store: fixture.store, caller: caller), accessory: nil)
        case let .purifier(config):
            return UKAirPurifierSheet.make(controller: AirPurifierController(config: config, store: fixture.store, caller: caller), accessory: nil)
        case .humidifier:
            return UKHumidifierSheet.make(config: HumidifierConfig.all[0], store: fixture.store, caller: caller, storage: GalleryScheduleStore(), context: context,
                                          initialTab: tab, accessory: nil)
        case .grill:
            return UKGrillSheet.make(controller: GrillController(store: fixture.store, caller: caller), accessory: nil)
        }
    }

    private func logger(for fixture: RoomDeviceFixture) -> LoggingResponder {
        LoggingResponder(RoomDeviceGalleryRecorder().caller(for: fixture.store))
    }

    func testEveryDeviceSheetTakesInputAndSendsCalls() {
        var sentSomewhere = 0
        for fixture in RoomDeviceFixture.all() {
            let log = logger(for: fixture)
            let modal = sheet(for: fixture, caller: log)
            let window = HostedPage.show(modal, size: HostedDriver.tall)
            hostedSettle(0.4)
            XCTAssertFalse(HostedPage.labels(in: modal.view).isEmpty, "\(fixture.name) draws")
            HostedDriver.useAll(in: modal.view, settle: 0.04)
            hostedSettle(0.6)
            if !log.calls.isEmpty { sentSomewhere += 1 }
            window.isHidden = true
        }
        XCTAssertGreaterThan(sentSomewhere, 0, "using the device sheets calls Home Assistant")
    }

    func testHumidifierTabsSchedulesAndActivityEditor() throws {
        guard let fixture = RoomDeviceFixture.all().first(where: { $0.kind == .humidifier }) else { return XCTFail("no humidifier fixture") }
        for tab in HumidifierTab.allCases {
            let log = logger(for: fixture)
            let modal = sheet(for: fixture, tab: tab, caller: log)
            let window = HostedPage.show(modal, size: HostedDriver.tall)
            hostedSettle(0.5)
            // Use every control, the schedule rows and the activity editor they push included.
            for round in 0..<3 {
                HostedDriver.useAll(in: modal.topViewController?.view ?? modal.view, settle: 0.05)
                hostedSettle(0.3)
                if modal.viewControllers.count > 1 {
                    HostedDriver.useAll(in: modal.topViewController!.view, settle: 0.05)
                    _ = modal.popViewController(animated: false)
                } else if round > 0 { break }
            }
            let content = Self.find(UKHumidifierContent.self, in: modal)
            if let content {
                for index in 0..<HumidifierTab.allCases.count { HostedDriver.pickTab(content.tabBar, index) }
            }
            window.isHidden = true
        }
    }

    private static func find<T: UIViewController>(_ type: T.Type, in controller: UIViewController) -> T? {
        if let match = controller as? T { return match }
        for child in controller.children { if let found = find(type, in: child) { return found } }
        for page in (controller as? UINavigationController)?.viewControllers ?? [] { if let found = find(type, in: page) { return found } }
        return nil
    }

    // MARK: Rooms

    func testEveryRoomPageOpensItsCardSheetsAndTheirControls() {
        let store = RoomsFixtures.store()
        let recorder = GalleryServiceRecorder(store: store)
        let log = LoggingResponder(RoomsGalleryCaller(recorder: recorder, bedroom: BedroomGalleryRecorder(store: store)))
        let context = UKGalleryChrome.context(store: store, caller: log)
        var sheets = 0
        for page in RoomsConfig.pages {
            let room = UKRoomViewController(page: page, context: context, viewer: .resident1)
            let nav = UINavigationController(rootViewController: room)
            let window = HostedPage.show(nav, size: HostedDriver.tall)
            hostedSettle(0.5)
            XCTAssertFalse(HostedPage.labels(in: room.view).isEmpty, "\(page.id) draws")
            let controls = HostedDriver.controls(in: room.view)
            for control in controls.prefix(14) {
                control.sendActions(for: .touchUpInside)
                hostedSettle(0.35)
                let top = HostedDriver.topmost(nav)
                if top !== nav {
                    sheets += 1
                    HostedDriver.useAll(in: (top as? UINavigationController)?.topViewController?.view ?? top.view, settle: 0.04)
                    hostedSettle(0.2)
                    top.dismiss(animated: false)
                    hostedSettle(0.2)
                }
            }
            window.isHidden = true
        }
        XCTAssertGreaterThan(sheets, 3, "room cards open sheets")
    }
}
