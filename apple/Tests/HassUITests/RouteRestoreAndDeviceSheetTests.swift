import Foundation
import HassCore
@testable import HassUI
import Testing
import HassTestSupport

/// Which pushed pages a cold launch puts back, and which device sheet a room card opens.
@MainActor
@Suite(.demoHouse)
struct RouteRestoreAndDeviceSheetTests {
    // MARK: Route restore

    @Test func routesAreRestoredOnlyWithinThirtyMinutesOfTheLastUse() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(RouteRestore.isFresh(savedAt: now.timeIntervalSince1970 - 60, now: now))
        #expect(RouteRestore.isFresh(savedAt: now.timeIntervalSince1970 - RouteRestore.window, now: now), "exactly at the edge still counts")
        #expect(!RouteRestore.isFresh(savedAt: now.timeIntervalSince1970 - RouteRestore.window - 1, now: now))
        #expect(!RouteRestore.isFresh(savedAt: 0, now: now), "never saved")
        #expect(!RouteRestore.isFresh(savedAt: now.timeIntervalSince1970 + 600, now: now), "a clock that went backwards restores nothing")
    }

    @Test func savedRoutesComeBackAsTheyWentAwayAndEmptyStacksAreNotKept() throws {
        let saved: [AppSection: [ShellRoute]] = [
            .home: [.home(.media), .foodSpace("fridge")],
            .chores: [.chores("groceries")],
            .settings: [],
        ]
        let data = try #require(RouteRestore.encode(saved))
        let back = RouteRestore.decode(data)
        #expect(back[.home] == [.home(.media), .foodSpace("fridge")])
        #expect(back[.chores] == [.chores("groceries")])
        #expect(back[.settings] == nil, "an empty stack is not written")
        #expect(RouteRestore.encode([.home: [], .security: []]) == nil, "nothing to keep, no bytes")
    }

    @Test func bytesThatNoLongerDecodeOrNameASectionThatWasRemovedRestoreNothing() throws {
        #expect(RouteRestore.decode(nil).isEmpty)
        #expect(RouteRestore.decode(Data("not json".utf8)).isEmpty, "a route renamed by an update")
        let mixed = try JSONEncoder().encode(["home": [ShellRoute.home(.media)], "retired-section": [ShellRoute.chores("x")]])
        let back = RouteRestore.decode(mixed)
        #expect(back.count == 1 && back[.home] == [.home(.media)], "an unknown section is dropped, the rest stays")
    }

    // MARK: Device sheets

    @Test func aVacuumAndAHumidifierNeedTheConnectionAndOthersDoNot() throws {
        let vacuum = try #require(Vacuums.all.first)
        #expect(RoomDeviceModal.resolve(.vacuum(entityId: vacuum.entityId), hasConnection: false, fan: { _ in nil }) == nil)
        let resolved = try #require(RoomDeviceModal.resolve(.vacuum(entityId: vacuum.entityId), hasConnection: true, fan: { _ in nil }))
        #expect(resolved.id == "vacuum.\(vacuum.entityId)")
        #expect(RoomDeviceModal.resolve(.vacuum(entityId: "vacuum.demo_nobody"), hasConnection: true, fan: { _ in nil }) == nil, "an unknown robot has no sheet")

        let power = HumidifierConfig.all[0].powerEntityId
        #expect(RoomDeviceModal.resolve(.humidifier(powerEntityId: power), hasConnection: false, fan: { _ in nil }) == nil)
        #expect(RoomDeviceModal.resolve(.humidifier(powerEntityId: power), hasConnection: true, fan: { _ in nil })?.id == "humidifier.\(power)")
        #expect(RoomDeviceModal.resolve(.humidifier(powerEntityId: "switch.demo_other"), hasConnection: true, fan: { _ in nil }) == nil)
    }

    @Test func anAirQualityCardOpensItsPurifierAndAGrillOpensTheGrill() throws {
        let pm25 = try #require(AirPurifierConfig.all.first).pm25EntityId
        #expect(RoomDeviceModal.resolve(.airQuality(pm25EntityId: pm25), hasConnection: false, fan: { _ in nil })?.id == "purifier.\(pm25)")
        #expect(RoomDeviceModal.resolve(.airQuality(pm25EntityId: "sensor.demo_unknown"), hasConnection: true, fan: { _ in nil }) == nil)
        #expect(RoomDeviceModal.resolve(.grill(entityId: "x"), hasConnection: false, fan: { _ in nil })?.id == "grill")
    }

    @Test func theDishwasherAndTheBedroomDevicesHaveNoSheetHereWithoutTheirOwner() {
        #expect(RoomDeviceModal.resolve(.dishwasher, hasConnection: true, fan: { _ in nil }) == nil, "generic tiles until its lane lands")
        #expect(RoomDeviceModal.resolve(.wakeLight(statusEntityId: "x"), hasConnection: true, fan: { _ in nil }) == nil, "no bedroom, no wake light sheet")
        #expect(RoomDeviceModal.resolve(.bed(sheet: "alexs-bed", climateEntityId: "x"), hasConnection: true, fan: { _ in nil }) == nil)
    }

    @Test func aBathroomFanSheetIsOnlyOfferedWhenThePageHasItsController() {
        #expect(RoomDeviceModal.resolve(.bathroomFan(powerEntityId: BathroomFanConfig.all[0].powerEntityId), hasConnection: false,
                                        fan: { _ in nil }) == nil)
    }
}
