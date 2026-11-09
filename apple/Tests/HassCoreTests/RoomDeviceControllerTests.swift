import Foundation
@testable import HassCore
import HassTestSupport
import Testing

/// Air purifier and grill sheets: what each tile sends and shows (web `AirQualityModalContent.tsx`,
/// `GrillModalContent.tsx`).
@MainActor
@Suite(.demoHouse)
struct AirPurifierControllerTests {
    let office = AirPurifierConfig.all.first { $0.roomTitle == "Office" }!

    func controller(mode: String = "Manual", auto: String = "Default", fan: String = "on", percentage: Double? = 33)
        -> (AirPurifierController, EntityStore, RecordingCaller, ManualScheduler)
    {
        var fanAttributes: [String: JSONValue] = [:]
        if let percentage { fanAttributes["percentage"] = .number(percentage) }
        let store = makeStore([
            office.modeEntityId: mode, office.autoModeEntityId: auto, office.fanEntityId: fan,
            office.pm25EntityId: "3", office.aqiEntityId: "12.0",
        ], attributes: [office.fanEntityId: fanAttributes, office.pm25EntityId: ["unit_of_measurement": .string("µg/m³")]])
        let caller = RecordingCaller()
        let scheduler = ManualScheduler()
        return (AirPurifierController(config: office, store: store, caller: caller, scheduler: scheduler), store, caller, scheduler)
    }

    @Test func entityIdsDeriveFromThePM25Sensor() {
        #expect(office.modeEntityId == "select.demo_office_1_fan_mode")
        #expect(office.autoModeEntityId == "select.demo_office_1_auto_mode")
        #expect(office.fanEntityId == "fan.demo_office_1_purifier")
        #expect(office.aqiEntityId == "sensor.demo_office_1_air_quality_index")
        let music = AirPurifierConfig.all.first { $0.roomTitle == "Studio" }!
        #expect(music.modeEntityId == "select.demo_sensor_17_fan_mode")
        #expect(AirPurifierConfig.all.count == 6)
        #expect(AirPurifierConfig.forPM25Entity("sensor.demo_sensor_17") == music)
        #expect(AirPurifierConfig.forPM25Entity("sensor.demo_kitchen_pm2_5") == nil)
    }

    @Test func aPurifierWithoutAFanIdOffersNoSpeedCalls() async {
        let bare = AirPurifierConfig(roomTitle: "Demo", pm25EntityId: "sensor.demo_unit_pm2_5")
        let caller = RecordingCaller()
        let controller = AirPurifierController(config: bare, store: makeStore([:]), caller: caller, scheduler: ManualScheduler())
        #expect(controller.fanUnavailable)
        controller.selectSpeed(AirPurifierController.speeds[0])
        await controller.commands.waitForCalls()
        #expect(caller.calls.isEmpty)
    }

    @Test func sectionsFollowTheMode() {
        let (manual, _, _, _) = controller(mode: "Manual")
        #expect(manual.showsSpeeds && !manual.showsAutoModes)
        #expect(manual.percentage == "33")
        let (auto, _, _, _) = controller(mode: "Auto")
        #expect(auto.showsAutoModes && !auto.showsSpeeds)
        let (sleep, _, _, _) = controller(mode: "Sleep")
        #expect(!sleep.showsAutoModes && !sleep.showsSpeeds)
    }

    @Test func choicesSendServicesAndHighlightAtOnce() async {
        let (purifier, _, caller, scheduler) = controller(mode: "Manual")
        purifier.selectMode(AirPurifierController.fanModes[2])
        #expect(purifier.mode == "Auto")
        purifier.selectAutoMode(AirPurifierController.autoModes[1])
        #expect(purifier.autoMode == "Quiet")
        purifier.selectSpeed(AirPurifierController.speeds[3])
        #expect(purifier.percentage == "100")
        await purifier.commands.waitForCalls()
        #expect(caller.calls == [
            .init(domain: "select", service: "select_option", data: ["entity_id": "select.demo_office_1_fan_mode", "option": "Auto"]),
            .init(domain: "select", service: "select_option", data: ["entity_id": "select.demo_office_1_auto_mode", "option": "Quiet"]),
            .init(domain: "fan", service: "set_percentage", data: ["entity_id": "fan.demo_office_1_purifier", "percentage": "100"]),
        ])
        scheduler.fireAll()
        #expect(purifier.mode == "Manual", "Reverts without confirmation")
    }

    @Test func unavailableEntitiesDisableTheirTiles() async {
        let (purifier, _, caller, _) = controller(mode: "unavailable", auto: "unknown", fan: "unavailable", percentage: nil)
        #expect(purifier.modeUnavailable && purifier.autoModeUnavailable && purifier.fanUnavailable)
        purifier.selectMode(AirPurifierController.fanModes[0])
        purifier.selectAutoMode(AirPurifierController.autoModes[0])
        purifier.selectSpeed(AirPurifierController.speeds[0])
        await purifier.commands.waitForCalls()
        #expect(caller.calls.isEmpty)
        #expect(purifier.percentage == nil)
    }

    @Test func summaryShowsAQIAndPM25WithUnits() {
        let (purifier, _, _, _) = controller()
        #expect(purifier.summary == "12 • 3 µg/m³")
        #expect(AirPurifierController.metric(nil) == "Unavailable")
        #expect(AirPurifierController.metric(EntityState(entityId: "sensor.demo_x", state: "unavailable")) == "Unavailable")
        #expect(AirPurifierController.metric(EntityState(entityId: "sensor.demo_x", state: "4 µg/m³", attributes: ["unit_of_measurement": .string("µg/m³")])) == "4 µg/m³")
    }
}

