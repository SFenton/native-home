import Foundation
import HassTestSupport
import Testing
@testable import HassCore

// MARK: - Room device source: reads, gesture guards and the activity draft

/// Every gesture the room device source accepts or refuses, per device model, and the draft's guards.
@MainActor @Suite
final class ServerUIRoomDeviceSourceBranchTests {
    /// Fired between gestures: a gesture stays pending until Home Assistant answers or the optimistic value expires.
    private let scheduler = ManualScheduler()
    private typealias Failure = ServerUIRoomDeviceSource.Failure

    private func humidifier(tank: String = "off", mode: String = "Manual", power: String = "on", options: [String]? = nil)
        throws -> (ServerUIRoomDeviceSource, HumidifierConfig, EntityStore, RecordingCaller) {
        let config = try DeviceLaneFixture.humidifier()
        let store = makeStore([
            config.powerEntityId: power, config.modeEntityId: mode, config.mistLevelEntityId: "5", config.targetHumidityEntityId: "50",
            config.warmLevelEntityId: "0", config.timerMinutesEntityId: "0", config.displayEntityId: "on",
            config.tankRemovedEntityId: tank, config.waterLowEntityId: "off", config.scheduleEnabledEntityId: "off",
            config.scheduleEntityId: "off", config.vacationModeEntityId: "off", config.currentHumidityEntityId: "44",
            config.currentTemperatureEntityId: "21", config.timerRemainingEntityId: "12"
        ], attributes: options.map { [config.modeEntityId: ["options": .array($0.map(JSONValue.string))]] } ?? [:])
        let caller = RecordingCaller()
        return (ServerUIRoomDeviceSource(descriptor: .humidifier(config), store: store, caller: caller, scheduler: scheduler), config, store, caller)
    }

    // MARK: Reads

    @Test func stateTextAndAvailabilityFollowEachDeviceModel() throws {
        let (source, config, store, _) = try humidifier()
        #expect(!source.stateText.isEmpty)
        #expect(!source.isUnavailable)
        set(store, config.powerEntityId, "unavailable")
        #expect(source.isUnavailable)

        let fan = DeviceLaneFixture.fan
        let fanSource = ServerUIRoomDeviceSource(descriptor: .fan(fan), store: makeStore([
            fan.powerEntityId: "off", fan.lockEntityId: "off", fan.pendingEntityId: "off"
        ]), caller: RecordingCaller())
        #expect(!fanSource.stateText.isEmpty)
        #expect(!fanSource.isUnavailable)

        let purifierConfig = AirPurifierConfig(roomTitle: "Synthetic Room", pm25EntityId: "sensor.demo_pm25", aqiEntityId: "sensor.demo_aqi",
                                               autoModeEntityId: "select.demo_auto", fanEntityId: "fan.demo_purifier", modeEntityId: "select.demo_mode")
        let purifierStore = makeStore(["select.demo_mode": "Manual", "select.demo_auto": "Default", "fan.demo_purifier": "on",
                                       "sensor.demo_pm25": "3", "sensor.demo_aqi": "12"])
        let purifier = ServerUIRoomDeviceSource(descriptor: .purifier(purifierConfig), store: purifierStore, caller: RecordingCaller())
        #expect(purifier.stateText.contains("•"))
        #expect(!purifier.isUnavailable)
        for id in ["select.demo_mode", "select.demo_auto", "fan.demo_purifier"] { set(purifierStore, id, "unavailable") }
        #expect(purifier.isUnavailable)

        let grill = try JSONDecoder().decode(GrillConfig.self, from: Data("""
            {"title":"Synthetic Grill","roomTitle":"Synthetic Room","stateEntityId":"sensor.demo_grill","details":[]}
            """.utf8))
        let grillStore = makeStore(["sensor.demo_grill": "cooking"])
        let grillSource = ServerUIRoomDeviceSource(descriptor: .grill(grill), store: grillStore, caller: RecordingCaller())
        #expect(!grillSource.stateText.isEmpty)
        #expect(!grillSource.isUnavailable)
        set(grillStore, grill.stateEntityId, "unavailable")
        #expect(grillSource.isUnavailable)
    }

