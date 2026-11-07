import Foundation
import HAKit
@testable import HassCore
import Testing

/// ``OptimisticActions``: commit-then-call, rollback on failure, live confirmation and resets.
@MainActor
struct OptimisticActionsTests {
    private func make(_ states: [String: String], rules: [String: OptimisticOverlay.ClearRule])
        -> (OptimisticActions, EntityStore, RecordingCaller, ManualScheduler) {
        let store = makeStore(states)
        let caller = RecordingCaller()
        let scheduler = ManualScheduler()
        let actions = OptimisticActions(store: store, rules: rules, caller: caller, scheduler: scheduler)
        return (actions, store, caller, scheduler)
    }

    /// Lets the observation hop (`Task { @MainActor in ... }`) run.
    private func settle() async {
        for _ in 0..<5 { await Task.yield() }
    }

    @Test func showsTheIntentAtOnceAndSendsTheCall() async {
        let (actions, _, caller, _) = make(["light.demo_desk": "off"], rules: ["light.demo_desk": .confirmation])
        let task = actions.perform(ServiceCall("light", "turn_on", target: "light.demo_desk"), showing: [.init("light.demo_desk", value: "on")])
        #expect(actions.shown("light.demo_desk") == "on")
        #expect(actions.isPending("light.demo_desk"))
        await task.value
        #expect(caller.calls == [.init(domain: "light", service: "turn_on", data: ["entity_id": "light.demo_desk"])])
    }

    @Test func confirmationClearsQuietly() async {
        let (actions, store, _, _) = make(["light.demo_desk": "off"], rules: ["light.demo_desk": .confirmation])
        await actions.perform("light", "turn_on", data: ["entity_id": "light.demo_desk"], showing: [.init("light.demo_desk", value: "on")]).value
        store.apply([EntityState(entityId: "light.demo_desk", state: "on")])
        await settle()
        #expect(actions.overlay.pending["light.demo_desk"] == nil)
        #expect(actions.shown("light.demo_desk") == "on")
    }

    @Test func liveChangeRuleClearsOnAnyChange() async {
        let (actions, store, _, _) = make(["light.demo_desk": "off"], rules: ["light.demo_desk": .liveChange])
        actions.perform("light", "turn_on", data: ["entity_id": "light.demo_desk"], showing: [.init("light.demo_desk", value: "on")])
        // Presence Based Lighting reverts the light: the tile follows the truth instead of holding "on".
        store.apply([EntityState(entityId: "light.demo_desk", state: "unavailable")])
        await settle()
        #expect(actions.shown("light.demo_desk") == "unavailable")
    }

    @Test func failureRollsBackWithoutWaitingForTheTimer() async {
        let (actions, _, caller, scheduler) = make(["switch.fan": "off"], rules: ["switch.fan": .confirmation])
        caller.failNext = true
        let task = actions.perform(ServiceCall("switch", "turn_on", target: "switch.fan"), showing: [.init("switch.fan", value: "on")])
        #expect(actions.shown("switch.fan") == "on")
        await task.value
        #expect(actions.shown("switch.fan") == "off")
        // Only the failed face's 4 s timer is left; the revert timer is gone.
        #expect(scheduler.pending.map(\.delay) == [OptimisticOverlay.failureDuration])
    }

    // MARK: Failed face

    @Test func aRejectedCallShowsTheFailedFaceForFourSeconds() async {
        let (actions, _, caller, scheduler) = make(["switch.fan": "off"], rules: ["switch.fan": .confirmation])
        caller.failNext = true
        await actions.perform(ServiceCall("switch", "turn_on", target: "switch.fan"), showing: [.init("switch.fan", value: "on")]).value
        #expect(actions.isFailed("switch.fan"))
        #expect(OptimisticOverlay.failureDuration == .seconds(4))
        scheduler.fireAll()
        #expect(!actions.isFailed("switch.fan"))
    }

    @Test func aCommandWithNoIntentFailsTheNamedKey() async {
        let (actions, _, caller, _) = make(["switch.fan": "off"], rules: ["switch.fan": .confirmation])
        caller.failNext = true
        await actions.perform(ServiceCall("script", "turn_on", target: "script.demo_go"), showing: [], failing: "script.demo_go").value
        #expect(actions.isFailed("script.demo_go"))
        // A key that already failed through an intent is not marked twice.
        caller.failNext = true
        await actions.perform("switch", "turn_on", data: [:], showing: [.init("switch.fan", value: "on")], failing: "switch.fan").value
        #expect(actions.isFailed("switch.fan"))
    }

    @Test func aSuccessfulCallShowsNoFailure() async {
        let (actions, _, _, _) = make(["switch.fan": "off"], rules: ["switch.fan": .confirmation])
        await actions.perform(ServiceCall("switch", "turn_on", target: "switch.fan"), showing: [.init("switch.fan", value: "on")],
                              failing: "switch.fan").value
        #expect(!actions.isFailed("switch.fan"))
    }

