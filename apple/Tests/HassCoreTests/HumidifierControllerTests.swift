import Foundation
@testable import HassCore
import HassTestSupport
import Testing

/// The humidifier's controls (web `HumidifierModalContent.tsx` `useHumidifierController`).
@MainActor
@Suite(.demoHouse)
struct HumidifierControllerTests {
    let h = HumidifierConfig.all[0]

    func controller(_ overrides: [String: String] = [:], attributes: [String: [String: JSONValue]] = [:])
        -> (HumidifierController, EntityStore, RecordingCaller, ManualScheduler)
    {
        var states: [String: String] = [
            h.powerEntityId: "on", h.modeEntityId: "Manual", h.mistLevelEntityId: "5.0", h.targetHumidityEntityId: "50.0",
            h.warmLevelEntityId: "1.0", h.timerMinutesEntityId: "0.0", h.timerRemainingEntityId: "0", h.displayEntityId: "on",
            h.currentHumidityEntityId: "41.4", h.currentTemperatureEntityId: "70.4", h.humidifyingEntityId: "on",
            h.waterLowEntityId: "off", h.tankRemovedEntityId: "off",
        ]
        states.merge(overrides) { _, new in new }
        let store = makeStore(states, attributes: attributes)
        let caller = RecordingCaller()
        let scheduler = ManualScheduler()
        return (HumidifierController(config: h, store: store, caller: caller, scheduler: scheduler), store, caller, scheduler)
    }

    // MARK: Reading

    @Test func readsAndNormalizesLiveValues() {
        let (humidifier, _, _, _) = controller([h.mistLevelEntityId: "12", h.warmLevelEntityId: "-1", h.timerMinutesEntityId: "900"],
                                               attributes: [h.currentTemperatureEntityId: ["unit_of_measurement": .string("°F")]])
        #expect(humidifier.powerOn && !humidifier.isUnavailable && !humidifier.isBlocked)
        #expect(humidifier.mistLevel == 9)
        #expect(humidifier.currentMistLevel == 9)
        #expect(humidifier.warmLevel == 0)
        #expect(humidifier.timerMinutes == 720)
        #expect(humidifier.targetHumidity == 50 && humidifier.targetHumidityValid)
        #expect(humidifier.humidityText == "41%")
        #expect(humidifier.temperatureText == "70°F")
        #expect(humidifier.subtitle == "Humidifying • 41%")
        #expect(humidifier.hint == "Drag the dial to adjust mist output.")
        #expect(humidifier.canSetLevel && humidifier.canTogglePower)
    }

    @Test func invalidOrMissingValuesFallBack() {
        let (humidifier, _, _, _) = controller([h.modeEntityId: "Turbo", h.targetHumidityEntityId: "20", h.mistLevelEntityId: "unknown",
                                                h.currentTemperatureEntityId: "unavailable", h.currentHumidityEntityId: "unknown"])
        #expect(humidifier.mode == .manual)
        #expect(humidifier.targetHumidity == 50 && !humidifier.targetHumidityValid)
        #expect(humidifier.mistLevel == 5)
        #expect(humidifier.currentMistLevel == nil)
        #expect(humidifier.temperatureText == "Unavailable")
        #expect(humidifier.humidityText == "Unavailable")
        let (odd, _, _, _) = controller([h.currentTemperatureEntityId: "warm"])
        #expect(odd.temperatureText == "Warm")
    }

    @Test(arguments: [
        ("tank", "Tank Removed", "Reinsert the water tank to restore controls."),
        ("water", "Water Low", "Refill the tank to restore output controls."),
    ])
    func faultsBlockOutputControls(fault: String, subtitle: String, hint: String) {
        let id = fault == "tank" ? h.tankRemovedEntityId : h.waterLowEntityId
        let (humidifier, _, _, _) = controller([id: "on"])
        #expect(humidifier.fault?.rawValue == fault)
        #expect(humidifier.isBlocked && !humidifier.canSetLevel)
        #expect(humidifier.subtitle == subtitle)
        #expect(humidifier.hint == hint)
        #expect(humidifier.faultMessage != nil)
        #expect(humidifier.canTogglePower, "Can still turn off")
        let (off, _, _, _) = controller([id: "on", h.powerEntityId: "off"])
        #expect(!off.canTogglePower, "Can't turn on with a fault")
        #expect(off.subtitle == "Off")
    }

    @Test func unavailableAndSleepStates() {
        let (missing, _, _, _) = controller([h.powerEntityId: "unavailable"])
        #expect(missing.isUnavailable && !missing.canTogglePower)
        #expect(missing.subtitle == "Unavailable")
        #expect(missing.hint == "Humidifier controls are unavailable.")
        let (sleep, _, _, _) = controller([h.modeEntityId: "Sleep"])
        #expect(sleep.isSleep && !sleep.canSetLevel)
        #expect(sleep.hint == "Sleep mode controls output automatically.")
        let (off, _, _, _) = controller([h.powerEntityId: "off"])
        #expect(off.hint == nil)
        let (idle, _, _, _) = controller([h.humidifyingEntityId: "off"])
        #expect(idle.subtitle == "On • 41%")
    }

    // MARK: Actions

    @Test func setLevelGoesThroughTheScriptAndZeroTurnsOff() async {
        let (humidifier, _, caller, _) = controller()
        humidifier.setLevel(7)
        #expect(humidifier.mistLevel == 7 && humidifier.powerOn)
        humidifier.setLevel(0)
        #expect(!humidifier.powerOn)
        #expect(humidifier.mistLevel == 7, "Off keeps the saved level")
        humidifier.setLevel(42)
        await humidifier.commands.waitForCalls()
        #expect(caller.calls.map(\.data) == [["level": "7"], ["level": "0"], ["level": "9"]])
        #expect(caller.calls.allSatisfy { $0.service == h.setLevelScriptService })
    }