    @Test func infoItemsExistOnlyForAHumidifierWithEveryReadingPresent() throws {
        let (source, _, _, _) = try humidifier()
        #expect(source.infoItem(.humidity) != nil)
        #expect(source.infoItem(.temperature) != nil)
        #expect(source.infoItem(.timer) != nil)
        #expect(source.infoItem(.mode) != nil)

        let fan = DeviceLaneFixture.fan
        let fanSource = ServerUIRoomDeviceSource(descriptor: .fan(fan), store: makeStore([:]), caller: RecordingCaller())
        #expect(fanSource.infoItem(.water) == nil, "only a humidifier has info items")
    }

    @Test func aTextModeOrAMistReadingWithoutANumberHasNoItem() throws {
        let (source, config, store, _) = try humidifier(mode: "Unlisted")
        #expect(source.infoItem(.mode) == nil, "an unlisted mode is not shown")
        set(store, config.mistLevelEntityId, "high")
        #expect(source.infoItem(.mist) == nil)
        set(store, config.mistLevelEntityId, "4")
        set(store, config.timerRemainingEntityId, "soon")
        #expect(source.infoItem(.timer) == nil)
    }

    // MARK: Gestures

    @Test func aKindFromAnotherModelIsRefused() throws {
        let (source, _, _, caller) = try humidifier()
        #expect(throws: Failure.invalidIntent) { try source.perform(.fanPower, intent: .setOn(true)) }
        #expect(throws: Failure.invalidIntent) { try source.perform(.humidifierPower, intent: .number(1)) }
        #expect(caller.calls.isEmpty)
    }

    @Test func humidifierGesturesCallTheirServicesAndRefuseBadValues() async throws {
        let (source, config, _, caller) = try humidifier()
        try source.perform(.humidifierPower, intent: .setOn(true))
        await source.commands.waitForCalls(); scheduler.fireAll()
        #expect(caller.calls.isEmpty, "power is already on")
        try source.perform(.humidifierDisplay, intent: .setOn(false))
        await source.commands.waitForCalls(); scheduler.fireAll()
        try source.perform(.humidifierMode, intent: .choose("Sleep"))
        await source.commands.waitForCalls(); scheduler.fireAll()
        #expect(throws: Failure.invalidIntent) { try source.perform(.humidifierMode, intent: .choose("Turbo")) }
        #expect(caller.calls.count == 2)
        #expect(throws: Failure.invalidIntent) { try source.perform(.humidifierPresets, intent: .choose("04")) }
        #expect(throws: Failure.invalidIntent) { try source.perform(.humidifierPresets, intent: .choose("10")) }
        #expect(throws: Failure.invalidIntent) { try source.perform(.humidifierWarm, intent: .choose("4")) }
        #expect(throws: Failure.invalidIntent) { try source.perform(.humidifierMist, intent: .number(10)) }
        #expect(throws: Failure.invalidIntent) { try source.perform(.humidifierTarget, intent: .number(85)) }
        #expect(throws: Failure.invalidIntent) { try source.perform(.humidifierTimer, intent: .number(721)) }
        #expect(throws: Failure.invalidIntent) { try source.perform(.humidifierTimer, intent: .number(.nan)) }
        _ = config
    }

    @Test func humidifierLevelsTimerAndTargetNeedTheRightMode() async throws {
        let (source, config, store, caller) = try humidifier()
        try source.perform(.humidifierPresets, intent: .choose("7"))
        await source.commands.waitForCalls(); scheduler.fireAll()
        #expect(caller.calls.isEmpty == false)
        try source.perform(.humidifierWarm, intent: .choose("2"))
        await source.commands.waitForCalls(); scheduler.fireAll()
        try source.perform(.humidifierMist, intent: .number(6))
        await source.commands.waitForCalls(); scheduler.fireAll()
        try source.perform(.humidifierTimer, intent: .number(30))
        await source.commands.waitForCalls(); scheduler.fireAll()
        #expect(throws: Failure.unavailable) { try source.perform(.humidifierTarget, intent: .number(60)) }
        set(store, config.modeEntityId, "Sleep")
        #expect(throws: Failure.unavailable) { try source.perform(.humidifierPresets, intent: .choose("3")) }
        #expect(throws: Failure.unavailable) { try source.perform(.humidifierWarm, intent: .choose("1")) }
        #expect(throws: Failure.unavailable) { try source.perform(.humidifierMist, intent: .number(3)) }
        #expect(throws: Failure.unavailable) { try source.perform(.humidifierDisplay, intent: .setOn(true)) }
    }