@MainActor
@Suite(.demoHouse)
struct GrillControllerTests {
    let grill = GrillConfig.bearGrills

    func controller(state: String = "cooking", keepWarm: String = "off")
        -> (GrillController, EntityStore, RecordingCaller, ManualScheduler)
    {
        let store = makeStore([
            grill.stateEntityId: state,
            grill.details[0].entityId: "165",
            grill.details[1].entityId: "72",
            grill.details[2].entityId: keepWarm,
            grill.details[3].entityId: "on",
        ], attributes: [grill.details[0].entityId: ["unit_of_measurement": .string("°F")],
                        grill.details[1].entityId: ["unit_of_measurement": .string("%")]])
        let caller = RecordingCaller()
        let scheduler = ManualScheduler()
        return (GrillController(config: grill, store: store, caller: caller, scheduler: scheduler), store, caller, scheduler)
    }

    @Test func cardsShowValuesWithUnits() {
        let (controller, _, _, _) = controller()
        #expect(controller.stateText == "Cooking")
        #expect(!controller.isOff)
        #expect(controller.display(grill.details[0]) == .init(value: "165 °F", isActive: false, isUnavailable: false, isActionable: false))
        #expect(controller.display(grill.details[1]).value == "72%")
        #expect(controller.display(grill.details[3]) == .init(value: "On", isActive: true, isUnavailable: false, isActionable: true))
    }

    @Test func switchesFlipWithExplicitServices() async {
        let (controller, _, caller, _) = controller()
        controller.toggle(grill.details[2])
        #expect(controller.display(grill.details[2]).isActive)
        controller.toggle(grill.details[3])
        controller.toggle(grill.details[0])
        await controller.commands.waitForCalls()
        #expect(caller.calls == [
            .init(domain: "switch", service: "turn_on", data: ["entity_id": "switch.demo_enabled_1"]),
            .init(domain: "switch", service: "turn_off", data: ["entity_id": "switch.demo_enabled_2"]),
        ])
    }

    @Test func offOrMissingGrillShowsUnavailable() {
        let (off, _, _, _) = controller(state: "off")
        #expect(off.isOff)
        #expect(off.stateText == "Off")
        let (missing, _, _, _) = controller(state: "unavailable", keepWarm: "unavailable")
        #expect(missing.stateText == "Unavailable")
        #expect(missing.display(grill.details[2]) == .init(value: "Unavailable", isActive: false, isUnavailable: true, isActionable: false))
        let empty = GrillController(store: EntityStore(), caller: RecordingCaller(), scheduler: ManualScheduler())
        #expect(empty.stateText == "Unavailable")
        #expect(empty.display(grill.details[0]).value == "Unavailable")
    }

    @Test func sharedStateHelpers() {
        #expect(StateText.titleCase("heat_cool") == "Heat Cool")
        #expect(DeviceState.binaryFlag(nil) == "unavailable")
        #expect(DeviceState.binaryFlag("unknown") == "unavailable")
        #expect(DeviceState.binaryFlag("idle") == "off")
        #expect(DeviceState.compact(nil) == "Unavailable")
        #expect(DeviceState.compact(EntityState(entityId: "binary_sensor.demo_door", state: "on")) == "Active")
        #expect(DeviceState.compact(EntityState(entityId: "binary_sensor.demo_door", state: "off")) == "Clear")
        #expect(DeviceState.compact(EntityState(entityId: "switch.demo_x", state: "on")) == "On")
        #expect(DeviceState.number(EntityState(entityId: "sensor.demo_x", state: "nan")) == nil)
    }
}
