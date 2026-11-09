import Foundation
@testable import HassCore
import HassTestSupport
import Testing

extension ManualScheduler {
    /// Runs the live items scheduled with `delay`.
    func fire(_ delay: Duration) {
        for item in pending where item.delay == delay {
            item.cancelled = true
            item.work()
        }
    }
}

/// A clock tests move by hand.
@MainActor
final class TestClock {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
    func advance(_ seconds: TimeInterval) { now += seconds }
}

/// The controller with a recording caller, a manual scheduler and clock: what each control sends, what it shows
/// meanwhile, and when a queued clean starts or fails.
@MainActor
@Suite(.demoHouse)
struct VacuumControllerTests {
    typealias V = Vacuums
    let main = Vacuums.mainFloor

    /// The service name of a `script.<name>` id.
    func service(_ script: String) -> String { String(script.drop { $0 != "." }.dropFirst()) }

    /// Main Floor docked and ready, two rooms selected.
    func states(_ overrides: [String: String] = [:]) -> [String: String] {
        let m = main.vacuumMapId
        var states: [String: String] = [
            main.entityId: "docked", main.batteryEntityId: "87", main.errorEntityId: "No error", main.statusFlagEntityId: "none",
            main.dockControls!.dockStatusEntityId: "idle", main.dockControls!.mopAttachmentEntityId: "on", main.passesEntityId: "1",
            main.modeEntityId!: "vacuum_and_mop", main.fanEntityId!: "medium", main.waterEntityId!: "medium",
            "input_text.demo_main_floor_mode_1": "Vacuum & Mop", main.dockButtonEntityId!: "unknown",
        ]
        for zone in main.zones { states[zone.entityId] = "off" }
        for room in main.autoCleanDisabledRooms { states[room.entityId] = "off" }
        states.merge(overrides) { _, new in new }
        return states
    }

    func attributes() -> [String: [String: JSONValue]] {
        let m = main.vacuumMapId
        func options(_ values: [String]) -> [String: JSONValue] { ["options": .array(values.map(JSONValue.string))] }
        var attributes: [String: [String: JSONValue]] = [
            main.passesEntityId: options(["1", "2", "3"]),
            main.modeEntityId!: options(["vacuum", "mop", "vacuum_and_mop"]),
            main.fanEntityId!: options(["low", "medium", "high"]),
            main.waterEntityId!: options(["low", "medium", "high"]),
        ]
        for zone in main.zones {
            if let mop = zone.mopRequiredEntityId { attributes[mop] = ["mop_required": .bool(zone.title == "Kitchen")] }
        }
        return attributes
    }

    func make(_ overrides: [String: String] = [:], vacuum: VacuumConfig? = nil, services: Set<String>? = nil)
        -> (VacuumController, EntityStore, RecordingCaller, ManualScheduler, TestClock)
    {
        var all = states(overrides)
        for zone in main.zones { if let mop = zone.mopRequiredEntityId { all[mop] = all[mop] ?? "2026-10-10T00:00:00Z" } }
        let store = makeStore(all, attributes: attributes())
        let caller = RecordingCaller()
        let scheduler = ManualScheduler()
        let clock = TestClock()
        let controller = VacuumController(vacuum: vacuum ?? main, store: store, caller: caller, scheduler: scheduler, now: { clock.now })
        controller.services = services
        return (controller, store, caller, scheduler, clock)
    }

    func confirm(_ controller: VacuumController, _ store: EntityStore, _ id: String, _ state: String) {
        set(store, id, state)
        controller.liveDidChange()
    }

    // MARK: Status and labels

    @Test func readyVacuumShowsFullModeAndEveryTab() {
        let (vacuum, _, _, _, _) = make()
        #expect(vacuum.runtimeMode == .full)
        #expect(vacuum.tabs == [.controls, .zones, .autoClean, .more, .info])
        #expect(vacuum.batteryLabel == "87%")
        #expect(vacuum.dockLabel == "Idle")
        #expect(vacuum.statusState == "docked")
        #expect(vacuum.showsCleaningSetup)
        #expect(vacuum.roomsEditable)
        #expect(!vacuum.normalCommandsDisabled)
        #expect(vacuum.liveState == "docked")
        #expect(vacuum.observedEntityIds.contains(main.passesEntityId))
    }

