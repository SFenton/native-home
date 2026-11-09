import Foundation
import HassCore
import HassDesign
@testable import HassUI
import SwiftUI
import Testing
import HassTestSupport

/// The HassUI side of the rollout foundations: the new spec fields reaching the tile, the confirmation sharing `AlertCopy`'s words,
/// and the tracked power hold running through the shared optimistic path. Pure checks, so they run on any host.
@MainActor
@Suite(.demoHouse)
struct TileRolloutMappingTests {
    final class Caller: HassServiceCalling {
        struct Rejected: Error {}
        var calls: [String] = []
        var fails = false
        func callService(_ domain: String, _ service: String, data: [String: any Sendable]) async throws {
            calls.append("\(domain).\(service)")
            if fails { throw Rejected() }
        }
    }

    // MARK: Mapping

    @Test func theNewFieldsReachTheItem() {
        let ask = TileActionSpec.Confirmation(title: "Turn off Alex's Bed?", message: "m", confirmVerb: "Turn Off", isDestructive: true, style: .dialog)
        let spec = TileActionSpec(id: "p", verb: "Turn Off", symbol: "power", feedback: .optimistic, label: "Turn Off TV", confirmation: ask,
                                  selection: .ordered(position: 3))
        let item = TileActionItem(spec)
        #expect(item.label == "Turn Off TV" && item.selection == .ordered(position: 3))
        #expect(item.confirmation == TileActionConfirmation(title: "Turn off Alex's Bed?", message: "m", confirmVerb: "Turn Off", isDestructive: true, style: .dialog))
        let plain = TileActionItem(TileActionSpec(id: "p", verb: "Go", symbol: "bolt", feedback: .momentary))
        #expect(plain.label == nil && plain.confirmation == nil && plain.selection == nil)
        #expect(TileActionItem(TileActionSpec(id: "s", verb: "S", symbol: "circle", feedback: .optimistic, selection: .single(isSelected: true))).selection == .single(isSelected: true))
        #expect(TileActionConfirmation(TileActionSpec.Confirmation(title: "T", confirmVerb: "Go")).style == .alert)
    }

    // MARK: Words

    @Test func theAlarmDiscAsksWithTheSecuritySheetsWords() {
        #expect(TileActionSpec.Confirmation(AlertCopy.disarm) == AlarmModeActions.disarmConfirmation)
    }

    @Test func anAlertCopySpecKeepsItsRole() {
        let signOut = TileActionSpec.Confirmation(AlertCopy.signOut)
        #expect(signOut.isDestructive && signOut.confirmVerb == "Sign Out" && signOut.style == .alert)
        let vacation = TileActionSpec.Confirmation(AlertCopy.turnOffVacation)
        #expect(!vacation.isDestructive && vacation.title == "Turn Off Vacation Mode?" && vacation.message == "Your checklist and helpers reset.")
        #expect(TileActionSpec.Confirmation(AlertCopy.highAqiMode(turningOn: true), style: .dialog).style == .dialog)
    }

    // MARK: Tracked power

    @Test func aTappedSwitchHoldsInFlightUntilTheBooleanReportsThenSettles() async {
        let provider = ScriptPowerActions.all[0]
        let active = provider.activeEntityId
        let store = EntityStore()
        store.apply([EntityState(entityId: active, state: "off"), EntityState(entityId: provider.onScriptEntityId, state: "off"),
                     EntityState(entityId: provider.offScriptEntityId, state: "off")])
        let caller = Caller()
        let actions = OptimisticActions(store: store, rules: [active: .confirmation], caller: caller)

        func spec() -> TileActionSpec {
            provider.actions(live: store.entity(active).state, pending: actions.overlay.pending[active],
                             onScript: store.entity(provider.onScriptEntityId).state, offScript: store.entity(provider.offScriptEntityId).state)[0]
        }
        #expect(spec().phase == .ready && spec().verb == "Turn On")

        let task = actions.perform(spec())
        #expect(spec().phase == .inFlight && spec().isOn == false, "the arc spins; the glyph has not moved")
        await task?.value
        #expect(caller.calls == ["script.demo_room_console_2"])
        #expect(spec().phase == .inFlight, "the call returned, the house has not")

        store.apply([EntityState(entityId: provider.onScriptEntityId, state: "on")])
        #expect(spec().phase == .inFlight)
        store.apply([EntityState(entityId: active, state: "on")])
        try? await Task.sleep(for: .milliseconds(50))
        #expect(spec().phase == .inFlight, "the boolean reported but the script is still running")
        store.apply([EntityState(entityId: provider.onScriptEntityId, state: "off")])
        #expect(spec().phase == .ready && spec().isOn == true && spec().verb == "Turn Off", "settled: the final glyph and fill")
        #expect(!actions.isFailed(active))
    }

    @Test func aRejectedCallShowsDidntRespondAndReturnsTheDisc() async {
        let provider = ScriptPowerActions.all[1]
        let active = provider.activeEntityId
        let store = EntityStore()
        store.apply([EntityState(entityId: active, state: "on")])
        let caller = Caller()
        caller.fails = true
        let actions = OptimisticActions(store: store, rules: [active: .confirmation], caller: caller)
        let spec = provider.actions(for: store.entity(active).state)[0]
        await actions.perform(spec)?.value
        #expect(caller.calls == ["script.demo_room_power_toggle"], "On: the disc runs the room's Power key")
        #expect(actions.isFailed(active), "the tile reads Didn't Respond")
        let after = provider.actions(live: store.entity(active).state, pending: actions.overlay.pending[active], onScript: nil, offScript: nil)[0]
        #expect(after.phase == .ready && after.isOn == true, "animates back to where it was")
    }

    @Test func aMomentarySpecShowsNothingWhileItRuns() async {
        let store = EntityStore()
        let caller = Caller()
        let actions = OptimisticActions(store: store, rules: [:], caller: caller)
        let spec = CommandActions.powerRecovery.actions(for: EntityState(entityId: HouseholdSettingsConfig.Admin.powerRecoveryAutomation, state: "on"))[0]
        await actions.perform(spec, failing: "automation.demo_x")?.value
        #expect(caller.calls == ["automation.trigger"])
        caller.fails = true
        await actions.perform(spec, failing: "automation.demo_x")?.value
        #expect(actions.isFailed("automation.demo_x"))
    }
}
