import HassCore
import UIKit
import XCTest
@testable import HassUI

/// The wake-light and bed-side sheets on the gallery's fixture bedroom, opened and used: tabs, alarm switches, the alarm editor,
/// temperature steppers, special modes and the calls they send.
@MainActor
final class UKHostedBedroomSheetTests: DemoHouseTestCase {
    private struct Room {
        let devices: BedroomDevices
        let log: LoggingResponder
        let context: UKContext
        let store: EntityStore
    }

    private func room(_ scenario: BedroomFixtures.Scenario = .default) -> Room {
        let store = EntityStore()
        store.replaceAll(BedroomFixtures.states(scenario), freshness: .live)
        let log = LoggingResponder(BedroomGalleryRecorder(store: store))
        let devices = BedroomDevices(store: store, caller: log)
        return Room(devices: devices, log: log, context: UKGalleryChrome.context(store: store, caller: log), store: store)
    }

    private func show(_ modal: UKHassModalController) -> UIWindow {
        let window = HostedPage.show(modal, size: HostedDriver.tall)
        hostedSettle(0.4)
        return window
    }

    // MARK: Wake light

    func testWakeLightTabsShowAlarmsAndDefaults() throws {
        let room = room()
        let modal = UKWakeLightSheet.make(devices: room.devices, context: room.context)
        let window = show(modal)
        defer { window.isHidden = true }
        let texts = HostedPage.labels(in: modal.view)
        XCTAssertTrue(texts.contains("Wake Alarm Schedule"), "the Alarms tab lists the schedule; saw \(texts.prefix(10))")
        XCTAssertTrue(texts.contains("Add Wake Alarm"))
        for index in 0..<WakeLightSheet.Tab.allCases.count {
            let content = try XCTUnwrap(Self.find(UKWakeLightContent.self, in: modal))
            HostedDriver.pickTab(content.tabBar, index)
            XCTAssertEqual(content.currentTab, WakeLightSheet.Tab.allCases[index])
        }
    }

    func testWakeAlarmSwitchesSaveThroughTheWakeLightCommand() {
        let room = room()
        let modal = UKWakeLightSheet.make(devices: room.devices, context: room.context)
        let window = show(modal)
        defer { window.isHidden = true }
        let switches = HostedDriver.controls(UISwitch.self, in: modal.view).filter { ($0.accessibilityIdentifier ?? "").hasPrefix("wake.alarm.") }
        XCTAssertFalse(switches.isEmpty, "the fixture has alarms with switches")
        for toggle in switches { HostedDriver.use(toggle) }
        hostedSettle(0.8)
        XCTAssertTrue(room.log.calls.contains("wake_light.command"), "an alarm switch sends a wake_light command; got \(room.log.calls)")
        XCTAssertTrue(room.log.data.contains { ($0["operation"] as? String).map { ["upsert_alarm", "link_alarm"].contains($0) } ?? false },
                      "the command names an operation")
    }

    func testAddWakeAlarmOpensTheEditorAndSaves() throws {
        let room = room()
        let modal = UKWakeLightSheet.make(devices: room.devices, context: room.context)
        let window = show(modal)
        defer { window.isHidden = true }
        let add = try XCTUnwrap(HostedDriver.control("wake.add", in: modal.view), "Add Wake Alarm is a button")
        add.sendActions(for: .touchUpInside)
        hostedSettle(0.5)
        let editor = try XCTUnwrap(modal.topViewController as? UKWakeLightEditor, "Add opens the editor")
        XCTAssertEqual(editor.navigationItem.title, editor.pageTitle)
        HostedDriver.useAll(in: editor.view, settle: 0.08)
        hostedSettle(0.4)
        // Save is the nav bar's action.
        if let save = editor.navigationItem.rightBarButtonItem ?? editor.navigationItem.leftBarButtonItem, let action = save.primaryAction {
            action.performWithSender(nil, target: nil)
        }
        hostedSettle(0.8)
        XCTAssertNotNil(modal.view.window)
    }

