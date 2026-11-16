import Foundation
import HassTestSupport
import Testing
@testable import HassCore

// MARK: - Authored sprinkler gestures and schedule drafts

/// The guarded gestures of the authored sprinkler source and the retained per-zone schedule editor.
@MainActor
@Suite(.demoHouse)
struct ServerUISprinklerSourceTests {
    typealias F = SprinklerFixture

    private func make(valve: String = "closed", mode: String = "auto") -> (ServerUISprinklerSource, EntityStore, RecordingCaller) {
        var (states, attributes) = F.frontStates(valve: valve)
        states[F.front.modeEntityId] = mode
        let store = makeStore(states, attributes: attributes)
        let caller = RecordingCaller()
        let descriptor = ServerUISprinklerDescriptor(controller: F.front, lowBatteryPercent: 20, defaultStartTime: "07:00")
        return (ServerUISprinklerSource(descriptor: descriptor, store: store, caller: caller), store, caller)
    }

    /// Lets Home Assistant "answer" so the optimistic overlay clears and the next gesture is accepted.
    private func settle(_ source: ServerUISprinklerSource) {
        source.controller.liveDidChange()
    }

    @Test func aWateringBlockerNamesWhyAZoneCannotStart() {
        let (source, store, _) = make()
        #expect(source.wateringBlocker == nil)
        set(store, F.front.modeEntityId, "off")
        #expect(source.wateringBlocker == "Turn on the sprinkler before starting watering.")
        set(store, F.front.modeEntityId, "auto")
        set(store, F.front.zones[0].valveEntityId, "open")
        #expect(source.wateringBlocker == "Stop the current watering before starting another zone.")
        set(store, F.front.stateEntityId, "unavailable")
        set(store, F.front.modeEntityId, "unavailable")
        #expect(source.wateringBlocker == "The sprinkler is unavailable.")
    }

    @Test func runTimesStayInsideTheConfiguredRangeForRealZones() {
        let (source, _, _) = make()
        #expect(source.duration(0) == SprinklersConfig.manualRunTime.default)
        source.setDuration(SprinklersConfig.manualRunTime.max, zone: 0)
        #expect(source.duration(0) == SprinklersConfig.manualRunTime.max && source.error == nil)
        source.setDuration(SprinklersConfig.manualRunTime.max + 1, zone: 0)
        #expect(source.error != nil && source.duration(0) == SprinklersConfig.manualRunTime.max)
        source.setDuration(SprinklersConfig.manualRunTime.min, zone: 99)
        #expect(source.duration(99) == SprinklersConfig.manualRunTime.default)
    }

    @Test func aZoneEditorIsRetainedAndAnUnknownZoneHasNone() throws {
        let (source, _, _) = make()
        let draft = try #require(source.draft(0))
        #expect(source.draft(0) === draft)
        #expect(source.draft(99) == nil)
        #expect(!source.protectsPublication)
        draft.update { $0.budget = 105 }
        #expect(source.protectsPublication, "unsaved edits hold publication")
    }

    @Test func aGestureHoldsPublicationUntilItFinishes() async {
        let (source, store, caller) = make()
        let task = source.start(.rainDelay(true))
        #expect(source.protectsPublication, "pinned synchronously, before the task first runs")
        #expect(await task.value)
        #expect(caller.calls.map(\.service) == ["turn_on"])
        #expect(source.protectsPublication, "the optimistic value is still pending")
        set(store, F.front.rainDelayEntityId, "on")
        settle(source)
        #expect(!source.controller.hasPendingCommands)
        #expect(!source.protectsPublication)
    }

    @Test func eachGestureCallsItsServiceAndAnUnavailableSprinklerRefusesThem() async {
        let (source, store, caller) = make()
        #expect(await source.perform(.smartWatering(false)))
        set(store, F.front.smartWateringEntityId, "off"); settle(source)
        #expect(await source.perform(.enabled(0, false)))
        set(store, F.front.zones[0].programEntityId, "off"); settle(source)
        #expect(await source.perform(.startProgram(0)))
        #expect(caller.calls.map { "\($0.domain).\($0.service)" } == ["switch.turn_off", "switch.turn_off", "bhyve.start_program"])
        #expect(source.error == nil)

        let (down, downStore, downCaller) = make()
        set(downStore, F.front.stateEntityId, "unavailable")
        set(downStore, F.front.modeEntityId, "unavailable")
        #expect(await down.perform(.rainDelay(true)) == false)
        #expect(down.error == "The sprinkler changed or is unavailable. Try again.")
        #expect(downCaller.calls.isEmpty)
    }