    @Test func modeScopedReadsFollowTheGivenMode() {
        let (vacuum, _, _, _, _) = make()
        #expect(vacuum.tabs(in: .full) == vacuum.tabs)
        #expect(vacuum.tabs(in: .minimal) == [.controls, .autoClean, .info])
        #expect(vacuum.powerSettings(in: .minimal).isEmpty)
        #expect(vacuum.powerSettings(in: .full).map(\.title) == vacuum.powerSettings.map(\.title))
        #expect(vacuum.showsCleaningSetup(in: .full))
        #expect(!vacuum.showsCleaningSetup(in: .minimal))
    }

    @Test func unavailableVacuumShowsUnknowns() {
        let (vacuum, _, _, _, _) = make([main.entityId: "unavailable"])
        #expect(!vacuum.status.primaryAvailable)
        #expect(vacuum.batteryLabel == "Unknown")
        #expect(vacuum.dockLabel == "Unknown")
        #expect(vacuum.runtimeActions.isEmpty)
        #expect(vacuum.runtimeMode == .minimal)
        #expect(vacuum.powerSettings.isEmpty)
    }

    // MARK: Settings

    @Test func powerSettingsHideFanForMopAndWaterForVacuum() {
        let (vacuum, store, _, _, _) = make()
        #expect(vacuum.powerSettings.map(\.title) == ["Mode", "Fan", "Water"])
        #expect(vacuum.powerSettings[0].valueLabel == "Vacuum and Mop", "the mode text helper names the mode, spelled like the menu")
        set(store, main.modeEntityId!, "mop")
        #expect(vacuum.powerSettings.map(\.title) == ["Mode", "Water"])
        set(store, main.modeEntityId!, "vacuum")
        #expect(vacuum.powerSettings.map(\.title) == ["Mode", "Fan"])
        #expect(vacuum.powerSettings[0].valueLabel == "Vacuum and Mop", "the helper is shown until HA rewrites it (VacuumCard.tsx:1376), spelled like the menu")
        set(store, "input_text.demo_main_floor_mode_1", "Vacuum")
        #expect(vacuum.powerSettings[0].valueLabel == "Vacuum")
        set(store, "input_text.demo_main_floor_mode_1", "unknown")
        #expect(vacuum.powerSettings[0].valueLabel == "Vacuum", "without a meaningful helper the select value is formatted")
        set(store, main.fanEntityId!, "unavailable")
        #expect(vacuum.powerSettings.map(\.title) == ["Mode"])
    }

    @Test func passesShowAsMultipliers() throws {
        let (vacuum, _, _, _, _) = make()
        let passes = try #require(vacuum.passesSetting)
        #expect(passes.valueLabel == "1x")
        #expect(passes.options == ["1", "2", "3"])
        #expect(passes.label(for: "2") == "2x")
        #expect(vacuum.powerSettings[1].label(for: "high") == "High")
    }

    @Test func selectShowsTheIntentUntilConfirmed() async {
        let (vacuum, store, caller, scheduler, _) = make()
        vacuum.select(main.passesEntityId, option: "2")
        #expect(vacuum.displayedValue(main.passesEntityId) == "2")
        #expect(vacuum.passesSetting?.valueLabel == "2x")
        await vacuum.waitForCalls()
        #expect(caller.calls.last == .init(domain: "input_select", service: "select_option", data: ["entity_id": main.passesEntityId, "option": "2"]))
        vacuum.select(main.passesEntityId, option: "2")
        await vacuum.waitForCalls()
        #expect(caller.calls.count == 1, "re-picking the shown value sends nothing")
        confirm(vacuum, store, main.passesEntityId, "2")
        #expect(scheduler.pending.filter { $0.delay == VacuumController.optimisticRevert }.isEmpty)

        vacuum.select(main.passesEntityId, option: "3")
        scheduler.fire(VacuumController.optimisticRevert)
        #expect(vacuum.displayedValue(main.passesEntityId) == "2", "an unconfirmed intent expires")
    }

    // MARK: Rooms

