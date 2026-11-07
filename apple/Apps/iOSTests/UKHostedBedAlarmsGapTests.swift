import HassCore
import UIKit
import XCTest
@testable import HassUI

/// A bed side's Alarms tab when Home Assistant has no alarm schedule, and when it has an empty one.
@MainActor
final class UKHostedBedAlarmsGapTests: DemoHouseTestCase {
    private func open(states: [EntityState]) -> (UKHassModalController, UIWindow) {
        let store = EntityStore()
        store.replaceAll(states, freshness: .live)
        let log = LoggingResponder(BedroomGalleryRecorder(store: store))
        let devices = BedroomDevices(store: store, caller: log)
        let context = UKGalleryChrome.context(store: store, caller: log)
        let modal = UKBedSideSheet.make(devices: devices, side: MasterBedroom.beds[0].side, initialTab: .alarms, context: context)
        let window = HostedPage.show(modal, size: HostedDriver.tall)
        FeatureHost.settle(0.6)
        return (modal, window)
    }

    func testMissingScheduleDataIsExplainedInsteadOfShowingNoAlarms() {
        var states = BedroomFixtures.states(.default)
        states.removeAll { $0.entityId == MasterBedroom.scheduleEntityId }
        let (modal, window) = open(states: states)
        defer { window.isHidden = true }
        XCTAssertTrue(HostedPage.labels(in: modal.view).contains("Home Assistant alarm schedule data is unavailable."),
                      "saw \(HostedPage.labels(in: modal.view).prefix(12))")
    }

    func testAnEmptyScheduleInvitesTheFirstAlarm() {
        var states = BedroomFixtures.states(.default)
        states.removeAll { $0.entityId == MasterBedroom.scheduleEntityId }
        let emptyWeek: JSONValue = .object(Dictionary(uniqueKeysWithValues: Weekday.allCases.map { ($0.rawValue, JSONValue.object(["alarms": .array([])])) }))
        states.append(EntityState(entityId: MasterBedroom.scheduleEntityId, state: "ok", attributes: ["left": emptyWeek, "right": emptyWeek]))
        let (modal, window) = open(states: states)
        defer { window.isHidden = true }
        XCTAssertTrue(HostedPage.labels(in: modal.view).contains("No alarms yet. Add one to choose days and a time."),
                      "saw \(HostedPage.labels(in: modal.view).prefix(12))")
    }
}
