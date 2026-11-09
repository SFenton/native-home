import Foundation
@testable import HassCore
import HassTestSupport
import Testing

private func entity(_ id: String, _ state: String, _ attributes: [String: JSONValue] = [:]) -> EntityState {
    EntityState(entityId: id, state: state, attributes: attributes)
}

/// Anything a provider returns must obey the feedback contract.
private func assertContract(_ specs: [TileActionSpec], sourceLocation: SourceLocation = #_sourceLocation) {
    for spec in specs {
        #expect(spec.call?.service != "toggle", "\(spec.id) must use an explicit service", sourceLocation: sourceLocation)
        if spec.feedback == .momentary {
            #expect(spec.phase != .inFlight, "momentary \(spec.id) never shows a spinner", sourceLocation: sourceLocation)
            #expect(spec.optimistic.isEmpty, "momentary \(spec.id) shows nothing", sourceLocation: sourceLocation)
        }
        if spec.feedback == .tracked {
            #expect(spec.optimistic.isEmpty, "tracked \(spec.id) follows the entity", sourceLocation: sourceLocation)
        }
        if spec.phase == .ready { #expect(spec.call != nil, "\(spec.id) is runnable", sourceLocation: sourceLocation) }
    }
}

// MARK: - Lock

@Suite(.demoHouse)
struct LockActionsTests {
    let provider = LockActions(entityId: "lock.demo_front")

    private func spec(_ state: String?) -> TileActionSpec {
        let specs = provider.actions(for: state.map { entity("lock.demo_front", $0) })
        assertContract(specs)
        #expect(specs.count == 1)
        #expect(specs[0].id == "lock")
        return specs[0]
    }

    @Test func lockedOffersUnlock() {
        let s = spec("locked")
        #expect(s.verb == "Unlock" && s.symbol == "lock.fill" && s.isOn == false && s.phase == .ready)
        #expect(s.call == ServiceCall("lock", "unlock", target: "lock.demo_front"))
        #expect(s.feedback == .tracked && !s.isError)
    }

    @Test(arguments: ["unlocked", "open"])
    func unlockedOffersLock(_ state: String) {
        let s = spec(state)
        #expect(s.verb == "Lock" && s.symbol == "lock.open" && s.isOn == true && s.phase == .ready)
        #expect(s.call == ServiceCall("lock", "lock", target: "lock.demo_front"))
    }

    @Test func movingStatesAreInFlight() {
        let locking = spec("locking")
        #expect(locking.phase == .inFlight && locking.symbol == "lock.fill" && locking.isOn == false)
        let unlocking = spec("unlocking")
        #expect(unlocking.phase == .inFlight && unlocking.symbol == "lock.open" && unlocking.isOn == true)
    }

    @Test func jammedHasItsOwnShape() {
        let s = spec("jammed")
        #expect(s.isError && s.symbol == "lock.trianglebadge.exclamationmark" && s.verb == "Lock" && s.phase == .ready)
        #expect(s.call?.service == "lock")
    }

    @Test(arguments: [nil, "unavailable", "unknown"] as [String?])
    func unavailableDimsInPlace(_ state: String?) {
        let s = spec(state)
        #expect(s.phase == .unavailable && s.id == "lock" && s.isOn == false)
    }

    @Test func matchesTodaysFilledRule() {
        for state in ["locked", "unlocked", "open", "locking", "unlocking", "jammed", "unavailable", nil] {
            #expect(LockActions.isFilled(state) == (state != nil && state != "locked" && state != "unavailable"))
        }
    }

    @Test func stateTextCoversEveryShownState() {
        for state in ["locked", "unlocked", "locking", "unlocking", "jammed", "open"] {
            #expect(provider.stateTextCandidates.contains(SecurityConfig.stateText(state)))
        }
    }
}

// MARK: - Cover

@Suite(.demoHouse)
struct CoverActionsTests {
    let id = "cover.demo_garage_door_1"
    let stop: [String: JSONValue] = ["supported_features": .number(11)]
    let noStop: [String: JSONValue] = ["supported_features": .number(3)]

    private func spec(_ state: String, _ attributes: [String: JSONValue], hold: CoverActions.Hold = .none) -> TileActionSpec {
        let specs = CoverActions(entityId: id, hold: hold).actions(for: entity(id, state, attributes))
        assertContract(specs)
        #expect(specs.map(\.id) == ["door"], "one spec, id stable in \(state)")
        return specs[0]
    }

    @Test func closedOpensAndOpenCloses() {
        for attributes in [stop, noStop] {
            let closed = spec("closed", attributes)
            #expect(closed.verb == "Open" && closed.symbol == "door.garage.closed" && closed.isOn == false)
            #expect(closed.call == ServiceCall("cover", "open_cover", target: id))
            let open = spec("open", attributes)
            #expect(open.verb == "Close" && open.symbol == "door.garage.open" && open.isOn == true)
            #expect(open.call == ServiceCall("cover", "close_cover", target: id))
        }
    }

    @Test func movingStopsWhenSupported() {
        for state in ["opening", "closing"] {
            let s = spec(state, stop)
            #expect(s.verb == "Stop" && s.symbol == "stop.fill" && s.phase == .ready)
            #expect(s.call == ServiceCall("cover", "stop_cover", target: id))
        }
    }

    @Test func movingReversesOtherwiseWithTodaysCommand() {
        let opening = spec("opening", noStop)
        #expect(opening.verb == "Reverse" && opening.call == ServiceCall("cover", "close_cover", target: id))
        #expect(opening.call?.service == GarageDoorController.command(for: "opening")?.service)
        let closing = spec("closing", noStop)
        #expect(closing.verb == "Reverse" && closing.call == ServiceCall("cover", "open_cover", target: id))
        #expect(opening.symbol != closing.symbol)
    }

    @Test func missingFeatureAttributeReverses() {
        #expect(spec("opening", [:]).verb == "Reverse")
        #expect(CoverActions.supportsStop(entity(id, "open", ["supported_features": .number(8)])))
        #expect(!CoverActions.supportsStop(nil))
    }

    @Test func holdsAreInFlight() {
        for hold in [CoverActions.Hold.sending, .stopping] {
            for state in ["closed", "open", "opening", "closing"] {
                #expect(spec(state, stop, hold: hold).phase == .inFlight)
            }
        }
        #expect(spec("closed", stop, hold: .none).phase == .ready)
    }

    @Test func unavailableKeepsTheDoorSpec() {
        for state in [nil, entity(id, "unavailable"), entity(id, "unknown"), entity(id, "stopped")] {
            let specs = CoverActions(entityId: id).actions(for: state)
            #expect(specs.map(\.id) == ["door"] && specs[0].phase == .unavailable)
        }
    }

    @Test func filledWheneverNotClosed() {
        #expect(!CoverActions.isFilled("closed") && !CoverActions.isFilled("unavailable") && !CoverActions.isFilled(nil))
        for state in ["open", "opening", "closing"] { #expect(CoverActions.isFilled(state)) }
    }
}

// MARK: - Power

@Suite(.demoHouse)
struct PowerToggleActionsTests {
    @Test func towelRackIsOptimisticAndExplicit() {
        let provider = PowerToggleActions.entity("switch.demo_towel_rack", symbol: "heat.waves")
        let off = provider.actions(for: entity("switch.demo_towel_rack", "off"))
        assertContract(off)
        #expect(off[0].verb == "Turn On" && off[0].isOn == false && off[0].symbol == "heat.waves" && off[0].feedback == .optimistic)
        #expect(off[0].call == ServiceCall("switch", "turn_on", target: "switch.demo_towel_rack"))
        #expect(off[0].optimistic == [OptimisticIntent("switch.demo_towel_rack", value: "on")])
        let on = provider.actions(for: entity("switch.demo_towel_rack", "on"))
        #expect(on[0].verb == "Turn Off" && on[0].isOn == true)
        #expect(on[0].call?.service == "turn_off" && on[0].optimistic.first?.value == "off")
    }

    @Test func guestToggleUsesInputBoolean() {
        let id = HomeConfig.guestToggles[0].entityId
        let spec = PowerToggleActions.entity(id).actions(for: entity(id, "on"))[0]
        #expect(spec.call == ServiceCall("input_boolean", "turn_off", target: id))
    }

    @Test func unknownDomainsGoThroughHomeAssistant() {
        let spec = PowerToggleActions.entity("climate.demo_towel").actions(for: entity("climate.demo_towel", "off"))[0]
        #expect(spec.call?.domain == "homeassistant" && spec.call?.service == "turn_on")
    }

    @Test func pcPressesItsButtonsAndIsTracked() {
        let provider = PowerToggleActions.pc(prefix: "demo_pc")
        let off = provider.actions(for: entity("input_boolean.demo_pc_power", "off"))
        assertContract(off)
        #expect(off[0].feedback == .tracked && off[0].call == ServiceCall("input_button", "press", target: "input_button.demo_pc_on"))
        let on = provider.actions(for: entity("input_boolean.demo_pc_power", "on"))
        #expect(on[0].call?.target == "input_button.demo_pc_off" && on[0].isOn == true)
    }

    @Test func pcTurningStatusIsInFlight() {
        let provider = PowerToggleActions.pc(prefix: "x", statusText: "Turning On…")
        let spec = provider.actions(for: entity("input_boolean.demo_x_power", "off"))[0]
        #expect(spec.phase == .inFlight)
        #expect(PowerToggleActions.pc(prefix: "x", statusText: "Off").actions(for: entity("input_boolean.demo_x_power", "off"))[0].phase == .ready)
        // An optimistic toggle never goes in flight from a status string.
        var optimistic = PowerToggleActions.entity("switch.demo_a")
        optimistic.statusText = "Turning On…"
        #expect(optimistic.actions(for: entity("switch.demo_a", "off"))[0].phase == .ready)
    }

    @Test func remotePowerFollowsTheRemotesOwnCommandAndOffStates() {
        let shield = MediaRemotes.config(id: "living-room-streamer")!
        let provider = PowerToggleActions.remote(shield)
        let off = provider.actions(for: entity(shield.controlEntityId, "off"))[0]
        #expect(off.verb == "Turn On" && off.isOn == false && off.call == ServiceCall("remote", "demo_send_command", target: "remote.demo_living_room_1", data: ["command": "POWER"]))
        #expect(provider.actions(for: entity(shield.controlEntityId, "playing"))[0].verb == "Turn Off")
        let tv = MediaRemotes.config(id: "bedroom-1-streamer-tv")!
        #expect(PowerToggleActions.remote(tv).isOn("standby") == false)
    }

    @Test func unavailableDims() {
        for provider in [PowerToggleActions.entity("switch.demo_a"), .pc(prefix: "p"), .remote(MediaRemotes.config(id: "living-room-streamer")!)] {
            for state in [nil, entity(provider.entityId, "unavailable"), entity(provider.entityId, "unknown")] {
                let specs = provider.actions(for: state)
                #expect(specs.count == 1 && specs[0].phase == .unavailable && specs[0].id == "power")
            }
        }
    }
}

// MARK: - Media

@Suite(.demoHouse)
struct MediaTransportActionsTests {
    let config = MediaRemotes.config(id: "living-room-streamer")!
    var provider: MediaTransportActions { MediaTransportActions(config: config) }
    var player: String { config.mediaEntityId }

    private func specs(_ state: String?, features: Int? = nil) -> [TileActionSpec] {
        let attributes: [String: JSONValue] = features.map { ["supported_features": .number(Double($0))] } ?? [:]
        let result = provider.actions(for: state.map { entity(player, $0, attributes) })
        assertContract(result)
        return result
    }

    @Test func playingShowsTransportWithPauseEmphasized() {
        let result = specs("playing")
        #expect(result.map(\.id) == ["previous", "play_pause", "next"])
        let pause = result[1]
        #expect(pause.verb == "Pause" && pause.symbol == "pause.fill" && pause.isEmphasized && pause.feedback == .optimistic)
        #expect(pause.isOn == nil)
        #expect(pause.call == ServiceCall("remote", "demo_send_command", target: "remote.demo_living_room_1", data: ["command": "MEDIA_PAUSE"]))
        #expect(pause.optimistic == [OptimisticIntent(player, value: "paused")])
        #expect(result[0].feedback == .momentary && result[0].call == ServiceCall("media_player", "media_previous_track", target: player))
        #expect(result[2].feedback == .momentary && result[2].call?.service == "media_next_track")
        #expect(result[0].symbol == "backward.fill" && result[2].symbol == "forward.fill")
    }

    @Test func pausedShowsPlayAction() {
        let play = specs("paused")[1]
        #expect(play.verb == "Play" && play.symbol == "play.fill" && play.isEmphasized)
        #expect(play.call?.data["command"] == "MEDIA_PLAY" && play.optimistic == [OptimisticIntent(player, value: "playing")])
    }

    @Test func featureBitsGateEachButton() {
        #expect(specs("playing", features: 1).map(\.id) == ["play_pause"])
        #expect(specs("playing", features: 1 | 16).map(\.id) == ["previous", "play_pause"])
        #expect(specs("playing", features: 16 | 32).map(\.id) == ["previous", "next"])
        // Paused needs the play bit, not pause.
        #expect(specs("paused", features: 1 | 32).map(\.id) == ["next"])
        #expect(specs("paused", features: 16384 | 32).map(\.id) == ["play_pause", "next"])
        #expect(specs("playing", features: 0).isEmpty)
    }

    @Test func offAndIdleShowPowerOnly() {
        for state in ["off", "standby", "idle", "on"] {
            let result = specs(state)
            #expect(result.map(\.id) == ["power"], "\(state)")
        }
        #expect(specs("off")[0].verb == "Turn On")
        #expect(specs("on")[0].verb == "Turn Off")
    }

    @Test func unavailableDimsPower() {
        for state in [nil, "unavailable", "unknown"] as [String?] {
            let result = specs(state)
            #expect(result.map(\.id) == ["power"] && result[0].phase == .unavailable)
        }
    }

    @Test func appleTVUsesItsOwnPlayCommandAndOffStates() {
        let tv = MediaRemotes.config(id: "bedroom-1-streamer-tv")!
        let result = MediaTransportActions(config: tv).actions(for: entity(tv.mediaEntityId, "playing"))
        #expect(result[1].call == ServiceCall("remote", "demo_send_command", target: "remote.demo_bedroom_1_1", data: ["command": "pause"]))
        #expect(MediaTransportActions(config: tv).actions(for: entity(tv.mediaEntityId, "standby"))[0].verb == "Turn On")
    }

    @Test func everyRemoteBuildsProvidersInEveryState() {
        for remote in MediaRemotes.all {
            for state in ["off", "playing", "paused", "idle", "unavailable"] {
                assertContract(MediaTransportActions(config: remote).actions(for: entity(remote.mediaEntityId, state)))
            }
        }
    }
}

// MARK: - Fan

@Suite(.demoHouse)
struct FanRailActionsTests {
    let config = BathroomFanConfig.all[0]
    private func provider(lock: String?, pending: Bool = false, auto: Bool = false) -> FanRailActions {
        FanRailActions(config: config, lockState: lock.map { entity(config.lockEntityId, $0) }, timerPending: pending, autoUnlock: auto)
    }
    private func power(_ state: String?) -> EntityState? { state.map { entity(config.powerEntityId, $0) } }

    @Test func lockThenPowerWithScriptCommands() {
        let specs = provider(lock: "off").actions(for: power("off"))
        assertContract(specs)
        #expect(specs.map(\.id) == ["lock", "power"])
        #expect(specs[0].verb == "Lock" && specs[0].symbol == "lock.open" && specs[0].isOn == false)
        #expect(specs[0].call == ServiceCall("script", config.scriptService, data: ["command": "lock", "locked": true]))
        #expect(specs[1].verb == "Turn On" && specs[1].symbol == "power" && specs[1].isOn == false)
        #expect(specs[1].call == ServiceCall("script", config.scriptService, data: ["command": "power", "target_power": "on"]))
        #expect(specs.allSatisfy { $0.feedback == .optimistic })
        #expect(specs[0].optimistic == [OptimisticIntent(config.lockEntityId, value: "on")])
    }

    @Test func onStatesAndClearedHelpers() {
        let specs = provider(lock: "on", pending: true, auto: true).actions(for: power("on"))
        #expect(specs[0].verb == "Unlock" && specs[0].symbol == "lock.fill" && specs[0].isOn == true)
        #expect(specs[0].call?.data["locked"] == false)
        #expect(specs[1].verb == "Turn Off" && specs[1].isOn == true && specs[1].call?.data["target_power"] == "off")
        // Same intents as BathroomFanController.setPower.
        #expect(specs[1].optimistic == [
            OptimisticIntent(config.powerEntityId, value: "off"), OptimisticIntent(config.pendingEntityId, value: "off"),
            OptimisticIntent(config.lockEntityId, value: "off"), OptimisticIntent(config.autoUnlockEntityId, value: "off"),
        ])
    }

    @Test func lockingDuringATimerTurnsAutoUnlockOn() {
        let specs = provider(lock: "off", pending: true).actions(for: power("on"))
        #expect(specs[0].optimistic == [OptimisticIntent(config.lockEntityId, value: "on"), OptimisticIntent(config.autoUnlockEntityId, value: "on")])
    }

    @Test func unavailableDimsInPlaceAndKeepsBothIds() {
        let lockGone = provider(lock: "unavailable").actions(for: power("on"))
        #expect(lockGone.map(\.id) == ["lock", "power"] && lockGone[0].phase == .unavailable && lockGone[1].phase == .ready)
        for state in [nil, "unavailable", "unknown"] as [String?] {
            let specs = provider(lock: "off").actions(for: power(state))
            #expect(specs.map(\.id) == ["lock", "power"] && specs.allSatisfy { $0.phase == .unavailable })
        }
        #expect(provider(lock: nil).actions(for: power("on"))[0].phase == .unavailable)
    }
}