    @Test func theNextTapClearsTheFailedFace() async {
        let (actions, _, caller, _) = make(["switch.fan": "off"], rules: ["switch.fan": .confirmation])
        caller.failNext = true
        await actions.perform(ServiceCall("switch", "turn_on", target: "switch.fan"), showing: [.init("switch.fan", value: "on")]).value
        #expect(actions.isFailed("switch.fan"))
        actions.perform(ServiceCall("switch", "turn_on", target: "switch.fan"), showing: [.init("switch.fan", value: "on")])
        #expect(!actions.isFailed("switch.fan"))
    }

    @Test func anOlderFailureNeverUndoesANewerTap() async {
        let (actions, _, caller, _) = make(["select.demo_mode": "a"], rules: ["select.demo_mode": .confirmation])
        caller.failNext = true
        let first = actions.perform(ServiceCall("select", "select_option", target: "select.demo_mode"), showing: [.init("select.demo_mode", value: "b")])
        actions.perform(ServiceCall("select", "select_option", target: "select.demo_mode"), showing: [.init("select.demo_mode", value: "c")])
        await first.value
        await actions.waitForCalls()
        #expect(actions.shown("select.demo_mode") == "c")
    }

    @Test func revertTimerGivesWayToLive() {
        let (actions, _, _, scheduler) = make(["switch.fan": "off"], rules: ["switch.fan": .confirmation])
        actions.perform(ServiceCall("switch", "turn_on", target: "switch.fan"), showing: [.init("switch.fan", value: "on")])
        #expect(scheduler.pending.first?.delay == OptimisticActions.defaultRevert)
        scheduler.fireAll()
        #expect(actions.shown("switch.fan") == "off")
    }

    @Test func resetsClearMatchingPendingValuesOnly() async {
        let (actions, _, _, _) = make(["media_player.demo_tv": "idle", "select.demo_source": "a"],
                                      rules: ["media_player.demo_tv": .confirmation, "select.demo_source": .confirmation])
        actions.perform(ServiceCall("media_player", "media_play", target: "media_player.demo_tv"), showing: [.init("media_player.demo_tv", value: "playing")])
        actions.perform(ServiceCall("select", "select_option", target: "select.demo_source"), showing: [.init("select.demo_source", value: "b")])
        actions.perform(ServiceCall("media_player", "media_stop", target: "media_player.demo_tv"), showing: [],
                        resetting: [.init("media_player.demo_tv", values: ["playing"]), .init("select.demo_source", values: ["z"])])
        #expect(actions.shown("media_player.demo_tv") == "idle")
        #expect(actions.shown("select.demo_source") == "b")
        await actions.waitForCalls()
    }

    @Test func untrackedKeysAreSentButNotShown() async {
        let (actions, _, caller, _) = make(["light.demo_desk": "off"], rules: [:])
        await actions.perform(ServiceCall("light", "turn_on", target: "light.demo_desk"), showing: [.init("light.demo_desk", value: "on")]).value
        #expect(actions.shown("light.demo_desk") == "off")
        #expect(caller.calls.count == 1)
    }

    @Test func customLiveSourceTracksAttributes() async {
        let store = makeStore(["climate.hub": "heat"], attributes: ["climate.hub": ["fan_mode": .string("auto")]])
        let actions = OptimisticActions(rules: ["hub#fan": .confirmation], caller: RecordingCaller(), scheduler: ManualScheduler()) { key in
            key == "hub#fan" ? store.entity("climate.hub").state?.attributes["fan_mode"]?.string : nil
        }
        actions.perform(ServiceCall("climate", "set_fan_mode", target: "climate.hub"), showing: [.init("hub#fan", value: "on")])
        #expect(actions.shown("hub#fan") == "on")
        store.apply([EntityState(entityId: "climate.hub", state: "heat", attributes: ["fan_mode": .string("on")])])
        await settle()
        #expect(actions.overlay.pending["hub#fan"] == nil)
        await actions.waitForCalls()
    }
}

/// ``EntityStore`` applies a delivery's changes and removals in place.
@MainActor
struct EntityDeliveryDeltaTests {
    @Test func storeAppliesChangesAndRemovalsInPlace() {
        let store = makeStore(["light.demo_a": "on", "sensor.demo_c": "3"])
        let kept = store.entity("light.demo_a")
        let removed = store.entity("sensor.demo_c")
        let before = store.publishedChangeCount
        store.apply([EntityState(entityId: "light.demo_a", state: "on")], removing: ["sensor.demo_c", "missing.x"], freshness: .live)
        #expect(kept.state?.state == "on")
        #expect(removed.state == nil)
        #expect(store.publishedChangeCount == before + 1)
        #expect(store.freshness == .live)
    }
}