    @Test func roomsKeepSelectionOrderAndSetTheMode() async {
        let (vacuum, store, caller, _, clock) = make([V.mainFloor.zones[0].entityId: "on"])
        let kitchen = main.zones.first { $0.title == "Kitchen" }!
        let office = main.zones.first { $0.title == "Office" }!
        #expect(vacuum.selectedZones.map(\.title) == ["Living Room"])
        clock.advance(1)
        vacuum.toggleRoom(office)
        clock.advance(1)
        vacuum.toggleRoom(kitchen)
        #expect(vacuum.selectedZones.map(\.title) == ["Living Room", "Office", "Kitchen"])
        #expect(vacuum.order(of: kitchen) == 3)
        #expect(vacuum.order(of: main.zones[1]) == nil)
        await vacuum.waitForCalls()
        #expect(caller.calls.contains(.init(domain: "input_boolean", service: "turn_on", data: ["entity_id": office.entityId])))
        // Office alone needs no mop; the mode drops to vacuum, then Kitchen brings mopping back.
        #expect(caller.calls.contains(.init(domain: "select", service: "select_option",
                                            data: ["entity_id": main.modeEntityId!, "option": "vacuum"])))
        #expect(vacuum.displayedValue(main.modeEntityId!) == "vacuum_and_mop")

        vacuum.toggleRoom(kitchen)
        #expect(!vacuum.isSelected(kitchen))
        confirm(vacuum, store, office.entityId, "on")
        #expect(vacuum.isSelected(office))
    }

    @Test func roomsLockOutsideFullMode() async {
        let (vacuum, _, caller, _, _) = make([main.entityId: "cleaning"])
        #expect(!vacuum.roomsEditable)
        vacuum.toggleRoom(main.zones[0])
        await vacuum.waitForCalls()
        #expect(caller.calls.isEmpty)
    }

    @Test func turningARoomOnDiscardsTheArea() {
        let (vacuum, _, _, _, _) = make()
        vacuum.areaSelection = .init(x0: 1, x1: 9, y0: 1, y1: 9)
        #expect(vacuum.roomToggleNeedsConfirmation(main.zones[0]))
        vacuum.toggleRoom(main.zones[0])
        #expect(vacuum.areaSelection == nil)
        #expect(!vacuum.roomToggleNeedsConfirmation(main.zones[0]), "turning a room off never asks")
    }

    @Test func drawingAnAreaClearsSelectedRooms() async {
        let (vacuum, _, caller, _, _) = make([main.zones[0].entityId: "on", main.zones[2].entityId: "on"])
        vacuum.clearRoomsForArea()
        #expect(vacuum.selectedZones.isEmpty)
        await vacuum.waitForCalls()
        #expect(caller.calls.filter { $0.service == "turn_off" }.count == 2)
    }

    @Test func roomMopHintsFallBackToConfig() {
        let (vacuum, _, _, _, _) = make()
        #expect(vacuum.requiresMop(main.zones.first { $0.title == "Kitchen" }!))
        #expect(!vacuum.requiresMop(main.zones[0]))
        #expect(vacuum.requiresMop(Vacuums.musicRoom.zones[0]))
        #expect(vacuum.requiresMop(.init(title: "X", entityId: "input_boolean.demo_x", icon: "mdi:sofa")))
    }

    // MARK: Cleaning

    @Test func cleanStartsAtOnceWhenSettingsAreSettled() async {
        let (vacuum, store, caller, scheduler, _) = make()
        vacuum.run(.clean)
        #expect(vacuum.cleanStartPending)
        #expect(vacuum.controlsDisabled)
        #expect(vacuum.state == "cleaning")
        await vacuum.waitForCalls()
        #expect(caller.calls.last == .init(domain: "script", service: service(main.cleanScript), data: [:]))
        confirm(vacuum, store, main.entityId, "cleaning")
        #expect(!vacuum.cleanStartPending)
        #expect(vacuum.cleanError == nil)
        scheduler.fire(VacuumController.cleanStartRevert)
        #expect(vacuum.cleanError == nil)
    }

    @Test func cleanWaitsForSettingsToConfirmAndGoQuiet() async {
        let (vacuum, store, caller, scheduler, clock) = make()
        vacuum.select(main.passesEntityId, option: "2")
        vacuum.run(.clean)
        #expect(vacuum.queuedClean != nil)
        await vacuum.waitForCalls()
        #expect(!caller.calls.contains { $0.domain == "script" })

        clock.advance(0.2)
        confirm(vacuum, store, main.passesEntityId, "2")
        let settle = scheduler.pending.first { $0.delay < .seconds(1) }
        #expect(settle != nil, "a settle check waits out the quiet window")
        clock.advance(1)
        for item in scheduler.pending where item.delay < .seconds(1) { item.cancelled = true; item.work() }
        await vacuum.waitForCalls()
        #expect(caller.calls.last?.domain == "script")
        #expect(vacuum.queuedClean == nil)
    }

    @Test func settleCheckReschedulesWhileStillNoisy() async {
        let (vacuum, store, caller, scheduler, clock) = make()
        vacuum.select(main.passesEntityId, option: "2")
        vacuum.run(.clean)
        confirm(vacuum, store, main.passesEntityId, "2")
        // Still inside the quiet window when the check fires: it checks again.
        for item in scheduler.pending where item.delay < .seconds(1) { item.cancelled = true; item.work() }
        #expect(vacuum.queuedClean != nil)
        clock.advance(1)
        for item in scheduler.pending where item.delay < .seconds(1) { item.cancelled = true; item.work() }
        await vacuum.waitForCalls()
        #expect(caller.calls.last?.domain == "script")
    }

    @Test func queuedCleanCancelsWhenTheVacuumStopsBeingReady() async {
        let (vacuum, store, caller, scheduler, clock) = make()
        vacuum.select(main.passesEntityId, option: "2")
        vacuum.run(.clean)
        #expect(vacuum.queuedClean != nil)
        clock.advance(0.2)
        set(store, main.errorEntityId, "Robot stuck or trapped")
        confirm(vacuum, store, main.passesEntityId, "2")
        clock.advance(1)
        for item in scheduler.pending where item.delay < .seconds(1) { item.cancelled = true; item.work() }
        await vacuum.waitForCalls()
        #expect(vacuum.cleanError == "The queued cleaning request was canceled because the vacuum is no longer ready. Retry when ready.")
        #expect(vacuum.queuedClean == nil && !vacuum.cleanStartPending)
        #expect(!caller.calls.contains { $0.domain == "script" }, "nothing is sent to a robot that is no longer ready")
    }

    @Test func cleanFailsWhenTheVacuumNeverStarts() {
        let (vacuum, _, _, scheduler, _) = make()
        vacuum.run(.clean)
        for item in scheduler.pending where item.delay == VacuumController.cleanStartRevert { item.cancelled = true; item.work() }
        #expect(vacuum.cleanError == "The vacuum did not begin cleaning within 30 seconds.")
        #expect(!vacuum.cleanStartPending)
        #expect(vacuum.state == "docked")
    }

    @Test func cleanFailsWhenSettingsNeverConfirm() {
        let (vacuum, _, _, scheduler, _) = make()
        vacuum.select(main.passesEntityId, option: "3")
        vacuum.run(.clean)
        scheduler.fire(VacuumController.optimisticRevert)
        #expect(vacuum.cleanError == "The vacuum settings did not confirm before cleaning could start.")
        #expect(vacuum.queuedClean == nil)
    }

    @Test func queuedCleanCancelsWhenTheVacuumIsNoLongerReady() {
        let (vacuum, store, _, _, _) = make()
        vacuum.select(main.passesEntityId, option: "3")
        vacuum.run(.clean)
        confirm(vacuum, store, main.errorEntityId, "Stuck")
        #expect(vacuum.cleanError == "The queued cleaning request was canceled because the vacuum is no longer ready. Retry when ready.")
    }

    @Test func cleanIsRefusedWhenRestricted() async {
        let (vacuum, _, caller, _, _) = make([main.errorEntityId: "Stuck"])
        vacuum.run(.clean)
        await vacuum.waitForCalls()
        #expect(caller.calls.isEmpty)
        #expect(vacuum.cleanError?.contains("no longer ready") == true)
    }

    @Test func rejectedCleanReportsTheFailure() async {
        let (vacuum, _, caller, _, _) = make()
        caller.failNext = true
        vacuum.run(.clean)
        await vacuum.waitForCalls()
        #expect(vacuum.cleanError == "Home Assistant rejected the cleaning request.")
    }

    @Test func areaCleanSendsTheRectangleInCentimetres() async {
        let (vacuum, _, caller, _, _) = make(services: [main.areaCleaning!.script])
        #expect(vacuum.supportsAreaCleaning)
        #expect(vacuum.areaCleanAction(mapReady: true, selectionAllowed: true).isDisabled, "no area yet")
        vacuum.areaSelection = .init(x0: 10, x1: 20, y0: 30, y1: 40)
        #expect(!vacuum.areaCleanAction(mapReady: true, selectionAllowed: true).isDisabled)
        #expect(vacuum.areaCleanAction(mapReady: false, selectionAllowed: true).isDisabled)
        #expect(vacuum.areaCleanAction(mapReady: true, selectionAllowed: false).isDisabled)
        vacuum.run(.cleanArea)
        #expect(!vacuum.cleanStartPending, "no pixel size, no call")
        vacuum.run(.cleanArea, pixelSize: 5)
        await vacuum.waitForCalls()
        #expect(caller.calls.last == .init(domain: "script", service: service(main.areaCleaning!.script),
                                           data: ["x_min_cm": "50", "x_max_cm": "100", "y_min_cm": "150", "y_max_cm": "200"]))
        let (noScript, _, _, _, _) = make(services: [])
        noScript.areaSelection = .init(x0: 10, x1: 20, y0: 30, y1: 40)
        #expect(!noScript.areaServiceReady)
        #expect(noScript.areaCleanAction(mapReady: true, selectionAllowed: true).isDisabled)
    }

    // MARK: Runtime actions

    func titles(_ vacuum: VacuumController) -> [String] { vacuum.runtimeActions.map(\.title) }

    @Test func actionsFollowTheState() {
        #expect(titles(make([main.entityId: "docked"]).0).isEmpty)
        #expect(titles(make([main.entityId: "idle"]).0) == ["Dock"])
        #expect(titles(make([main.entityId: "error", main.errorEntityId: "Stuck"]).0) == ["Stop", "Dock"])
        #expect(titles(make([main.entityId: "error", main.errorEntityId: "Low battery"]).0).isEmpty)
        #expect(titles(make([main.entityId: "docked", main.statusFlagEntityId: "resumable"]).0) == ["Resume", "Cancel"])
        #expect(titles(make([main.entityId: "returning", main.statusFlagEntityId: "resumable"]).0) == ["Cancel", "Pause"])
        #expect(titles(make([main.entityId: "cleaning"]).0) == ["Pause", "Stop"])
        #expect(titles(make([main.entityId: "paused"]).0) == ["Resume", "Stop"])
        #expect(titles(make([main.entityId: "returning"]).0) == ["Pause"])
        let prep = make([main.entityId: "cleaning", main.dockControls!.dockStatusEntityId: "cleaning"]).0
        #expect(prep.dockPreparationActive)
        #expect(titles(prep) == ["Pause", "Cancel Cleaning Session"])
        #expect(prep.runtimeActions[0].isDisabled)
    }

    @Test func actionsSendTheWebServicesWithOptimisticState() async {
        func sent(_ overrides: [String: String], _ kind: VacuumController.Action.Kind) async -> (String, String) {
            let (vacuum, _, caller, _, _) = make(overrides)
            vacuum.run(kind)
            await vacuum.waitForCalls()
            return (caller.calls.last.map { "\($0.domain).\($0.service)" } ?? "none", vacuum.state)
        }
        #expect(await sent([main.entityId: "idle"], .dock) == ("vacuum.return_to_base", "returning"))
        #expect(await sent([main.entityId: "error", main.errorEntityId: "Stuck"], .stop) == ("vacuum.stop", "idle"))
        #expect(await sent([main.entityId: "cleaning"], .stop) == ("vacuum.return_to_base", "returning"))
        #expect(await sent([main.entityId: "cleaning"], .cancelSession) == ("vacuum.return_to_base", "docked"))
        #expect(await sent([main.entityId: "cleaning"], .pause) == ("vacuum.pause", "paused"))
        #expect(await sent([main.entityId: "paused"], .resume) == ("vacuum.start", "cleaning"))
        #expect(await sent([main.entityId: "unavailable"], .dock) == ("none", "unavailable"))

        let (resumable, _, caller, _, _) = make([main.entityId: "docked", main.statusFlagEntityId: "resumable"])
        resumable.run(.cancelResume)
        await resumable.waitForCalls()
        #expect(caller.calls.last?.service == "stop")
        #expect(resumable.state == "docked")
        #expect(resumable.runtimeActions.allSatisfy { $0.isDisabled }, "buttons wait for the flag to clear")
    }

    @Test func returnHomeFromAnErrorStaysOptimisticThroughALiveFlap() async {
        let (vacuum, store, caller, scheduler, _) = make([main.entityId: "error", main.errorEntityId: "Cannot reach target"])
        vacuum.run(.dock)
        await vacuum.waitForCalls()
        #expect(caller.calls.last?.service == "return_to_base")
        #expect(vacuum.state == "returning")
        confirm(vacuum, store, main.entityId, "idle")
        #expect(vacuum.state == "returning", "a state the robot passes through does not drop the tap's result")
        confirm(vacuum, store, main.entityId, "returning")
        #expect(vacuum.state == "returning")
        confirm(vacuum, store, main.entityId, "docked")
        #expect(vacuum.state == "docked")
        scheduler.fire(VacuumController.optimisticRevert)
    }

    @Test func returnHomeFromAnErrorRevertsWhenNothingConfirms() async {
        let (vacuum, _, _, scheduler, _) = make([main.entityId: "error", main.errorEntityId: "Cannot reach target"])
        vacuum.run(.dock)
        await vacuum.waitForCalls()
        #expect(vacuum.state == "returning")
        scheduler.fire(VacuumController.optimisticRevert)
        #expect(vacuum.state == "error")
    }

    @Test func robotErrorTextReadsInPlainWords() {
        #expect(VacuumFormat.issue("Cannot reach target") == "Can't reach its room. A door may be closed. Open it, then tap Resume.")
        #expect(VacuumFormat.issue("  cannot reach target ") == VacuumFormat.issue("Cannot reach target"))
        #expect(VacuumFormat.issue("Stuck") == "Stuck")
    }

    @Test func locateAndEmptyBin() async {
        let (vacuum, _, caller, _, _) = make()
        vacuum.locate()
        vacuum.run(.emptyBin)
        await vacuum.waitForCalls()
        #expect(caller.calls.map(\.service) == ["locate", "press"])
        #expect(caller.calls[1].data["entity_id"] == main.dockButtonEntityId!)
    }

    // MARK: Dock

    @Test func dockActionsNeedTheBridgeMopsAndADockedRobot() async {
        let ready: Set<String> = ["valetudo_vacuum_coordinator.dock_action", main.dockControls!.cleanScript, main.dockControls!.dryScript]
        let (vacuum, store, caller, _, _) = make(services: ready)
        #expect(vacuum.dockActions.map(\.title) == ["Clean Mop Dock", "Dry Mops", "Empty Bin"])
        #expect(vacuum.dockActions.allSatisfy { !$0.isDisabled })
        vacuum.run(.cleanDock)
        await vacuum.waitForCalls()
        #expect(caller.calls.last == .init(domain: "script", service: service(main.dockControls!.cleanScript), data: [:]))
        #expect(vacuum.dockActions.first?.title == "Stop Dock Clean")
        confirm(vacuum, store, main.dockControls!.dockStatusEntityId, "cleaning")
        confirm(vacuum, store, main.dockControls!.dockStatusEntityId, "drying")
        // A drying dock is busy, so commands are restricted and only the active dock action shows (VacuumCard.tsx:456).
        #expect(vacuum.runtimeMode == .minimal)
        #expect(vacuum.dockActions.map(\.title) == ["Stop Mop Drying"])
        #expect(!vacuum.dockActions[0].isDisabled, "stopping stays allowed while restricted")
        vacuum.run(.stopDrying)
        await vacuum.waitForCalls()
        #expect(caller.calls.last?.service == service(main.dockControls!.dryScript))

        let (noBridge, _, _, _, _) = make(services: [])
        #expect(!noBridge.dockBridgeAvailable)
        #expect(noBridge.dockActions[0].isDisabled)
        let (noMops, _, noMopCalls, _, _) = make([main.dockControls!.mopAttachmentEntityId: "off"], services: ready)
        #expect(!noMops.mopAttached)
        noMops.run(.dryMops)
        await noMops.waitForCalls()
        #expect(noMopCalls.calls.isEmpty, "a disabled dock action sends nothing")
    }

    @Test func minimalModeShowsOnlyTheActiveDockCycle() {
        let ready: Set<String> = ["valetudo_vacuum_coordinator.dock_action", main.dockControls!.cleanScript, main.dockControls!.dryScript]
        let (vacuum, _, _, _, _) = make([main.statusFlagEntityId: "resumable", main.dockControls!.dockStatusEntityId: "drying"], services: ready)
        #expect(vacuum.runtimeMode == .minimal)
        #expect(vacuum.dockActions.map(\.title) == ["Stop Mop Drying"])
        #expect(vacuum.tabs.contains(.more))
    }

    // MARK: Auto-clean rooms

    @Test func autoCleanRoomsFlipWithConfirmation() async {
        let (vacuum, store, caller, scheduler, _) = make()
        let room = main.autoCleanDisabledRooms[0]
        vacuum.toggleAutoClean(room)
        #expect(vacuum.isAutoCleanDisabled(room))
        await vacuum.waitForCalls()
        #expect(caller.calls.last == .init(domain: "switch", service: "turn_on", data: ["entity_id": room.entityId]))
        confirm(vacuum, store, room.entityId, "on")
        #expect(vacuum.isAutoCleanDisabled(room))
        vacuum.toggleAutoClean(room)
        scheduler.fire(VacuumController.optimisticRevert)
        #expect(vacuum.isAutoCleanDisabled(room), "an unconfirmed change reverts")

        let (offline, _, offlineCalls, _, _) = make([room.entityId: "unavailable"])
        offline.toggleAutoClean(room)
        await offline.waitForCalls()
        #expect(offlineCalls.calls.isEmpty)
    }

    // MARK: Report

    @Test func whileAwayAppliesReconciliations() {
        let (vacuum, store, _, _, _) = make()
        #expect(vacuum.whileAway == .empty)
        set(store, main.coordinatorSessionEntityId!, "idle", ["while_away_outcomes": VacuumOutcomeFixtures.sample])
        guard case let .typed(contract) = vacuum.whileAway else { Issue.record("typed"); return }
        #expect(contract.rooms[2].status == .interrupted)
        set(store, "input_text.demo_living_room_2", "e3")
        guard case let .typed(reconciled) = vacuum.whileAway else { Issue.record("typed"); return }
        #expect(reconciled.rooms[2].status == .completed)
    }

    @Test func servicesAndActionHelpers() {
        let (vacuum, _, _, _, _) = make()
        #expect(!vacuum.hasService("script.demo_x"))
        vacuum.services = ["script.demo_x"]
        #expect(vacuum.hasService("script.demo_x"))
        let call = ServiceCall.action("script.demo_go", data: ["a": .number(1)])
        #expect(call.domain == "script" && call.service == "demo_go" && call.target == nil)
        #expect(ServiceCall.action("bare").service == "")
        #expect(HassServices.names(["script": ["demo_a": [:], "demo_b": [:]] as [String: Any], "light": "bad"]) == ["script.demo_a", "script.demo_b"])
        #expect(VacuumController.Action(kind: .dock, title: "Dock", icon: "mdi:home", tone: .neutral, detail: nil, isDisabled: false).id == "dock")
    }

    @Test func liveObservationConfirmsWithoutAManualPoke() async throws {
        let (vacuum, store, _, _, _) = make()
        vacuum.select(main.passesEntityId, option: "2")
        set(store, main.passesEntityId, "2")
        for _ in 0..<20 where vacuum.intentRevision < 2 { await Task.yield() }
        #expect(vacuum.intentRevision >= 2)
    }
}