    @Test func gesturesNamingAMissingZoneOrAnUnavailableSwitchAreRefused() async {
        let (source, store, caller) = make()
        #expect(await source.perform(.enabled(9, true)) == false)
        #expect(await source.perform(.startProgram(9)) == false)
        #expect(await source.perform(.water(9)) == false)
        #expect(await source.perform(.stop) == false, "nothing is watering")
        set(store, F.front.rainDelayEntityId, "unavailable")
        #expect(await source.perform(.rainDelay(true)) == false)
        set(store, F.front.smartWateringEntityId, "unavailable")
        #expect(await source.perform(.smartWatering(true)) == false)
        #expect(caller.calls.isEmpty)
    }

    @Test func waterAndStopDriveTheZoneValve() async {
        let (source, store, caller) = make()
        source.setDuration(SprinklersConfig.manualRunTime.min, zone: 0)
        #expect(await source.perform(.water(0)))
        #expect(caller.calls.last?.service == "start_watering")
        set(store, F.front.zones[0].valveEntityId, "open"); settle(source)
        #expect(await source.perform(.water(0)) == false, "a second zone cannot start while one waters")
        #expect(await source.perform(.stop))
        #expect(caller.calls.last?.service == "stop_watering")
    }

    @Test func aFailedCallReportsFalseWithoutAnError() async {
        let (source, _, caller) = make()
        caller.failNext = true
        #expect(await source.perform(.rainDelay(true)) == false)
        #expect(source.controller.errorMessage != nil)
    }

    // MARK: - Draft

    @Test func theDraftTracksEditsTimesAndDiscard() throws {
        let (source, _, _) = make()
        let draft = try #require(source.draft(0))
        #expect(!draft.dirty && !draft.blocksExit && !draft.canSave)
        draft.update { $0.days.insert(2); $0.budget = 110 }
        #expect(draft.dirty && draft.blocksExit && draft.canSave)
        draft.addTime(); draft.addTime(); draft.addTime(); draft.addTime()
        #expect(draft.value.times.count == 4, "at most four start times")
        #expect(draft.value.times.last?.value == "07:00")
        #expect(!draft.canSave, "the added times repeat the default clock")
        let removable = try #require(draft.value.times.last?.id)
        draft.removeTime(removable)
        #expect(draft.value.times.count == 3)
        draft.discard()
        #expect(!draft.dirty && draft.value == draft.initial)
        draft.removeTime(try #require(draft.value.times.first?.id))
        #expect(draft.value.times.count == 1, "the last start time stays")
    }

    @Test func aDraftRefusesToSaveAnIncompleteOrInvalidSchedule() throws {
        let (source, _, _) = make()
        let draft = try #require(source.draft(0))
        draft.update { $0.days = [] }
        #expect(!draft.canSave)
        draft.update { $0.days = [1]; $0.budget = 103 }
        #expect(!draft.canSave, "the budget moves in steps of five")
        draft.update { $0.budget = 205 }
        #expect(!draft.canSave)
        draft.update { $0.budget = 100; $0.times = [.init(id: "a", value: "25:00")] }
        #expect(!draft.canSave, "a start time is a clock time")
        draft.update { $0.times = [.init(id: "a", value: "06:30"), .init(id: "b", value: "06:30")] }
        #expect(!draft.canSave, "start times are distinct")
        draft.update { $0.times = [] }
        #expect(!draft.canSave)
        draft.update { $0.days = [7]; $0.times = [.init(id: "a", value: "08:00")] }
        #expect(!draft.canSave, "weekdays run 0 through 6")
    }

    @Test func savingAppliesThePinnedValuesAndAFailureKeepsTheDraft() async throws {
        let (source, _, caller) = make()
        let draft = try #require(source.draft(0))
        draft.update { $0.days.insert(2) }
        #expect(draft.canSave)
        #expect(await draft.save())
        #expect(caller.calls.last?.service.isEmpty == false)
        #expect(!draft.dirty && draft.error == nil && !draft.busy)
        settle(source)

        draft.update { $0.budget = 120 }
        caller.failNext = true
        #expect(await draft.save() == false)
        #expect(draft.dirty && draft.error != nil)
        draft.update { $0.budget = 120 }
        #expect(draft.error == nil, "an edit clears the last failure")
    }

    @Test func aStaleOrUnsavableDraftSaysSoAndReloadNeedsAnUneditedDraft() async throws {
        let (source, store, _) = make()
        let draft = try #require(source.draft(0))
        #expect(await draft.save() == false)
        #expect(draft.error == "The schedule changed or is incomplete. Reload it before applying.")
        draft.update { $0.budget = 115 }
        draft.reload()
        #expect(draft.error == "Discard your changes before reloading the schedule.")
        draft.discard()
        #expect(draft.error == nil)
        var attributes = F.program(station: 1, days: [0, 2], times: ["09:00"])
        attributes["budget"] = .number(90)
        store.apply([EntityState(entityId: F.front.zones[0].programEntityId, state: "on", attributes: attributes)])
        #expect(draft.canSave == false)
        draft.reload()
        #expect(draft.value.days == [0, 2] && draft.value.budget == 90 && draft.value.times.map(\.value) == ["09:00"])
        #expect(!draft.dirty)
    }
}
