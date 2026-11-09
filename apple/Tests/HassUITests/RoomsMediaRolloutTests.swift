import Foundation
import HassCore
import HassDesign
@testable import HassUI
import SwiftUI
import Testing
import HassTestSupport

/// The pure side of lane R: what the shared support feeds the providers, what the fan rail hands the sheet, and how the gallery's
/// recorder answers the new script calls so a journey sees the state change. No accessibility permission needed.
@MainActor
@Suite(.demoHouse)
struct RoomsMediaRolloutTests {
    final class Caller: HassServiceCalling {
        var calls: [String] = []
        func callService(_ domain: String, _ service: String, data: [String: any Sendable]) async throws { calls.append("\(domain).\(service)") }
    }

    // MARK: Shared support

    @Test func eachScriptDeviceFindsItsProviderByItsBoolean() {
        #expect(RolloutTileSupport.scriptProvider(forEntity: ScriptPowerActions.all[0].activeEntityId)?.onScript == ScriptPowerActions.all[0].onScript)
        #expect(RolloutTileSupport.scriptProvider(forEntity: ScriptPowerActions.all[1].activeEntityId)?.onScript == "demo_room_media_1")
        #expect(RolloutTileSupport.scriptProvider(forEntity: "light.demo_x") == nil)
    }

    @Test func aScriptDeviceHoldsInFlightWhileItsScriptRuns() {
        let store = EntityStore()
        let provider = ScriptPowerActions.all[1]
        store.apply([EntityState(entityId: provider.activeEntityId, state: "off"), EntityState(entityId: provider.onScriptEntityId, state: "off"),
                     EntityState(entityId: provider.offScriptEntityId, state: "off")])
        #expect(RolloutTileSupport.scriptSpecs(provider, store: store, actions: nil).first?.phase == .ready)
        store.apply([EntityState(entityId: provider.onScriptEntityId, state: "on")])
        #expect(RolloutTileSupport.scriptSpecs(provider, store: store, actions: nil).first?.phase == .inFlight, "the script is running")
        store.apply([EntityState(entityId: provider.onScriptEntityId, state: "off"), EntityState(entityId: provider.activeEntityId, state: "on")])
        let settled = RolloutTileSupport.scriptSpecs(provider, store: store, actions: nil).first
        #expect(settled?.phase == .ready && settled?.isOn == true && settled?.verb == "Turn Off")
    }

    @Test func aTappedScriptDeviceFailsWithDidntRespondAndAnsweringEndsTheHold() async {
        let store = EntityStore()
        let provider = ScriptPowerActions.all[0]
        store.apply([EntityState(entityId: provider.activeEntityId, state: "off")])
        let caller = Caller()
        let actions = RolloutTileSupport.scriptActions(provider, store: store, caller: caller)
        let spec = RolloutTileSupport.scriptSpecs(provider, store: store, actions: actions)[0]
        await actions.perform(spec)?.value
        #expect(caller.calls == [provider.onScriptEntityId])
        #expect(RolloutTileSupport.scriptSpecs(provider, store: store, actions: actions)[0].phase == .inFlight, "waiting on the boolean")
        store.apply([EntityState(entityId: provider.activeEntityId, state: "on")])
        try? await Task.sleep(for: .milliseconds(50))
        #expect(RolloutTileSupport.scriptSpecs(provider, store: store, actions: actions)[0].phase == .ready)
    }

    @Test func aSourceFaceIsTheProvidersDiscAndStateLine() {
        typealias M = MediaRemotes.MusicRoom
        let xbox = RolloutTileSupport.sourceProvider(title: "Game Console")!
        let chosen = RolloutTileSupport.sourceFace(xbox, state: EntityState(entityId: M.activeMediaSourceEntityId, state: M.Source.fortnite))
        #expect(chosen.subtitle == "On the TV" && chosen.specs.first?.selection == .single(isSelected: true) && chosen.specs.first?.label == "Turn Off TV")
        let idle = RolloutTileSupport.sourceFace(xbox, state: EntityState(entityId: M.activeMediaSourceEntityId, state: M.Source.tv))
        #expect(idle.subtitle == nil && idle.specs.first?.selection == .single(isSelected: false))
        let fortnite = RolloutTileSupport.sourceFace(RolloutTileSupport.sourceProvider(title: "Game")!,
                                                      state: EntityState(entityId: M.activeMediaSourceEntityId, state: M.Source.fortnite))
        #expect(fortnite.specs.first?.verb == "Select", "Fortnite relaunches, so its chosen disc does not say it turns anything off")
        #expect(RolloutTileSupport.sourceProvider(title: "Nope") == nil)
    }

    // MARK: Fan rail

    @Test func theFanSheetAndTheRoomTileShareTheRailSpecs() {
        let store = EntityStore()
        store.replaceAll(RoomDeviceFixture.fanStates(BathroomFanConfig.all[1], power: "on", locked: true, pending: false, now: Date()))
        let fan = BathroomFanController(config: BathroomFanConfig.all[1], store: store, caller: Caller())
        let specs = fan.railSpecs
        #expect(specs.map(\.id) == ["lock", "power"])
        #expect(specs.first { $0.id == "lock" }?.verb == "Unlock" && specs.first { $0.id == "power" }?.verb == "Turn Off")
    }

    @Test func runningARailDiscSendsTheFanScriptsExplicitTarget() async {
        let store = EntityStore()
        store.replaceAll(RoomDeviceFixture.fanStates(BathroomFanConfig.all[0], power: "off", locked: false, pending: false, now: Date()))
        let caller = Caller()
        let fan = BathroomFanController(config: BathroomFanConfig.all[0], store: store, caller: caller)
        fan.runRail("power")
        fan.runRail("lock")
        fan.runRail("unknown")
        await fan.commands.waitForCalls()
        #expect(caller.calls == ["script.\(BathroomFanConfig.all[0].scriptService)", "script.\(BathroomFanConfig.all[0].scriptService)"])
    }

    // MARK: Gallery recorder

    @Test func theGalleryAnswersTheTheaterScriptsAndTheMusicSources() async {
        let store = EntityStore()
        store.replaceAll(MediaRemoteFixtures.states)
        let recorder = GalleryServiceRecorder(store: store)
        try? await recorder.callService("script", ScriptPowerActions.all[0].onScript, data: [:])
        #expect(store.value(ScriptPowerActions.all[0].activeEntityId)?.state == "on")
        #expect(store.value(ScriptPowerActions.all[1].activeEntityId)?.state == "off", "one device is active at a time")
        try? await recorder.callService("script", "demo_room_media_1", data: [:])
        #expect(store.value(ScriptPowerActions.all[1].activeEntityId)?.state == "on" && store.value(ScriptPowerActions.all[0].activeEntityId)?.state == "off")
        try? await recorder.callService("script", "demo_room_power_toggle", data: [:])
        #expect(store.value(ScriptPowerActions.all[1].activeEntityId)?.state == "off", "the Power key turns the active device off")
        try? await recorder.callService("script", "demo_studio_game", data: [:])
        #expect(store.value(MediaRemotes.MusicRoom.activeMediaSourceEntityId)?.state == MediaRemotes.MusicRoom.Source.fortnite)
        try? await recorder.callService("script", "demo_studio_windows_pc", data: [:])
        #expect(store.value(MediaRemotes.MusicRoom.activeMediaSourceEntityId)?.state == MediaRemotes.MusicRoom.Source.windowsPC)
        try? await recorder.callService("fan", "turn_off", data: ["entity_id": "fan.demo_x_purifier"])
        #expect(store.value("fan.demo_x_purifier")?.state == "off")
    }
}