/// The page's Auto-Clean tiles.
@MainActor
@Suite(.demoHouse)
struct VacuumAutoCleanControllerTests {
    @Test func tilesFlipAndConfirm() async {
        let pause = Vacuums.autoCleanControls[0], music = Vacuums.autoCleanControls[1]
        let store = makeStore([pause.entityId: "off", music.entityId: "off"])
        let caller = RecordingCaller()
        let scheduler = ManualScheduler()
        let controller = VacuumAutoCleanController(store: store, caller: caller, scheduler: scheduler)
        #expect(controller.display(pause) == .init(isEnabled: true, isUnavailable: false, subtitle: "Enabled"))
        #expect(controller.display(music).subtitle == "Paused")
        #expect(controller.display(Vacuums.autoCleanControls[2]).isUnavailable)

        controller.toggle(pause)
        #expect(controller.display(pause).subtitle == "Paused")
        controller.toggle(music)
        await controller.waitForCalls()
        #expect(caller.calls == [.init(domain: "switch", service: "turn_on", data: ["entity_id": pause.entityId]),
                                 .init(domain: "automation", service: "turn_on", data: ["entity_id": music.entityId])])
        scheduler.fireAll()
        #expect(controller.display(pause).isEnabled, "unconfirmed changes revert")
        #expect(controller.display(pause).isFailed, "and say so for 4 s")
        scheduler.fireAll()
        #expect(controller.display(pause).subtitle == "Enabled")

        caller.failNext = true
        controller.toggle(music)
        await controller.waitForCalls()
        #expect(!controller.display(music).isEnabled, "a rejected call reverts at once")
        #expect(controller.display(music).isFailed)
        #expect(controller.display(music).subtitle == "Didn't Respond")
        scheduler.fireAll()
        #expect(controller.display(music).subtitle == "Paused")

        controller.toggle(Vacuums.autoCleanControls[2])
        await controller.waitForCalls()
        #expect(caller.calls.count == 3)
    }

    @Test func liveChangesConfirm() async {
        let music = Vacuums.autoCleanControls[1]
        let store = makeStore([music.entityId: "off"])
        let controller = VacuumAutoCleanController(store: store, caller: RecordingCaller(), scheduler: ManualScheduler())
        controller.toggle(music)
        set(store, music.entityId, "on")
        for _ in 0..<20 where controller.overlay.pending[music.entityId] != nil { await Task.yield() }
        #expect(controller.overlay.pending[music.entityId] == nil)
        #expect(controller.display(music).isEnabled)
    }
}