    @Test func aMissingOrBlockedHumidifierRefusesEveryCommand() throws {
        let (blocked, _, _, caller) = try humidifier(tank: "on")
        #expect(throws: Failure.unavailable) { try blocked.perform(.humidifierMode, intent: .choose("Manual")) }
        #expect(throws: Failure.unavailable) { try blocked.perform(.humidifierDisplay, intent: .setOn(false)) }
        #expect(throws: Failure.unavailable) { try blocked.perform(.humidifierWarm, intent: .choose("1")) }
        #expect(throws: Failure.unavailable) { try blocked.perform(.humidifierTimer, intent: .number(10)) }
        #expect(throws: Failure.unavailable) { try blocked.perform(.humidifierTarget, intent: .number(60)) }
        let (off, _, _, _) = try humidifier(power: "unavailable")
        #expect(throws: Failure.unavailable) { try off.perform(.humidifierPower, intent: .setOn(true)) }
        #expect(caller.calls.isEmpty)
    }

    @Test func schedulingNeedsLoadedStorage() async throws {
        let (source, _, _, _) = try humidifier()
        #expect(throws: Failure.scheduleUnavailable) { try source.perform(.humidifierScheduling, intent: .setOn(true)) }
        await #expect(throws: Failure.scheduleUnavailable) { try await source.loadSchedules() }
        #expect(throws: Failure.scheduleUnavailable) { try source.deletion(for: "any") }
        #expect(!source.schedulesLoadRequested)
    }

    @Test func aLoadedScheduleTogglesAndDeletesOnlyTheRuleThatTicketNamed() async throws {
        let config = try DeviceLaneFixture.humidifier()
        let storage = MemoryScheduleStore([HassSchedule(id: config.scheduleId, name: "Synthetic")])
        let store = makeStore([
            config.powerEntityId: "on", config.modeEntityId: "Manual", config.mistLevelEntityId: "5", config.targetHumidityEntityId: "50",
            config.warmLevelEntityId: "0", config.timerMinutesEntityId: "0", config.displayEntityId: "on",
            config.tankRemovedEntityId: "off", config.waterLowEntityId: "off", config.scheduleEnabledEntityId: "off",
            config.scheduleEntityId: "off", config.vacationModeEntityId: "off"
        ])
        let source = ServerUIRoomDeviceSource(descriptor: .humidifier(config), store: store, caller: RecordingCaller(), storage: storage,
                                              scheduler: scheduler)
        #expect(throws: Failure.scheduleUnavailable) { try source.deletion(for: "x") }
        try await source.loadSchedules()
        #expect(source.schedulesLoadRequested)
        #expect(throws: Failure.staleConfirmation) { try source.deletion(for: "missing") }
        let draft = ServerUIHumidifierActivityDraft(source: source, rule: .new(id: "night", mode: .manual), isNew: true)
        draft.value.label = "Night"
        #expect(draft.canSave && !draft.isBusy)
        #expect(await draft.save())
        await source.schedules?.waitForCalls(); scheduler.fireAll()
        let ticket = try source.deletion(for: "night")
        #expect(ticket.descriptor == source.descriptor)
        try await source.delete(ticket)
        #expect(source.schedules?.rules.isEmpty == true)
    }

    @Test func aDraftOverALoadedScheduleExplainsAFailedSave() async throws {
        let config = try DeviceLaneFixture.humidifier()
        let storage = MemoryScheduleStore([HassSchedule(id: config.scheduleId, name: "Synthetic")])
        let store = makeStore([config.powerEntityId: "on", config.modeEntityId: "Manual", config.scheduleEnabledEntityId: "off",
                               config.scheduleEntityId: "off", config.vacationModeEntityId: "off"])
        let source = ServerUIRoomDeviceSource(descriptor: .humidifier(config), store: store, caller: RecordingCaller(), storage: storage,
                                              scheduler: scheduler)
        let draft = ServerUIHumidifierActivityDraft(source: source, rule: .new(id: "night", mode: .manual), isNew: true)
        #expect(!draft.canSave, "nothing is loaded yet")
        #expect(await draft.save() == false)
        try await source.loadSchedules()
        draft.value.label = "Night"
        storage.failUpdate = true
        #expect(await draft.save() == false)
        #expect(draft.error != nil)
        #expect(draft.conflict == nil)
        draft.value.label = String(repeating: "x", count: 41)
        #expect(!draft.canSave, "a label is at most forty characters")
    }
}