    @Test func modeWhileOnSelectsAndWhileOffAppliesTheProfile() async {
        let (on, _, onCaller, _) = controller()
        on.setMode(.targetHumidity)
        #expect(on.mode == .targetHumidity)
        await on.commands.waitForCalls()
        #expect(onCaller.calls == [.init(domain: "select", service: "select_option",
                                         data: ["entity_id": "select.demo_mode_1", "option": "Target Humidity"])])

        let (off, _, offCaller, _) = controller([h.powerEntityId: "off"])
        off.setMode(.sleep)
        #expect(off.powerOn && off.mode == .sleep)
        await off.commands.waitForCalls()
        #expect(offCaller.calls == [.init(domain: "script", service: h.applyProfileScriptService, data: [
            "display": "true", "mist_level": "5", "mode": "Sleep", "target_humidity": "50", "warm_level": "1",
        ])])
    }

    @Test func numbersSnapAndClamp() async {
        let (humidifier, _, caller, _) = controller()
        humidifier.setTargetHumidity(62.4)
        #expect(humidifier.targetHumidity == 60)
        humidifier.setTargetHumidity(99)
        humidifier.setTimerMinutes(50)
        #expect(humidifier.timerMinutes == 60)
        humidifier.setTimerMinutes(10_000)
        humidifier.setWarmLevel(5)
        #expect(humidifier.warmLevel == 3)
        await humidifier.commands.waitForCalls()
        #expect(caller.calls.map { $0.data["value"] } == ["60", "80", "60", "720", "3"])
    }

    @Test func switchesSendExplicitServices() async {
        let (humidifier, _, caller, _) = controller()
        humidifier.setDisplay(false)
        #expect(!humidifier.displayOn)
        humidifier.togglePower()
        #expect(!humidifier.powerOn)
        await humidifier.commands.waitForCalls()
        #expect(caller.calls == [
            .init(domain: "switch", service: "turn_off", data: ["entity_id": "switch.demo_switch_1"]),
            .init(domain: "switch", service: "turn_off", data: ["entity_id": "switch.demo_power_1"]),
        ])
    }

    @Test func optimisticValuesWaitForConfirmationThenRevertAfterEightSeconds() async {
        let (humidifier, store, _, scheduler) = controller()
        humidifier.setWarmLevel(3)
        set(store, h.warmLevelEntityId, "2.0")
        for _ in 0..<20 { await Task.yield() }
        #expect(humidifier.warmLevel == 3, "A different live value does not clear it")
        #expect(scheduler.pending.first?.delay == .seconds(8))
        set(store, h.warmLevelEntityId, "3.0")
        for _ in 0..<20 where !humidifier.commands.overlay.pending.isEmpty { await Task.yield() }
        #expect(humidifier.commands.overlay.pending.isEmpty)

        humidifier.setTargetHumidity(70)
        scheduler.fireAll()
        #expect(humidifier.targetHumidity == 50)
    }

    // MARK: Info

    @Test func infoItemsFollowTheState() {
        let (humidifier, _, _, _) = controller([h.timerRemainingEntityId: "3000"])
        #expect(humidifier.deviceItems.map(\.value) == ["Humidifying", "OK", "Installed", "Manual", "On", "Low"])
        #expect(humidifier.deviceItems[0].tone == .active)
        #expect(humidifier.environmentItems.map(\.value) == ["41%", "70°", "Level 5", "50m"])

        let (tank, _, _, _) = controller([h.tankRemovedEntityId: "on", h.powerEntityId: "off"])
        #expect(tank.deviceItems.map(\.value).prefix(3) == ["Tank Removed", "Low", "Removed"])
        #expect(tank.deviceItems.map(\.tone).prefix(3) == [.danger, .warning, .danger])
        #expect(tank.environmentItems[2].value == "Saved 5")

        let (water, _, _, _) = controller([h.waterLowEntityId: "on", h.humidifyingEntityId: "off"])
        #expect(water.deviceItems[0].tone == .warning)
        let (idle, _, _, _) = controller([h.humidifyingEntityId: "off"])
        #expect(idle.deviceItems[0].value == "Idle" && idle.deviceItems[0].tone == .ok)
        let (missing, _, _, _) = controller([h.powerEntityId: "unavailable", h.humidifyingEntityId: "off"])
        #expect(missing.deviceItems[0].tone == .unavailable)
        let (off, _, _, _) = controller([h.powerEntityId: "off", h.humidifyingEntityId: "off"])
        #expect(off.deviceItems[0].value == "Off" && off.deviceItems[0].tone == .neutral)
    }

    @Test func durationFormatting() {
        #expect(HumidifierController.formatMinutes(0) == "Off")
        #expect(HumidifierController.formatMinutes(30) == "30m")
        #expect(HumidifierController.formatMinutes(60) == "1h")
        #expect(HumidifierController.formatMinutes(90) == "1h 30m")
        #expect(HumidifierController.formatSeconds(nil) == "Off")
        #expect(HumidifierController.formatSeconds(30) == "1m")
        #expect(HumidifierController.formatSeconds(3_601) == "1h 1m")
        #expect(HumidifierController.warmTitle(2) == "Medium")
        #expect(HumidifierController.warmTitle(7) == "Level 7")
        #expect(HumidifierConfig.forPowerEntity("switch.demo_power_1") == HumidifierConfig.all[0])
        #expect(HumidifierMode.targetHumidity.title == "Auto Humidity")
        #expect(HumidifierMode.manual.icon == "mdi:water")
    }
}