/// The map loader with an injected fetch.
@MainActor
@Suite(.demoHouse)
struct ValetudoMapLoaderTests {
    @Test func loadsLiveAndReportedMaps() async throws {
        let png = try valetudoPNG(sampleMapJSON)
        let loader = ValetudoMapLoader { _ in png }
        let url = URL(string: "https://example.invalid/api/camera_proxy/camera.demo_x?token=1")!
        await loader.load(from: url, live: true)
        #expect(loader.provenance == .live)
        #expect(loader.map?.entities.count == 2)
        await loader.load(from: url, live: false)
        #expect(loader.provenance == .reported)
        #expect(loader.map?.entities.map(\.type) == ["robot_position"], "reported maps drop transient paths")
    }

    @Test func keepsTheLastMapWhenALoadFails() async throws {
        let png = try valetudoPNG(sampleMapJSON)
        let fail = FailSwitch()
        let loader = ValetudoMapLoader { _ in
            if await fail.on { throw URLError(.timedOut) }
            return png
        }
        let url = URL(string: "https://example.invalid/map")!
        await loader.load(from: url, live: true)
        await fail.set(true)
        await loader.load(from: url, live: true)
        #expect(loader.map != nil && !loader.failed)

        let empty = ValetudoMapLoader { _ in Data("nope".utf8) }
        await empty.load(from: url, live: true)
        #expect(empty.failed && empty.map == nil)
    }

