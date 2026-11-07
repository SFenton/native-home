import Foundation
@testable import HassCore
import Testing
import HassTestSupport

/// What each Climate control sends and shows meanwhile, with a recording caller and a manual clock.
@MainActor
@Suite(.demoHouse)
struct ClimateControllerTests {
    typealias C = ClimateConfig

    func controller(_ states: [String: String], attributes: [String: [String: JSONValue]] = [:])
        -> (ClimateController, EntityStore, RecordingCaller, ManualScheduler)
    {
        let store = makeStore(states, attributes: attributes)
        let caller = RecordingCaller()
        let scheduler = ManualScheduler()
        return (ClimateController(store: store, caller: caller, scheduler: scheduler), store, caller, scheduler)
    }

    @Test func toggleSendsHomeAssistantToggleAndShowsTheNewStateAtOnce() async {
        let (climate, store, caller, scheduler) = controller([C.ecoModeEntityId: "on"])
        climate.toggle(C.ecoModeEntityId)
        #expect(!climate.isOn(C.ecoModeEntityId))
        await climate.waitForCalls()
        #expect(caller.calls == [.init(domain: "homeassistant", service: "toggle", data: ["entity_id": C.ecoModeEntityId])])
        // Home Assistant confirms: the pending value clears without waiting for the revert.
        set(store, C.ecoModeEntityId, "off")
        for _ in 0..<20 where climate.overlay.pending[C.ecoModeEntityId] != nil { await Task.yield() }
        #expect(climate.overlay.pending[C.ecoModeEntityId] == nil)
        #expect(!climate.isOn(C.ecoModeEntityId))
        #expect(scheduler.items.count == 1)
    }

    @Test func unconfirmedToggleRevertsAfterTwoSeconds() async {
        let (climate, _, _, scheduler) = controller([C.trackSelectedEntityId: "off"])
        climate.toggle(C.trackSelectedEntityId)
        #expect(climate.isOn(C.trackSelectedEntityId))
        #expect(climate.trackingSummary.selectedEnabled, "Counts follow the optimistic state")
        #expect(scheduler.pending.first?.delay == .seconds(2))
        scheduler.fireAll()
        #expect(!climate.isOn(C.trackSelectedEntityId))
    }

    @Test func failedCallUndoesTheOptimisticValue() async {
        let (climate, _, caller, _) = controller([C.integrationEntityId: "on"])
        caller.failNext = true
        climate.toggle(C.integrationEntityId)
        #expect(!climate.isOn(C.integrationEntityId))
        await climate.waitForCalls()
        #expect(climate.isOn(C.integrationEntityId))
    }

    @Test func unavailableEntitiesIgnoreTaps() async {
        let (climate, _, caller, _) = controller([C.ecoModeEntityId: "unavailable"])
        climate.toggle(C.ecoModeEntityId)
        climate.toggle(C.trackSelectedEntityId)
        climate.setSwitch(C.predictiveComfortEntityId, on: true)
        await climate.waitForCalls()
        #expect(caller.calls.isEmpty)
        #expect(climate.isUnavailable(C.ecoModeEntityId) && climate.isUnavailable("switch.demo_missing"))
    }

    @Test func predictiveComfortUsesExplicitTurnOnAndTurnOff() async {
        let (climate, store, caller, _) = controller([C.predictiveComfortEntityId: "off"])
        climate.setSwitch(C.predictiveComfortEntityId, on: false)
        climate.setSwitch(C.predictiveComfortEntityId, on: true)
        #expect(climate.isOn(C.predictiveComfortEntityId))
        set(store, C.predictiveComfortEntityId, "on")
        for _ in 0..<20 where climate.overlay.pending[C.predictiveComfortEntityId] != nil { await Task.yield() }
        climate.setSwitch(C.predictiveComfortEntityId, on: false)
        await climate.waitForCalls()
        #expect(caller.calls.map(\.service) == ["turn_on", "turn_off"])
        #expect(caller.calls.allSatisfy { $0.domain == "switch" && $0.data["entity_id"] == C.predictiveComfortEntityId })
    }

    @Test func selectSendsSelectOptionAndSkipsTheShownOption() async {
        let (climate, _, caller, _) = controller([C.ecoAwayEntityId: "Keep Eco Active"])
        climate.select(C.ecoAwayEntityId, option: "Keep Eco Active")
        climate.select(C.ecoAwayEntityId, option: "Use Eco Away Targets")
        #expect(climate.shown(C.ecoAwayEntityId) == "Use Eco Away Targets")
        await climate.waitForCalls()
        #expect(caller.calls == [.init(domain: "select", service: "select_option",
                                       data: ["entity_id": C.ecoAwayEntityId, "option": "Use Eco Away Targets"])])
    }

    @Test func hubModeAndFanCallClimateServices() async {
        let (climate, store, caller, _) = controller([C.hubEntityId: "off"], attributes: [C.hubEntityId: ["fan_mode": .string("auto")]])
        #expect(climate.liveValue(ClimateController.hubFanKey) == "auto")
        climate.setHubMode("off")
        climate.setHubMode("heat")
        climate.setHubFan("auto")
        climate.setHubFan("on")
        #expect(climate.shown(ClimateController.hubModeKey) == "heat")
        #expect(climate.shown(ClimateController.hubFanKey) == "on")
        await climate.waitForCalls()
        #expect(caller.calls == [
            .init(domain: "climate", service: "set_hvac_mode", data: ["entity_id": C.hubEntityId, "hvac_mode": "heat"]),
            .init(domain: "climate", service: "set_fan_mode", data: ["entity_id": C.hubEntityId, "fan_mode": "on"]),
        ])
        set(store, C.hubEntityId, "heat", ["fan_mode": .string("on")])
        for _ in 0..<20 where !climate.overlay.pending.isEmpty { await Task.yield() }
        #expect(climate.overlay.pending.isEmpty)
    }

    @Test func lookupReadsTheStore() {
        let (climate, _, _, _) = controller([C.homeAwayEntityId: "Away"])
        #expect(climate.lookup(C.homeAwayEntityId)?.state == "Away")
        #expect(climate.entity("sensor.demo_none") == nil)
        #expect(climate.caller is RecordingCaller)
    }
}
