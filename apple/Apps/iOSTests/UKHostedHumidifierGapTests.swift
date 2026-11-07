import HassCore
import UIKit
import XCTest
@testable import HassUI

/// The humidifier sheet where things are missing or go wrong: no target humidity set, no timer running, no scheduled activities, a
/// schedule that cannot be read, and deleting an activity.
@MainActor
final class UKHostedHumidifierGapTests: DemoHouseTestCase {
    private struct Unreadable: Error {}

    /// A schedule helper that cannot be read.
    private final class BrokenStore: HassScheduleStoring {
        func listSchedules() async throws -> [HassSchedule] { throw Unreadable() }
        func updateSchedule(_ message: [String: JSONValue]) async throws -> HassSchedule { throw Unreadable() }
        func userIsAdmin() async throws -> Bool { true }
    }

    private func open(tab: HumidifierTab, states: [EntityState]? = nil, storage: any HassScheduleStoring) -> (UKHassModalController, LoggingResponder, UIWindow) {
        let store = EntityStore()
        store.replaceAll(states ?? RoomDeviceFixture.humidifierStates(power: "on", tankRemoved: false), freshness: .live)
        let log = LoggingResponder(RoomDeviceGalleryRecorder().caller(for: store))
        let context = UKGalleryChrome.context(store: store, caller: log).with { $0.surface = .sheet }
        let modal = UKHumidifierSheet.make(config: HumidifierConfig.all[0], store: store, caller: log, storage: storage, context: context, initialTab: tab, accessory: nil)
        let window = HostedPage.show(modal, size: HostedDriver.tall)
        FeatureHost.settle(0.6)
        return (modal, log, window)
    }

    func testWithoutAValidTargetTheSheetWarnsBeforeAutoHumidityIsRelied() {
        var states = RoomDeviceFixture.humidifierStates(power: "on", tankRemoved: false)
        let target = HumidifierConfig.all[0].targetHumidityEntityId
        states.removeAll { $0.entityId == target }
        states.append(EntityState(entityId: target, state: "unknown"))
        let (modal, _, window) = open(tab: .controls, states: states, storage: GalleryScheduleStore())
        defer { window.isHidden = true }
        XCTAssertTrue(HostedPage.labels(in: modal.view).contains("Choose a target before relying on Auto Humidity."),
                      "the missing target is explained; saw \(HostedPage.labels(in: modal.view).prefix(14))")
    }

    func testNoRunningTimerHidesTheCancelTimerButton() {
        var states = RoomDeviceFixture.humidifierStates(power: "on", tankRemoved: false)
        let remaining = HumidifierConfig.all[0].timerRemainingEntityId
        states.removeAll { $0.entityId == remaining }
        states.append(EntityState(entityId: remaining, state: "0"))
        let (modal, _, window) = open(tab: .controls, states: states, storage: GalleryScheduleStore())
        defer { window.isHidden = true }
        let cancel = FeatureHost.view("humidifier.cancelTimer", in: modal.view)
        XCTAssertNil(cancel, "with no timer counting down there is nothing to cancel")
    }

    func testAnEmptyScheduleSaysSoAndInvitesTheFirstActivity() {
        let (modal, _, window) = open(tab: .schedules, storage: GalleryScheduleStore(rules: []))
        defer { window.isHidden = true }
        XCTAssertTrue(HostedPage.until(4) { HostedPage.labels(in: modal.view).contains("No activities yet. Add morning, evening, or overnight profiles.") },
                      "an empty schedule explains itself; saw \(HostedPage.labels(in: modal.view).prefix(12))")
        XCTAssertNotNil(FeatureHost.view("humidifier.addActivity", in: modal.view), "Add Activity is offered")
    }

    func testAnUnreadableScheduleShowsAnErrorInsteadOfSpinningForever() {
        let (modal, _, window) = open(tab: .schedules, storage: BrokenStore())
        defer { window.isHidden = true }
        XCTAssertTrue(HostedPage.until(4) { HostedPage.labels(in: modal.view).contains { $0.contains("Could not load scheduled activities") } },
                      "the failure is shown; saw \(HostedPage.labels(in: modal.view).prefix(12))")
    }

    func testDeletingAnActivityAsksFirstThenRemovesItAndClosesTheEditor() throws {
        let (modal, _, window) = open(tab: .schedules, storage: GalleryScheduleStore())
        defer { window.isHidden = true }
        XCTAssertTrue(HostedPage.until(4) { FeatureHost.view("humidifier.activity.Night", in: modal.view) != nil }, "the Night activity is listed")
        let row = try XCTUnwrap(FeatureHost.view("humidifier.activity.Night", in: modal.view) as? UIControl)
        row.sendActions(for: .touchUpInside)
        XCTAssertTrue(HostedPage.until(4) { modal.viewControllers.count > 1 }, "the activity opens in its editor")
        let editor = try XCTUnwrap(modal.topViewController)
        let delete = try XCTUnwrap(FeatureHost.view("activity.delete", in: editor.view) as? UIControl, "an existing activity can be deleted")
        delete.sendActions(for: .touchUpInside)
        FeatureHost.settle(0.4)
        XCTAssertEqual(modal.viewControllers.count, 2, "nothing is deleted before the person confirms")
        let sheet = try XCTUnwrap(FeatureHost.alert(on: editor), "a confirmation appears")
        let confirm = try XCTUnwrap(sheet.actions.first { $0.style == .destructive }, "a destructive confirm action")
        XCTAssertTrue(FeatureHost.answer(sheet, confirm.title))
        XCTAssertTrue(HostedPage.until(5) { modal.viewControllers.count == 1 }, "confirming deletes the activity and leaves the editor")
        XCTAssertTrue(HostedPage.until(4) { FeatureHost.view("humidifier.activity.Night", in: modal.view) == nil }, "Night is gone from the list")
        XCTAssertNotNil(FeatureHost.view("humidifier.activity.Evening", in: modal.view), "the other activity stays")
    }

    func testTheConnectionConvenienceBuildsTheSameSheet() throws {
        let signedIn = try FeatureHost.signedIn()
        let modal = UKHumidifierSheet.make(config: HumidifierConfig.all[0], connection: signedIn.connection, context: signedIn.context)
        let window = HostedPage.show(modal, size: HostedDriver.tall)
        defer { window.isHidden = true }
        FeatureHost.settle(0.5)
        XCTAssertNotNil(FeatureHost.view("device.sheet.humidifier", in: modal.view), "the humidifier sheet opens on the live connection")
    }
}