    func testEditingAnExistingAlarmAndTheStopButtonWhileRinging() throws {
        let room = room(.ringing)
        let modal = UKWakeLightSheet.make(devices: room.devices, context: room.context)
        let window = show(modal)
        defer { window.isHidden = true }
        if let stop = HostedDriver.control("wake.stop", in: modal.view) {
            stop.sendActions(for: .touchUpInside)
            hostedSettle(0.6)
            XCTAssertTrue(room.log.calls.contains("wake_light.command"), "Stop Wake-Light Episode sends a command; got \(room.log.calls)")
        }
        let open = HostedDriver.controls(in: modal.view).first { ($0.accessibilityIdentifier ?? "").hasPrefix("wake.alarm.") && !($0.accessibilityIdentifier ?? "").contains(".enabled") && !($0.accessibilityIdentifier ?? "").contains(".link") && !($0.accessibilityIdentifier ?? "").contains(".open") }
        let row = try XCTUnwrap(open, "an alarm row opens its editor")
        row.sendActions(for: .touchUpInside)
        hostedSettle(0.5)
        let editor = try XCTUnwrap(modal.topViewController as? UKWakeLightEditor)
        HostedDriver.useAll(in: editor.view, settle: 0.08)
        hostedSettle(0.3)
    }

    func testWakeSheetInEveryScenarioAndEveryTabTakesInput() throws {
        for scenario in BedroomFixtures.Scenario.allCases {
            for tab in WakeLightSheet.Tab.allCases {
                let room = room(scenario)
                let modal = UKWakeLightSheet.make(devices: room.devices, initialTab: tab, context: room.context)
                let window = show(modal)
                HostedDriver.useAll(in: modal.view, settle: 0.03)
                hostedSettle(0.3)
                window.isHidden = true
            }
        }
    }

    // MARK: Bed side

    func testBedSideSheetsOnEveryTabTakeInput() throws {
        for scenario in BedroomFixtures.Scenario.allCases {
            for bed in MasterBedroom.beds {
                for tab in BedSideSheet.Tab.allCases {
                    let room = room(scenario)
                    let side = try XCTUnwrap(room.devices.beds.first { $0.config.side == bed.side }).config.side
                    let modal = UKBedSideSheet.make(devices: room.devices, side: side, initialTab: tab, context: room.context)
                    let window = show(modal)
                    XCTAssertFalse(HostedPage.labels(in: modal.view).isEmpty, "\(bed.id) \(tab) draws text")
                    HostedDriver.useAll(in: modal.view, settle: 0.03)
                    hostedSettle(0.3)
                    window.isHidden = true
                }
            }
        }
    }

    func testBedTemperatureStepsSendTheLevelScript() throws {
        let room = room()
        let bed = MasterBedroom.beds[0]
        let modal = UKBedSideSheet.make(devices: room.devices, side: bed.side, initialTab: .temperature, context: room.context)
        let window = show(modal)
        defer { window.isHidden = true }
        let used = HostedDriver.useAll(in: modal.view, settle: 0.1)
        hostedSettle(0.8)
        XCTAssertGreaterThan(used, 0, "the temperature tab has controls")
        XCTAssertFalse(room.log.calls.isEmpty, "using the temperature controls calls Home Assistant; got \(room.log.calls)")
    }

    func testBedAlarmsTabOpensDayPagesAndTheAlarmEditor() throws {
        let room = room()
        let bed = MasterBedroom.beds[0]
        let modal = UKBedSideSheet.make(devices: room.devices, side: bed.side, initialTab: .alarms, context: room.context)
        let window = show(modal)
        defer { window.isHidden = true }
        for control in HostedDriver.controls(in: modal.view) {
            guard ((control.accessibilityIdentifier ?? "") + (control.accessibilityLabel ?? "")).lowercased().contains("alarm") || control is UIButton else { continue }
            if control is UISwitch { continue }
            control.sendActions(for: .touchUpInside)
            hostedSettle(0.3)
            if let pushed = modal.topViewController, pushed is UKBedAlarmDayPage || pushed is UKBedAlarmEditor {
                HostedDriver.useAll(in: pushed.view, settle: 0.05)
                if modal.viewControllers.count > 1 { _ = modal.popViewController(animated: false) }
                hostedSettle(0.2)
            }
        }
        XCTAssertNotNil(modal.view.window)
    }

    private static func find<T: UIViewController>(_ type: T.Type, in controller: UIViewController) -> T? {
        if let match = controller as? T { return match }
        for child in controller.children { if let found = find(type, in: child) { return found } }
        for page in (controller as? UINavigationController)?.viewControllers ?? [] { if let found = find(type, in: page) { return found } }
        return nil
    }
}