    @Test func runStopsAfterOneReportedLoadAndWithoutAURL() async throws {
        let png = try valetudoPNG(sampleMapJSON)
        let counter = FailSwitch()
        let loader = ValetudoMapLoader { _ in await counter.count(); return png }
        await loader.run(url: URL(string: "https://example.invalid/map")!, live: false)
        #expect(await counter.calls == 1)
        await loader.run(url: nil, live: true)
        #expect(loader.provenance == .reported, "no URL keeps the map")
        let blank = ValetudoMapLoader { _ in png }
        await blank.run(url: nil, live: true)
        #expect(blank.provenance == .none)
        blank.show(ValetudoMapFixtures.map(Vacuums.musicRoom.vacuumMapId), provenance: .live)
        #expect(blank.provenance == .live)
        blank.show(nil, provenance: .live)
        #expect(blank.provenance == .none)
    }

    @Test func livePollingStopsOnCancel() async throws {
        let png = try valetudoPNG(sampleMapJSON)
        let loader = ValetudoMapLoader { _ in png }
        let task = Task { await loader.run(url: URL(string: "https://example.invalid/map")!, live: true) }
        for _ in 0..<50 where loader.map == nil { await Task.yield() }
        task.cancel()
        await task.value
        #expect(loader.map != nil)
    }

    @Test func pictureURLResolvesAgainstTheServer() {
        let server = HassServer(baseURL: URL(string: "https://ha.example.invalid")!)
        let entity = EntityState(entityId: "camera.demo_x", state: "idle", attributes: ["entity_picture": .string("/api/camera_proxy/camera.demo_x?token=abc")])
        #expect(ValetudoMapLoader.pictureURL(entity, server: server)?.absoluteString == "https://ha.example.invalid/api/camera_proxy/camera.demo_x?token=abc")
        #expect(ValetudoMapLoader.pictureURL(nil, server: server) == nil)
    }
}

/// Shared mutable test state for fetch closures.
actor FailSwitch {
    var on = false
    var calls = 0
    func set(_ value: Bool) { on = value }
    func count() { calls += 1 }
}
