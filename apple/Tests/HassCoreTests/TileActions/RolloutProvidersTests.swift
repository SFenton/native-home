import Foundation
@testable import HassCore
import HassTestSupport
import Testing

private func entity(_ id: String, _ state: String, _ attributes: [String: JSONValue] = [:]) -> EntityState {
    EntityState(entityId: id, state: state, attributes: attributes)
}

/// The feedback contract every rollout provider obeys (the same one `TileActionProvidersTests` states for the first six).
private func assertContract(_ specs: [TileActionSpec], sourceLocation: SourceLocation = #_sourceLocation) {
    for spec in specs {
        #expect(spec.call?.service != "toggle", "\(spec.id) must use an explicit service", sourceLocation: sourceLocation)
        if spec.feedback == .momentary {
            #expect(spec.phase != .inFlight, "momentary \(spec.id) never shows a spinner", sourceLocation: sourceLocation)
            #expect(spec.optimistic.isEmpty && spec.tracking.isEmpty, "momentary \(spec.id) shows nothing", sourceLocation: sourceLocation)
        }
        if spec.feedback == .tracked { #expect(spec.optimistic.isEmpty, "tracked \(spec.id) never swaps optimistically", sourceLocation: sourceLocation) }
        if spec.feedback != .tracked { #expect(spec.tracking.isEmpty, "only tracked \(spec.id) holds a tracking value", sourceLocation: sourceLocation) }
    }
}

// MARK: - Spec

@Suite(.demoHouse)
struct TileActionSpecExtrasTests {
    @Test func aSpecDefaultsToNoConfirmationSelectionLabelOrTracking() {
        let spec = TileActionSpec(id: "a", verb: "Go", symbol: "bolt", feedback: .momentary)
        #expect(spec.confirmation == nil && spec.selection == nil && spec.label == nil && spec.tracking.isEmpty)
    }

    @Test func aConfirmationCanBeAddedWithoutChangingTheRest() {
        let ask = TileActionSpec.Confirmation(title: "Sure?", confirmVerb: "Yes")
        let spec = TileActionSpec(id: "a", verb: "Go", symbol: "bolt", feedback: .momentary).with(confirmation: ask)
        #expect(spec.confirmation == ask && spec.id == "a")
        #expect(ask.style == .alert && !ask.isDestructive && ask.message == nil)
    }

    @Test func selectionReadsChosenAndPosition() {
        #expect(TileActionSpec.Selection.single(isSelected: true).isSelected)
        #expect(!TileActionSpec.Selection.single(isSelected: false).isSelected)
        #expect(TileActionSpec.Selection.ordered(position: 2).isSelected && TileActionSpec.Selection.ordered(position: 2).position == 2)
        #expect(!TileActionSpec.Selection.ordered(position: nil).isSelected)
        #expect(TileActionSpec.Selection.single(isSelected: true).position == nil)
    }

    @Test func aCustomActionMakesTheSlotSetCustom() {
        let custom = TileActionSpec(id: "x", verb: "Go", symbol: "bolt", feedback: .momentary)
        let runnable = TileActionSpec(id: "x", verb: "Go", symbol: "bolt", feedback: .momentary, call: ServiceCall("a", "b"))
        #expect(TileActionSlotSet([custom]).hasCustom && !TileActionSlotSet([runnable]).hasCustom)
    }
}

// MARK: - Command

@Suite(.demoHouse)
struct CommandActionsTests {
    @Test func powerRecoveryIsOneMomentaryBoltDisc() throws {
        let live = EntityState(entityId: HouseholdSettingsConfig.Admin.powerRecoveryAutomation, state: "on")
        let specs = CommandActions.powerRecovery.actions(for: live)
        assertContract(specs)
        let spec = try #require(specs.first)
        #expect(specs.count == 1 && spec.id == "power_recovery" && spec.symbol == "bolt.fill" && spec.feedback == .momentary)
        #expect(spec.phase == .ready, "the automation is there: runnable")
        #expect(CommandActions.powerRecovery.actions(for: nil)[0].phase == .unavailable, "no automation: dimmed")
        #expect(spec.isOn == nil, "momentary-styled, not a toggle")
        #expect(spec.call == ServiceCall("automation", "trigger", target: "automation.demo_living_room_power_1"))
        #expect(spec.label == "Run power recovery" && spec.confirmation == nil)
    }

    @Test func anAvailabilityEntityDimsTheDiscInPlace() throws {
        let provider = CommandActions(verb: "Run", symbol: "bolt.fill", call: ServiceCall("script", "go"), availabilityEntityId: "script.demo_go")
        #expect(provider.actions(for: entity("script.demo_go", "off")).first?.phase == .ready)
        for state in [nil, entity("script.demo_go", "unavailable"), entity("script.demo_go", "unknown")] {
            let spec = try #require(provider.actions(for: state).first)
            #expect(spec.phase == .unavailable && spec.id == "command" && spec.call != nil, "dims in place, keeps its id")
        }
    }

    @Test func aCommandCanBeConfirmed() throws {
        let ask = TileActionSpec.Confirmation(title: "Run?", confirmVerb: "Run")
        let provider = CommandActions(verb: "Run", symbol: "bolt", call: ServiceCall("script", "go"), confirmation: ask)
        #expect(provider.actions(for: nil).first?.confirmation == ask)
    }

    @Test func stateTextCoversTheFailedFace() {
        #expect(CommandActions.powerRecovery.stateTextCandidates.contains("Didn't Respond"))
    }
}

// MARK: - Source select

@Suite(.demoHouse)
struct SourceSelectActionsTests {
    typealias M = MediaRemotes.MusicRoom
    private var source: String { M.activeMediaSourceEntityId }
    private func spec(_ s: SourceSelectActions.MusicRoomSource, _ state: String?) throws -> TileActionSpec {
        let specs = SourceSelectActions.musicRoom(s).actions(for: state.map { entity(source, $0) })
        assertContract(specs)
        #expect(specs.count == 1 && specs[0].id == "source", "one stable action, so the check swaps in place")
        return specs[0]
    }

    @Test func eachSourceIsChosenOnlyWhenTheSensorNamesIt() throws {
        let expectations: [(SourceSelectActions.MusicRoomSource, [String])] = [
            (.console, [M.Source.xbox, M.Source.fortnite]), (.server, [M.Source.server]),
            (.pc, [M.Source.windowsPC]), (.launcher, [M.Source.fortnite]),
        ]
        for (item, chosen) in expectations {
            for state in [M.Source.xbox, M.Source.server, M.Source.windowsPC, M.Source.fortnite, "TV", "Off"] {
                let s = try spec(item, state)
                #expect(s.selection == .single(isSelected: chosen.contains(state)), "\(item) at \(state)")
                #expect(s.symbol == (chosen.contains(state) ? "checkmark" : "circle"))
            }
        }
    }

    @Test func fortniteMakesXboxAndFortniteBothRead() throws {
        #expect(try spec(.console, M.Source.fortnite).selection == .single(isSelected: true))
        #expect(try spec(.launcher, M.Source.fortnite).selection == .single(isSelected: true))
        #expect(try spec(.server, M.Source.fortnite).selection == .single(isSelected: false))
    }

    @Test func tappingAnUnselectedSourceRunsItsScriptWithTodaysValues() throws {
        var scripts: [ServiceCall?] = []
        for item in SourceSelectActions.MusicRoomSource.allCases {
            let s = try spec(item, "Off")
            #expect(s.call?.domain == "script", "\(item)")
            #expect(s.verb == "Select" && s.label == nil && s.feedback == .optimistic && s.phase == .ready)
            #expect(s.optimistic.contains { $0.entityId == source }, "the source moves at once")
            scripts.append(s.call)
        }
        #expect(Set(scripts.map { $0?.service }).count == scripts.count, "each source runs its own script")
    }

    @Test func tappingTheSelectedSourceTurnsTheTvOffAndSaysSo() throws {
        var offCalls: [ServiceCall?] = []
        for item in [SourceSelectActions.MusicRoomSource.console, .server, .pc] {
            let state = SourceSelectActions.musicRoom(item).selectedStates[0]
            let s = try spec(item, state)
            #expect(s.call?.domain == "script", "\(item)")
            #expect(s.label == "Turn Off TV" && s.verb == "Turn Off TV", "the check disc's VoiceOver label")
            #expect(s.optimistic.contains { $0.entityId == source && $0.value == "Off" }, "the source returns to Off at once")
            offCalls.append(s.call)
        }
        #expect(Set(offCalls.map { $0?.service }).count == 1, "every chosen source turns the TV off with the same script")
        // Xbox while Fortnite runs is selected, so it also turns the TV off.
        #expect(try spec(.console, M.Source.fortnite).label == "Turn Off TV")
    }

    @Test func fortniteKeepsTodaysBehaviourAndRelaunches() throws {
        let chosen = try spec(.launcher, M.Source.fortnite)
        let idle = try spec(.launcher, "Off")
        #expect(chosen.call == idle.call && chosen.label == nil, "no off branch today")
    }

    @Test(arguments: [nil, "unavailable", "unknown"] as [String?])
    func unavailableDimsInPlaceAndReadsNotChosen(_ state: String?) throws {
        let s = try spec(.console, state)
        #expect(s.phase == .unavailable && s.selection == .single(isSelected: false) && s.symbol == "circle")
    }

    @Test func theViewTracksEveryEntityTheValuesTouch() {
        let tracked = Set(SourceSelectActions.trackedEntityIds)
        for item in SourceSelectActions.allMusicRoom {
            let intents = (item.actions(for: entity(source, "Off")).first?.optimistic ?? []) + (item.actions(for: entity(source, item.selectedStates[0])).first?.optimistic ?? [])
            #expect(!intents.isEmpty)
            #expect(intents.allSatisfy { tracked.contains($0.entityId) }, "\(item.title)")
        }
    }

    @Test func allFourSourcesInTileOrderAndStateText() {
        #expect(SourceSelectActions.allMusicRoom.map(\.title) == SourceSelectActions.MusicRoomSource.allCases.map(\.title))
        #expect(SourceSelectActions.musicRoom(.console).stateTextCandidates.contains("Unavailable"))
    }
}

// MARK: - Script power

@Suite(.demoHouse)
struct ScriptPowerActionsTests {
    let provider = ScriptPowerActions.all[0]
    private var active: String { provider.activeEntityId }

    private func spec(live: String?, pending: String? = nil, own: String? = nil, off: String? = nil) throws -> TileActionSpec {
        let specs = provider.actions(
            live: live.map { entity(active, $0) }, pending: pending,
            onScript: own.map { entity(provider.onScriptEntityId, $0) }, offScript: off.map { entity(provider.offScriptEntityId, $0) }
        )
        assertContract(specs)
        #expect(specs.count == 1 && specs[0].id == "power" && specs[0].feedback == .tracked && specs[0].symbol == "power")
        return specs[0]
    }

    @Test func offRunsTheTilesOwnScript() throws {
        let s = try spec(live: "off")
        #expect(s.verb == "Turn On" && s.isOn == false && s.phase == .ready)
        #expect(s.call == ServiceCall("script", "demo_room_console_2"))
    }

    @Test func onRunsTheToggleScriptAndReadsTurnOff() throws {
        let s = try spec(live: "on")
        #expect(s.verb == "Turn Off" && s.isOn == true && s.phase == .ready)
        #expect(s.call == ServiceCall("script", "demo_room_power_toggle"))
    }

    @Test(.demoHouse) func shieldUsesItsOwnScriptAndBoolean() throws {
        let shield = ScriptPowerActions.all[1]
        let off = try #require(shield.actions(for: entity(shield.activeEntityId, "off")).first)
        #expect(off.call?.domain == "script" && off.call?.service == shield.onScriptEntityId.replacingOccurrences(of: "script.", with: ""))
        #expect(shield.onScriptEntityId.hasPrefix("script.") && shield.offScriptEntityId.hasPrefix("script."))
        #expect(shield.onScriptEntityId != shield.offScriptEntityId)
        #expect(ScriptPowerActions.all.map(\.activeEntityId) == [ScriptPowerActions.all[0].activeEntityId, shield.activeEntityId])
    }

    @Test func aPendingTargetKeepsTheDiscInFlightUntilTheBooleanReports() throws {
        let waiting = try spec(live: "off", pending: "on")
        #expect(waiting.phase == .inFlight && waiting.isOn == false, "glyph and fill change only when the boolean reports")
        let reported = try spec(live: "on", pending: "on")
        #expect(reported.phase == .ready && reported.isOn == true)
        let turningOff = try spec(live: "on", pending: "off")
        #expect(turningOff.phase == .inFlight && turningOff.verb == "Turn Off" && turningOff.isOn == true)
    }

    @Test func aRunningScriptKeepsItInFlightEvenAfterTheBooleanReports() throws {
        #expect(try spec(live: "on", pending: nil, own: "on").phase == .inFlight)
        #expect(try spec(live: "off", pending: nil, off: "on").phase == .inFlight, "the turn-off script, still running")
        #expect(try spec(live: "on", pending: nil, own: "off", off: "off").phase == .ready)
    }

    @Test func unavailableDimsAndNeverSpins() throws {
        for state in [nil, "unavailable", "unknown"] as [String?] {
            let s = try spec(live: state, pending: "on", own: "on")
            #expect(s.phase == .unavailable && s.id == "power" && s.isOn == false, "\(state ?? "nil")")
        }
    }

    @Test func theTapHoldsTheTargetOnTheBooleanAndFailsOnTimeout() throws {
        let off = try spec(live: "off")
        #expect(off.tracking == [OptimisticIntent(active, "on", revertAfter: ScriptPowerActions.holdDuration, failsOnTimeout: true)])
        let on = try spec(live: "on")
        #expect(on.tracking.first?.value == "off" && on.tracking.first?.failsOnTimeout == true)
        #expect(off.optimistic.isEmpty, "tracked: no optimistic glyph swap")
    }

    @Test func restingSpecsNeverSpin() {
        #expect(provider.actions(for: entity(active, "on")).first?.phase == .ready)
        #expect(provider.actions(for: nil).first?.phase == .unavailable)
        #expect(provider.stateTextCandidates.contains("Didn't Respond"))
    }
}

// MARK: - Bed side power

@Suite(.demoHouse)
struct BedSidePowerActionsTests {
    let provider = BedSidePowerActions(MasterBedroom.bed(.left))

    private func spec(_ state: String?, readOnly: Bool = false) throws -> TileActionSpec {
        var provider = provider
        provider.isReadOnly = readOnly
        let specs = provider.actions(for: state.map { entity(provider.entityId, $0) })
        assertContract(specs)
        return try #require(specs.first)
    }

    @Test func onOffersATurnOffThatAsksFirst() throws {
        for state in ["heat", "cool", "heat_cool", "on"] {
            let s = try spec(state)
            #expect(s.verb == "Turn Off" && s.isOn == true && s.phase == .ready && s.id == "power", "\(state)")
            let ask = try #require(s.confirmation)
            #expect(ask.title == "Turn off Alex's Bed?" && ask.confirmVerb == "Turn Off" && ask.isDestructive && ask.style == .dialog)
        }
    }

    @Test func offOffersATurnOnWithNoQuestion() throws {
        let s = try spec("off")
        #expect(s.verb == "Turn On" && s.isOn == false && s.phase == .ready && s.confirmation == nil)
    }

    @Test func theTravelersSideAndAnUnavailableSideDimInPlace() throws {
        #expect(try spec("heat", readOnly: true).phase == .unavailable)
        for state in [nil, "unavailable", "unknown"] as [String?] {
            let s = try spec(state)
            #expect(s.phase == .unavailable && s.confirmation == nil && s.isOn == false)
        }
    }

    @Test func theBedControllerOwnsTheEffect() throws {
        #expect(try spec("off").call == nil, "setPower(on:) picks the broker script or the whole-bed command")
        #expect(provider.entityId == MasterBedroom.bed(.left).climateEntityId)
        #expect(BedSidePowerActions(MasterBedroom.bed(.right)).turnOffConfirmation.title == "Turn off Sam's Bed?")
        #expect(provider.stateTextCandidates.contains("Away · Read Only"))
    }
}

// MARK: - Hot flash

@Suite(.demoHouse)
struct HotFlashActionsTests {
    let provider = HotFlashActions(MasterBedroom.bed(.left))
    private var config: BedSideConfig { MasterBedroom.bed(.left) }

    private func spec(_ state: String?, readOnly: Bool = false) throws -> TileActionSpec {
        var provider = provider
        provider.isReadOnly = readOnly
        let specs = provider.actions(for: state.map { entity(config.hotFlashActiveEntityId, $0) })
        assertContract(specs)
        #expect(specs.count == 1 && specs[0].id == "hot_flash", "one id, so the snowflake becomes the stop")
        return specs[0]
    }

    @Test func inactiveOffersTheSnowflake() throws {
        let s = try spec("off")
        #expect(s.symbol == "snowflake" && s.label == "Start Hot Flash Mode" && s.phase == .ready && s.isOn == nil)
        #expect(s.call == ServiceCall("input_button", "press", target: config.hotFlashButtonEntityId))
        #expect(s.optimistic == [OptimisticIntent(config.hotFlashActiveEntityId, value: "on")])
    }

    @Test func activeOffersStopThatCancels() throws {
        let s = try spec("on")
        #expect(s.symbol == "stop.fill" && s.label == "Cancel Hot Flash Mode" && s.phase == .ready)
        #expect(s.call == ServiceCall("input_button", "press", target: config.hotFlashCancelButtonEntityId))
        #expect(s.optimistic == [OptimisticIntent(config.hotFlashActiveEntityId, value: "off")])
        #expect(s.confirmation == nil, "cancelling is cheap to redo")
    }

    @Test func unavailableAndReadOnlyDimInPlace() throws {
        for state in [nil, "unavailable", "unknown"] as [String?] { #expect(try spec(state).phase == .unavailable) }
        let travelers = try spec("on", readOnly: true)
        #expect(travelers.phase == .unavailable && travelers.symbol == "snowflake", "read-only never reads active")
    }

    @Test func stateTextHasTheCountdownAndTheFallback() {
        #expect(provider.stateTextCandidates.contains("Hot Flash Mode • Cooling") && provider.stateTextCandidates.contains("Inactive"))
        #expect(provider.isActive("on") && !provider.isActive("off"))
    }
}

// MARK: - Alarm

@Suite(.demoHouse)
struct AlarmModeActionsTests {
    let provider = AlarmModeActions()
    private let panel = SecurityConfig.alarmEntityId

    private func spec(_ state: String?) throws -> TileActionSpec {
        let specs = provider.actions(for: state.map { entity(panel, $0) })
        assertContract(specs)
        #expect(specs.count == 1 && specs[0].id == "alarm", "Arm Home morphs into Disarm")
        return specs[0]
    }

    @Test func disarmedOffersArmHomeWithNoQuestion() throws {
        let s = try spec("disarmed")
        #expect(s.verb == "Arm Home" && s.symbol == "shield.lefthalf.filled" && s.phase == .ready && s.confirmation == nil)
        #expect(s.call == ServiceCall("alarm_control_panel", "alarm_arm_home", target: panel) && s.feedback == .tracked)
    }

    @Test(arguments: ["armed_home", "armed_away", "armed_night", "armed_vacation", "armed_custom_bypass", "triggered"])
    func armedOffersAConfirmedDisarm(_ state: String) throws {
        let s = try spec(state)
        #expect(s.verb == "Disarm" && s.symbol == "shield.slash" && s.phase == .ready)
        #expect(s.call == ServiceCall("alarm_control_panel", "alarm_disarm", target: panel))
        let ask = try #require(s.confirmation)
        #expect(ask.title == "Disarm the Security System?" && ask.message == "Doors and motion stop triggering the alarm.")
        #expect(ask.confirmVerb == "Disarm" && !ask.isDestructive && ask.style == .alert, "plain and bold, as the sheet's alert")
    }

    @Test func theExitAndEntryDelaysKeepDisarmTappableAndDisarmingSpins() throws {
        for state in ["arming", "pending"] {
            let s = try spec(state)
            #expect(s.phase == .ready && s.verb == "Disarm" && s.confirmation != nil, "pending is the entry delay: Disarm must stay tappable")
        }
        let disarming = try spec("disarming")
        #expect(disarming.phase == .inFlight && disarming.verb == "Arm Home")
    }

    @Test(arguments: [nil, "unavailable", "unknown"] as [String?])
    func unavailableDimsInPlace(_ state: String?) throws {
        let s = try spec(state)
        #expect(s.phase == .unavailable && s.verb == "Arm Home" && s.confirmation == nil)
    }

    @Test func theConfirmationMatchesTheSecuritySheetsWords() {
        #expect(AlarmModeActions.disarmConfirmation.confirmVerb == SecurityConfig.disarmMode.buttonTitle)
        #expect(provider.entityId == SecurityConfig.alarmEntityId)
        #expect(provider.stateTextCandidates.contains("Armed Home") && provider.stateTextCandidates.contains("Triggered"))
    }
}

// MARK: - Sprinklers

@Suite(.demoHouse)
struct SprinklerActionsTests {
    let provider = SprinklerActions(SprinklersConfig.controllers[1])
    private var valve: String { SprinklersConfig.controllers[1].zones[0].valveEntityId }

    @Test func aWateringValveOffersStopWatering() throws {
        for state in ["open", "opening"] {
            let specs = provider.actions(for: entity(valve, state))
            assertContract(specs)
            let s = try #require(specs.first)
            #expect(specs.count == 1 && s.id == "stop" && s.symbol == "stop.fill" && s.label == "Stop Watering")
            #expect(s.phase == .ready && s.feedback == .momentary && s.isOn == nil)
            #expect(s.call == SprinklersConfig.stopWatering(valve: valve))
        }
    }

    @Test func idleDimsInPlaceAndKeepsItsCall() throws {
        for state in [nil, entity(valve, "closed"), entity(valve, "unavailable")] {
            let s = try #require(provider.actions(for: state).first)
            #expect(s.phase == .unavailable && s.id == "stop" && s.call == SprinklersConfig.stopWatering(valve: valve), "the set never changes shape")
        }
    }

    @Test func theSnapshotPicksTheActiveValve() throws {
        let config = SprinklersConfig.controllers[1]
        let second = config.zones[1].valveEntityId
        let watering = SprinklerSnapshot(config: config) { id in entity(id, id == second ? "open" : "closed") }
        #expect(watering.watering && watering.activeValveEntityId == second)
        let s = try #require(provider.actions(for: watering).first)
        #expect(s.phase == .ready && s.call == SprinklersConfig.stopWatering(valve: second))

        let resting = SprinklerSnapshot(config: config) { id in entity(id, "closed") }
        let idle = try #require(provider.actions(for: resting).first)
        #expect(!resting.watering && idle.phase == .unavailable && idle.call == SprinklersConfig.stopWatering(valve: valve))

        let gone = SprinklerSnapshot(config: config) { _ in nil }
        #expect(gone.status == .unavailable && provider.actions(for: gone).first?.phase == .unavailable)
    }

    @Test func stateText() {
        #expect(provider.stateTextCandidates.contains("Watering") && SprinklerActions.isWatering("open") && !SprinklerActions.isWatering("closed"))
    }
}

// MARK: - Selection

@Suite(.demoHouse)
struct SelectionActionsTests {
    @Test func singleChoiceReadsCheckOrRing() {
        let chosen = SelectionActions.single(isSelected: true)
        let not = SelectionActions.single(isSelected: false)
        #expect(chosen.symbol == "checkmark" && chosen.selection == .single(isSelected: true) && chosen.verb == "Deselect")
        #expect(not.symbol == "circle" && not.selection == .single(isSelected: false) && not.verb == "Select")
        #expect(chosen.id == not.id, "one id, so the mark swaps in place")
        #expect(chosen.call == nil && chosen.feedback == .optimistic && chosen.isOn == nil, "the controller owns the choice; never a switch")
    }

    @Test func orderedChoiceCarriesItsPlace() {
        let second = SelectionActions.ordered(position: 2)
        #expect(second.selection == .ordered(position: 2) && second.verb == "Deselect")
        let none = SelectionActions.ordered(position: nil)
        #expect(none.selection == .ordered(position: nil) && none.symbol == "circle")
        #expect(SelectionActions.ordered(position: 0).selection == .ordered(position: nil), "0 is not a place")
        #expect(SelectionActions.ordered(position: -3).selection == .ordered(position: nil))
    }

    @Test func aDisabledChoiceDimsInPlace() {
        #expect(SelectionActions.single(isSelected: false, isEnabled: false).phase == .unavailable)
        #expect(SelectionActions.ordered(position: 1, isEnabled: false).phase == .unavailable)
        #expect(SelectionActions.single(isSelected: false, label: "Select Alex").label == "Select Alex")
    }

    @Test(arguments: [(1, "Cleans 1st"), (2, "Cleans 2nd"), (3, "Cleans 3rd"), (4, "Cleans 4th"), (11, "Cleans 11th"), (12, "Cleans 12th"),
                      (13, "Cleans 13th"), (21, "Cleans 21st"), (22, "Cleans 22nd"), (101, "Cleans 101st"), (111, "Cleans 111th")])
    func orderText(_ place: Int, _ text: String) {
        #expect(SelectionActions.orderText(place) == text)
    }

    @Test func orderTextForNone() {
        #expect(SelectionActions.orderText(nil) == "Not included" && SelectionActions.orderText(0) == "Not included")
    }
}

// MARK: - Registration

@Suite(.demoHouse)
struct RolloutRegistrationTests {
    @Test func everyNewKindHasARestingCountThatMatchesItsProvider() {
        #expect(TileActionKind.momentaryCommand.restingActionCount == CommandActions.powerRecovery.actions(for: nil).count)
        #expect(TileActionKind.sourceSelect.restingActionCount == SourceSelectActions.musicRoom(.console).actions(for: nil).count)
        #expect(TileActionKind.scriptPower.restingActionCount == ScriptPowerActions.all[0].actions(for: nil).count)
        #expect(TileActionKind.bedSidePower.restingActionCount == BedSidePowerActions(MasterBedroom.bed(.left)).actions(for: nil).count)
        #expect(TileActionKind.hotFlash.restingActionCount == HotFlashActions(MasterBedroom.bed(.left)).actions(for: nil).count)
        #expect(TileActionKind.alarmMode.restingActionCount == AlarmModeActions().actions(for: nil).count)
        #expect(TileActionKind.sprinkler.restingActionCount == SprinklerActions(SprinklersConfig.controllers[1]).actions(for: nil).count)
        #expect(TileActionKind.selection.restingActionCount == 1)
        #expect(TileActionKind.roomLightsPower.restingActionCount == 1)
        #expect(TileActionKind.allCases.count == 17)
    }

    @Test(.demoHouse) func theMediaPageMapsSourcesAndScriptedDevices() {
        let sourceTitles = Set(SourceSelectActions.MusicRoomSource.allCases.map(\.title))
        let scriptIds = Set(ScriptPowerActions.all.map(\.activeEntityId))
        let kinds = Dictionary(uniqueKeysWithValues: MediaPageConfig.cards.compactMap { $0.remote == nil ? ($0.device.title + "/" + $0.id, ($0.device, TileActionCatalog.kind(of: $0))) : nil })
        for (key, (device, kind)) in kinds {
            if sourceTitles.contains(device.title) { #expect(kind == .sourceSelect, "\(key)") }
            if scriptIds.contains(device.entityId) { #expect(kind == .scriptPower, "\(key)") }
        }
        #expect(kinds.values.contains { $0.1 == .sourceSelect } && kinds.values.contains { $0.1 == .scriptPower })
    }

    @Test(.demoHouse) func theScriptPowerCardsOnTheRoomPageAreScriptPower() throws {
        let scriptIds = Set(ScriptPowerActions.all.map(\.activeEntityId))
        let scripted = RoomsConfig.pages.flatMap(\.allCards).filter { scriptIds.contains($0.entityId) }
        #expect(scripted.count == 2)
        for card in scripted {
            #expect(TileActionCatalog.kind(of: card) == .scriptPower && TileActionCatalog.classification(of: card) == .action(1))
        }
    }
}