// MARK: - Vacuum

@Suite(.demoHouse)
struct VacuumActionsTests {
    let id = "vacuum.demo_v"
    private func specs(_ state: String?) -> [TileActionSpec] {
        let result = VacuumActions(entityId: id).actions(for: state.map { entity(id, $0) })
        assertContract(result)
        #expect(result.map(\.id) == ["start_pause", "dock"], "the set never changes shape")
        return result
    }

    @Test func cleaningPausesAndDocks() {
        let s = specs("cleaning")
        #expect(s[0].verb == "Pause" && s[0].symbol == "pause.fill" && s[0].feedback == .optimistic && s[0].phase == .ready)
        #expect(s[0].call == ServiceCall("vacuum", "pause", target: id) && s[0].optimistic == [OptimisticIntent(id, value: "paused")])
        #expect(s[1].verb == "Dock" && s[1].feedback == .momentary && s[1].phase == .ready)
        #expect(s[1].call == ServiceCall("vacuum", "return_to_base", target: id))
    }

    @Test func pausedResumes() {
        let s = specs("paused")
        #expect(s[0].verb == "Resume" && s[0].symbol == "play.fill" && s[0].call?.service == "start")
        #expect(s[0].optimistic == [OptimisticIntent(id, value: "cleaning")] && s[1].phase == .ready)
    }

    @Test func dockedStartsAndCannotDock() {
        let s = specs("docked")
        #expect(s[0].verb == "Start" && s[0].phase == .ready && s[1].phase == .unavailable)
    }

    @Test func idleStartsAndDocks() {
        let s = specs("idle")
        #expect(s[0].phase == .ready && s[1].phase == .ready)
    }

    @Test func returningPausesButAlreadyDocking() {
        let s = specs("returning")
        #expect(s[0].verb == "Pause" && s[1].phase == .unavailable)
    }

    @Test func errorOnlyDocks() {
        let s = specs("error")
        #expect(s[0].phase == .unavailable && s[1].phase == .ready)
    }

    @Test(arguments: [nil, "unavailable", "unknown"] as [String?])
    func unavailableDimsBoth(_ state: String?) {
        #expect(specs(state).allSatisfy { $0.phase == .unavailable })
    }
}

// MARK: - Cross-provider

@Suite(.demoHouse)
struct TileActionContractTests {
    @Test func nobodyEverToggles() {
        let providers: [(any TileActionProviding, String)] = [
            (LockActions(entityId: "lock.demo_a"), "lock.demo_a"), (CoverActions(entityId: "cover.demo_a"), "cover.demo_a"),
            (PowerToggleActions.entity("switch.demo_a"), "switch.demo_a"), (PowerToggleActions.pc(prefix: "p"), "input_boolean.demo_p_power"),
            (VacuumActions(entityId: "vacuum.demo_a"), "vacuum.demo_a"),
            (FanRailActions(config: BathroomFanConfig.all[1], lockState: nil), BathroomFanConfig.all[1].powerEntityId),
        ]
        let states = ["on", "off", "locked", "unlocked", "locking", "unlocking", "jammed", "open", "closed", "opening", "closing",
                      "cleaning", "paused", "docked", "returning", "idle", "error", "unavailable", "unknown"]
        for (provider, id) in providers {
            for state in states + [""] {
                assertContract(provider.actions(for: state.isEmpty ? nil : entity(id, state)))
            }
            #expect(!provider.stateTextCandidates.isEmpty)
        }
    }
}
