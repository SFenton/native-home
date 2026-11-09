import Foundation
import Observation

/// Drives one side of the Master Bedroom Pod through the SleepyPod adapter: power, target level, the
/// Bedtime/Asleep/Dawn stage levels, Hot Flash Mode, the active alarm and the alarm schedule
/// (web `useEightSleepBedModalState`, `EightSleepThermostatHero`, `useEightSleepAlarmsController`,
/// `ha-sfenton-react-dash@9ac2a46:src/pages/DashboardViewPage.tsx:4003`).
///
/// Home Assistant stays the source of truth: changes show at once and give way to the live state when it
/// confirms them, when a call fails, or after their revert time. During a Solo Trip the side either controls the
/// whole bed through the Household Away command or is read-only.
@MainActor
@Observable
public final class BedSideController {
    // MARK: - Types

    /// A pending "Tonight or All Nights?" question after a target change during a schedule stage.
    public struct ScopeRequest: Equatable, Sendable {
        public var phase: SchedulePhase
        public var level: Double
        /// `+3`.
        public var targetText: String
    }

    /// An alarm being added or edited (web `EightSleepAlarmEditorDraft`).
    public struct AlarmDraft: Equatable, Sendable {
        public var days: [Weekday]
        /// The alarm being edited, or `nil` when adding.
        public var editingId: String?
        public var enabled: Bool
        /// `HH:MM`.
        public var time: String
        public var title: String
        /// Whether the room wake light follows this alarm.
        public var wakeLightEnabled: Bool
        /// The day page the editor opened from; hides the day picker.
        public var lockedDay: Weekday?

        public init(days: [Weekday], editingId: String? = nil, enabled: Bool = true, time: String = BedAlarm.defaultTime,
                    title: String, wakeLightEnabled: Bool = true, lockedDay: Weekday? = nil) {
            self.days = days
            self.editingId = editingId
            self.enabled = enabled
            self.time = time
            self.title = title
            self.wakeLightEnabled = wakeLightEnabled
            self.lockedDay = lockedDay
        }
    }

    // MARK: - Properties

    public let config: BedSideConfig
    public let store: EntityStore
    /// Optimistic values: `power`, `target`, `hotFlash`, `alarm`, and `stage.<phase>`.
    public let overlay: OptimisticOverlay

    /// The open scope question, if any.
    public private(set) var scopeRequest: ScopeRequest?
    /// The last refused Solo Trip command's message.
    public private(set) var commandError: String?

    private var held: [String: EntityState] = [:]
    private var alarmOverride: [BedAlarm]?
    private var optimisticSnoozedUntil: Double?

    @ObservationIgnored private let caller: any HassServiceResponding
    @ObservationIgnored private let scheduler: any RevertScheduler
    @ObservationIgnored private let makeRequestId: @MainActor () -> String
    @ObservationIgnored private var holdTimers: [String: any ScheduledWork] = [:]
    @ObservationIgnored private var stageTimers: [SchedulePhase: any ScheduledWork] = [:]
    @ObservationIgnored private var alarmTimer: (any ScheduledWork)?
    @ObservationIgnored private var alarmRevertTimer: (any ScheduledWork)?
    @ObservationIgnored private var alarmBaseKey: String?
    @ObservationIgnored private var pendingAlarms: [BedAlarm]?
    @ObservationIgnored private var publishedAlarmKeys: [String] = []
    @ObservationIgnored private var lastPhaseState: String??
    @ObservationIgnored private var inFlight: [Task<Void, Never>] = []

    /// Power and hot-flash edits wait this long for confirmation (web `EIGHT_SLEEP_POWER_REVERT_MS`).
    public static let powerRevert: Duration = .seconds(30)
    /// Target and stage edits wait this long (web `FREE_SLEEP_TARGET_REVERT_MS`).
    public static let targetRevert: Duration = .seconds(30)
    /// The alarm state shows a snooze or stop this long (web default optimistic revert).
    public static let alarmRevert: Duration = .seconds(10)
    /// A briefly unavailable Pod keeps its last state this long (web `EIGHT_SLEEP_UNAVAILABLE_HOLD_MS`).
    public static let unavailableHold: Duration = .seconds(10)
    /// Stage stepper presses are batched this long (web `FREE_SLEEP_NUMBER_SYNC_DEBOUNCE_MS`).
    public static let stageDebounce: Duration = .milliseconds(300)
    /// Alarm list edits are batched this long (web `FREE_SLEEP_ALARM_SYNC_DEBOUNCE_MS`).
    public static let alarmDebounce: Duration = .milliseconds(450)
    /// An unconfirmed alarm list gives way to Home Assistant after this long.
    public static let alarmListRevert: Duration = .seconds(30)

    // MARK: - Init

    /// Creates a controller.
    /// - Parameters:
    ///   - config: The bed side.
    ///   - store: Live state.
    ///   - caller: Sends service calls and response-checked Solo Trip commands.
    ///   - scheduler: Runs revert, hold and debounce timers.
    ///   - requestId: Makes Solo Trip `request_id`s.
    public init(config: BedSideConfig, store: EntityStore, caller: any HassServiceResponding,
                scheduler: any RevertScheduler = TaskRevertScheduler(),
                requestId: @escaping @MainActor () -> String = { UUID().uuidString.lowercased() }) {
        self.config = config
        self.store = store
        self.caller = caller
        self.scheduler = scheduler
        makeRequestId = requestId
        var rules: [String: OptimisticOverlay.ClearRule] = ["power": .confirmation, "target": .confirmation, "hotFlash": .confirmation, "alarm": .confirmation]
        for phase in SchedulePhase.allCases { rules["stage.\(phase.rawValue)"] = .confirmation }
        overlay = OptimisticOverlay(rules: rules, scheduler: scheduler)
        liveDidChange()
        observeLive()
    }

    // MARK: - Live readings

    private func live(_ id: String) -> EntityState? { store.entity(id).state }

    /// The entity, or its last available state for ``unavailableHold`` after it drops out.
    private func stable(_ id: String) -> EntityState? {
        let value = live(id)
        if let value, !value.isUnavailable { return value }
        return held[id] ?? value
    }

    private static func available(_ state: EntityState?) -> Bool { state.map { !$0.isUnavailable } ?? false }

    /// Both adapter entities answer; otherwise nothing on the side can change.
    public var sideAvailable: Bool {
        Self.available(stable(config.climateEntityId)) && Self.available(stable(config.targetLevelEntityId))
    }

    var liveSideOn: Bool {
        guard let climate = stable(config.climateEntityId), !climate.isUnavailable else { return false }
        return climate.state != "off"
    }

    var liveTarget: Double? { stable(config.targetLevelEntityId).flatMap { $0.isUnavailable ? nil : Double($0.state) } }

    /// The target level range from the number entity.
    public var targetRange: ClosedRange<Double> {
        let attributes = stable(config.targetLevelEntityId)?.attributes
        let low = attributes?["min"].flatMap(BedAlarm.number) ?? BedLevel.min
        let high = attributes?["max"].flatMap(BedAlarm.number) ?? BedLevel.max
        return low...max(low, high)
    }

    /// The target level step.
    public var targetStep: Double { stable(config.targetLevelEntityId)?.attributes["step"].flatMap(BedAlarm.number) ?? BedLevel.step }

    /// The Pod's measured surface temperature.
    public var currentTemperature: Double? {
        guard let climate = stable(config.climateEntityId), !climate.isUnavailable else { return nil }
        return climate.attributes["current_temperature"].flatMap(BedAlarm.number)
    }

    /// Where the dial's current marker sits on the level scale.
    public var currentLevel: Double? {
        guard let currentTemperature else { return nil }
        let targetTemperature = stable(config.targetLevelEntityId)?.attributes["targetTemperature"].flatMap(BedAlarm.number)
            ?? stable(config.climateEntityId)?.attributes["temperature"].flatMap(BedAlarm.number)
        return BedLevel.currentLevel(current: currentTemperature, range: targetRange, targetLevel: liveTarget, targetTemperature: targetTemperature)
    }

    /// The running schedule stage, if any.
    public var activePhase: SchedulePhase? { SchedulePhase(state: live(config.schedulePhaseEntityId)?.state) }

    /// The stage sensor reports a stage or `outside`.
    public var phaseAvailable: Bool { SchedulePhase.isAvailable(live(config.schedulePhaseEntityId)?.state) }

    /// Solo Trip scope for this side.
    public var scope: HouseholdAwayBedScope {
        HouseholdAwayBedScope(entity: live(MasterBedroom.householdAwayEntityId), owner: config.owner)
    }

    // MARK: - Displayed state

    /// The side is on (optimistic while a power change is pending).
    public var isOn: Bool { sideAvailable && overlay.displayed("power", live: liveSideOn ? "on" : "off") == "on" }

    /// Hot Flash Mode is on.
    public var hotFlashActive: Bool {
        let live = live(config.hotFlashActiveEntityId)
        return overlay.displayed("hotFlash", live: live?.state == "on" ? "on" : "off") == "on"
    }

    /// Hot Flash Mode can be started.
    public var hotFlashAvailable: Bool { Self.available(live(config.hotFlashActiveEntityId)) }

    /// Hot Flash Mode's timer is running (cooling has finished ramping and is holding).
    public var hotFlashHolding: Bool { hotFlashActive && live(config.hotFlashTimerEntityId)?.state == "active" }

    /// The target level to show; Hot Flash Mode shows the bottom of the scale.
    public var displayedTarget: Double? {
        if hotFlashActive { return targetRange.lowerBound }
        return overlay.displayed("target", live: liveTarget.map(Self.key)).flatMap(Double.init)
    }

    /// Heating, cooling, idle or off.
    public var action: String { BedLevel.action(targetLevel: displayedTarget, isOn: isOn) }

    /// The sheet subtitle (web `subtitle`).
    public var subtitle: String {
        // A side that stopped answering is not "Off": say so (the tile stays navigable; the sheet explains).
        guard sideAvailable else { return "Unavailable" }
        if hotFlashActive { return "Hot Flash Mode" }
        guard isOn else { return "Off" }
        return "\(StateText.titleCase(action, empty: "")) • \(BedLevel.format(displayedTarget))"
    }

    /// The room tile subtitle at `now` (web `tileSubtitle` with Solo Trip wording).
    public func tileSubtitle(now: Date = .now) -> String {
        let scope = scope
        if scope.readOnly { return HouseholdAwayBedScope.readOnlySubtitle }
        var text = subtitle
        if hotFlashActive {
            text = hotFlashHolding ? hotFlashCountdown(now: now).map { "\($0) Remaining" } ?? "Hot Flash Mode • Cooling" : "Hot Flash Mode • Cooling"
        }
        return scope.controlsWholeBed ? "Whole Bed • \(text)" : text
    }

    /// The sheet title (`Alex's Bed · Whole Bed` while it controls both sides).
    public var title: String { scope.controlsWholeBed ? "\(config.title) · Whole Bed" : config.title }

    /// Hot Flash Mode's remaining time at `now` (web `eightSleepHotFlashCountdown`), while holding.
    public func hotFlashCountdown(now: Date) -> String? {
        guard hotFlashHolding else { return nil }
        let timer = live(config.hotFlashTimerEntityId)
        if let finishes = timer?.attributes["finishes_at"]?.string.flatMap(WakeLight.timestamp) {
            return BedFormat.countdown(finishes.timeIntervalSince(now))
        }
        if let remaining = timer?.attributes["remaining"]?.string {
            let parts = remaining.split(separator: ":").compactMap { Int($0) }
            if parts.count >= 2 { return "\(parts[parts.count - 2]):\(String(format: "%02d", parts[parts.count - 1]))" }
        }
        guard let restore = live(config.hotFlashRestoreAtEntityId), !restore.isUnavailable else { return nil }
        if let timestamp = restore.attributes["timestamp"].flatMap(BedAlarm.number) {
            return BedFormat.countdown(timestamp - now.timeIntervalSince1970)
        }
        return HassDates.localDateTime(restore.state).map { BedFormat.countdown($0.timeIntervalSince(now)) }
    }

    /// The target can change from the dial.
    public var canSetTarget: Bool {
        sideAvailable && scope.interactive && isOn && !hotFlashActive && displayedTarget != nil && phaseAvailable
    }

    /// The line under the power button (web `heroHintText`).
    public var hint: String {
        if !sideAvailable { return "Bed controls are unavailable." }
        if !scope.interactive { return HouseholdAwayBedScope.readOnlySubtitle }
        if !isOn { return "Use the power control to turn on the Pod." }
        if !phaseAvailable { return "Schedule phase is unavailable." }
        if hotFlashActive { return "Hot Flash Mode controls the target." }
        return "Drag the dial to set the target."
    }

    /// The power button can be used.
    public var canTogglePower: Bool { sideAvailable && scope.interactive }

    /// `Turn On`, `Turn Off`, `Unavailable`, or the read-only subtitle.
    public var powerTitle: String {
        if !scope.interactive { return HouseholdAwayBedScope.readOnlySubtitle }
        if !sideAvailable { return "Unavailable" }
        return isOn ? "Turn Off" : "Turn On"
    }

    // MARK: - Stage levels

    /// A stage's recurring level, optimistic while a change is pending.
    public func stageLevel(_ phase: SchedulePhase) -> Double? {
        guard let id = config.stageLevelEntityIds[phase] else { return nil }
        let live = live(id).flatMap { $0.isUnavailable ? nil : Double($0.state) }
        return overlay.displayed("stage.\(phase.rawValue)", live: live.map(Self.key)).flatMap(Double.init)
    }

    /// The stage's range and step from its `input_number`.
    public func stageRange(_ phase: SchedulePhase) -> (range: ClosedRange<Double>, step: Double) {
        let attributes = config.stageLevelEntityIds[phase].flatMap(live)?.attributes
        let low = attributes?["min"].flatMap(BedAlarm.number) ?? BedLevel.min
        let high = attributes?["max"].flatMap(BedAlarm.number) ?? BedLevel.max
        return (low...max(low, high), attributes?["step"].flatMap(BedAlarm.number) ?? BedLevel.step)
    }

    /// Whether a stage's stepper works.
    public func canStepStage(_ phase: SchedulePhase) -> Bool {
        guard let id = config.stageLevelEntityIds[phase], Self.available(live(id)) else { return false }
        return (stageLevel(phase) ?? displayedTarget) != nil && scope.interactive
    }

    // MARK: - Alarm state

    /// The alarm state to show.
    public var alarmState: BedAlarmState {
        BedAlarmState(state: overlay.displayed("alarm", live: BedAlarmState(state: live(config.alarmStateEntityId)?.state).rawValue))
    }

    /// `4:59 Remaining` while snoozed.
    public func snoozeRemaining(now: Date) -> String {
        let live = live(config.alarmStateEntityId)
        let liveUntil = live?.state == "snoozed" ? live?.attributes["snoozed_until"].flatMap(BedAlarm.number) : nil
        return BedAlarmState.snoozeRemainingText(snoozedUntil: liveUntil, now: now)
            ?? BedAlarmState.snoozeRemainingText(snoozedUntil: optimisticSnoozedUntil, now: now)
            ?? "5:00 Remaining"
    }

    /// The active alarm buttons are read-only (traveler side during a Solo Trip).
    public var alarmControlsReadOnly: Bool { scope.readOnly }

    // MARK: - Alarm schedule

    /// The side's schedule as Home Assistant reports it.
    public var schedule: SleepypodSchedule? {
        guard let entity = live(MasterBedroom.scheduleEntityId), !entity.isUnavailable else { return nil }
        return SleepypodSchedule(attributes: entity.attributes)
    }

    /// Home Assistant has an alarm schedule for this side.
    public var alarmsAvailable: Bool { schedule?.has(config.side) ?? false }

    /// Alarms can change (available, and not the traveler's side).
    public var alarmsEditable: Bool { alarmsAvailable && scope.interactive }

    /// Alarms as Home Assistant reports them.
    public var sourceAlarms: [BedAlarm] { schedule?.alarms(config.side) ?? [] }

    /// Alarms to show (optimistic while an edit is unconfirmed).
    public var alarms: [BedAlarm] { alarmOverride ?? sourceAlarms }

    /// Alarms grouped by day.
    public var alarmGroups: [BedAlarmDayGroup] { BedAlarmDayGroup.groups(alarms) }

    /// Why a draft can't be saved, in display order; empty when it can.
    public func problems(_ draft: AlarmDraft) -> [String] {
        var problems: [String] = []
        if !alarmsAvailable { problems.append("Home Assistant alarm schedule data is unavailable.") }
        else if !alarmsEditable { problems.append(HouseholdAwayBedScope.readOnlySubtitle) }
        if isStale(draft) { problems.append("This alarm changed in Home Assistant. Go back and reopen it.") }
        if draft.days.isEmpty { problems.append("Select at least one day.") }
        if !ClockTime.isValid(draft.time) { problems.append("Choose a valid alarm time.") }
        return problems
    }

    /// The edited alarm no longer exists in Home Assistant.
    public func isStale(_ draft: AlarmDraft) -> Bool {
        guard alarmsAvailable, let id = draft.editingId else { return false }
        return !alarms.contains { $0.id == id }
    }

    /// A new-alarm draft (web `createAlarmDraft`; Monday–Friday unless a day page locks it).
    public func newAlarmDraft(lockedDay: Weekday? = nil) -> AlarmDraft {
        let title = lockedDay.map { "Add \(config.title) \($0.label) Alarm" } ?? "Add \(config.title) Alarm"
        return AlarmDraft(days: lockedDay.map { [$0] } ?? Weekday.workdays, title: title, lockedDay: lockedDay)
    }

    /// An edit draft for `alarm`, reading its wake-light link from `wakeLight`.
    public func editDraft(_ alarm: BedAlarm, wakeLight: WakeLight.Snapshot?) -> AlarmDraft {
        let source = MasterBedroom.wakeLight.source(for: config.side)
        let linked = source.map { wakeLight?.isLinked(WakeLight.linkKey(source: $0.id, day: alarm.day, time: alarm.time)) ?? false } ?? false
        return AlarmDraft(days: [alarm.day], editingId: alarm.id, enabled: alarm.enabled, time: alarm.time,
                          title: "\(config.title) \(alarm.day.label) Alarm", wakeLightEnabled: linked, lockedDay: alarm.day)
    }

    // MARK: - Actions: power and target

    /// Turns the side on or off (the sheet confirms turning off first).
    public func setPower(on: Bool) {
        guard canTogglePower else { return }
        let generation = overlay.commit("power", value: on ? "on" : "off", live: liveSideOn ? "on" : "off", revertAfter: Self.powerRevert)
        if !on { overlay.reset("target") }
        let effect: Effect = scope.controlsWholeBed
            ? .solo("set_power", ["enabled": on])
            : .service("script", MasterBedroom.hotFlashBrokerScript, ["action": on ? "power_heat" : "power_off", "side": config.side.rawValue])
        run(effect, rollback: [("power", generation)])
    }

    /// Sets the target level from the dial. During a schedule stage this sets tonight's target and asks whether it
    /// should also become the stage's level (web `setTargetTemperature` and `commitTemperatureIntent`).
    public func setTarget(_ value: Double) {
        guard canSetTarget else { return }
        let level = BedLevel.snap(value, range: targetRange, step: targetStep)
        let matchesLive = liveTarget == level
        if let phase = activePhase {
            if !matchesLive { commitTarget(level, effect: tonightEffect(level)) } else { overlay.reset("target") }
            scopeRequest = ScopeRequest(phase: phase, level: level, targetText: BedLevel.format(level))
            return
        }
        guard !matchesLive else {
            overlay.reset("target")
            return
        }
        let effect: Effect = scope.controlsWholeBed
            ? .solo("set_outside_level", ["level": level])
            : .service("script", config.outsideScheduleScript, ["level": level])
        commitTarget(level, effect: effect)
    }

    /// Answers the scope question: All Nights also saves the level as the stage's recurring level.
    public func chooseScope(_ choice: BedTemperatureScope) {
        guard let request = scopeRequest else { return }
        scopeRequest = nil
        guard choice == .allNights, sideAvailable, !scope.readOnly, activePhase == request.phase else { return }
        setStageLevelNow(request.phase, level: request.level)
    }

    /// Dismisses the scope question (tonight's target stays).
    public func dismissScope() { scopeRequest = nil }

    /// ``scopeRequest`` as a writable property for `confirmationDialog(item:)`: setting it to nil is the dialog being dismissed.
    public var scopePrompt: ScopeRequest? {
        get { scopeRequest }
        set { if newValue == nil { dismissScope() } }
    }

    private func tonightEffect(_ level: Double) -> Effect {
        scope.controlsWholeBed ? .solo("set_tonight_level", ["level": level]) : .service("script", config.tonightScript, ["level": level])
    }

    private func commitTarget(_ level: Double, effect: Effect) {
        let generation = overlay.commit("target", value: Self.key(level), live: liveTarget.map(Self.key), revertAfter: Self.targetRevert)
        run(effect, rollback: [("target", generation)])
    }

    // MARK: - Actions: stages

    /// Steps a stage's level by one step up or down; presses are batched before sending (web
    /// `EightSleepScheduleTemperatureControl`). The running stage goes through tonight's target and the scope question.
    public func stepStage(_ phase: SchedulePhase, up: Bool) {
        guard canStepStage(phase), let base = stageLevel(phase) ?? displayedTarget else { return }
        let (range, step) = stageRange(phase)
        let next = BedLevel.snap(base + (up ? step : -step), range: range, step: step)
        let key = "stage.\(phase.rawValue)"
        let live = config.stageLevelEntityIds[phase].flatMap(live).flatMap { Double($0.state) }
        overlay.commit(key, value: Self.key(next), live: live.map(Self.key), revertAfter: Self.targetRevert)
        stageTimers[phase]?.cancel()
        stageTimers[phase] = scheduler.schedule(after: Self.stageDebounce) { [weak self] in
            guard let self else { return }
            self.stageTimers[phase] = nil
            self.sendStage(phase, level: next)
        }
    }

    private func sendStage(_ phase: SchedulePhase, level: Double) {
        if scope.controlsWholeBed {
            run(.solo("set_stage_level", ["level": level, "phase": phase.rawValue]), rollback: [("stage.\(phase.rawValue)", nil)])
            return
        }
        if activePhase == phase {
            if sideAvailable, liveTarget != level { commitTarget(level, effect: tonightEffect(level)) }
            if sideAvailable { scopeRequest = ScopeRequest(phase: phase, level: level, targetText: BedLevel.format(level)) }
            return
        }
        guard let id = config.stageLevelEntityIds[phase] else { return }
        run(.service("input_number", "set_value", ["entity_id": id, "value": level]), rollback: [("stage.\(phase.rawValue)", nil)])
        if let schedule {
            var levels: [SchedulePhase: Double] = [:]
            for stage in SchedulePhase.allCases {
                levels[stage] = stage == phase ? level : (stageLevel(stage) ?? displayedTarget ?? 0)
            }
            publish(schedule.stagePayload(side: config.side, levels: levels))
        }
    }

    private func setStageLevelNow(_ phase: SchedulePhase, level: Double) {
        let key = "stage.\(phase.rawValue)"
        let live = config.stageLevelEntityIds[phase].flatMap(live).flatMap { Double($0.state) }
        let generation = overlay.commit(key, value: Self.key(level), live: live.map(Self.key), revertAfter: Self.targetRevert)
        if scope.controlsWholeBed {
            run(.solo("set_stage_level", ["level": level, "phase": phase.rawValue]), rollback: [(key, generation)])
        } else if let id = config.stageLevelEntityIds[phase] {
            run(.service("input_number", "set_value", ["entity_id": id, "value": level]), rollback: [(key, generation)])
        }
    }

    // MARK: - Actions: hot flash and active alarm

    /// Starts Hot Flash Mode (cools to the bottom of the scale for fifteen minutes).
    public func startHotFlash() {
        guard hotFlashAvailable, !scope.readOnly else { return }
        let flash = overlay.commit("hotFlash", value: "on", live: live(config.hotFlashActiveEntityId)?.state == "on" ? "on" : "off", revertAfter: Self.powerRevert)
        let power = overlay.commit("power", value: "on", live: liveSideOn ? "on" : "off", revertAfter: Self.powerRevert)
        run(.service("input_button", "press", ["entity_id": config.hotFlashButtonEntityId]), rollback: [("hotFlash", flash), ("power", power)])
    }

    /// Cancels Hot Flash Mode.
    public func cancelHotFlash() {
        guard !scope.readOnly else { return }
        let flash = overlay.commit("hotFlash", value: "off", live: live(config.hotFlashActiveEntityId)?.state == "on" ? "on" : "off", revertAfter: Self.powerRevert)
        run(.service("input_button", "press", ["entity_id": config.hotFlashCancelButtonEntityId]), rollback: [("hotFlash", flash)])
    }

    /// Snoozes the ringing alarm for five minutes.
    public func snoozeAlarm(now: Date = .now) {
        guard !scope.readOnly else { return }
        optimisticSnoozedUntil = now.timeIntervalSince1970 + BedAlarmState.snoozeSeconds
        commitAlarm("snoozed", action: "snooze_alarm", button: config.alarmSnoozeButtonEntityId)
    }

    /// Stops the active alarm.
    public func stopAlarm() {
        guard !scope.readOnly else { return }
        optimisticSnoozedUntil = nil
        commitAlarm("idle", action: "stop_alarm", button: config.alarmStopButtonEntityId)
    }

    private func commitAlarm(_ state: String, action: String, button: String) {
        let live = BedAlarmState(state: live(config.alarmStateEntityId)?.state).rawValue
        let generation = overlay.commit("alarm", value: state, live: live, revertAfter: Self.alarmRevert)
        let effect: Effect = scope.controlsWholeBed ? .solo(action, [:]) : .service("button", "press", ["entity_id": button])
        run(effect, rollback: [("alarm", generation)])
    }

    // MARK: - Actions: alarm schedule

    /// Adds or replaces alarms from a draft (web `saveAlarm`); turns the room wake light's link for the alarm on
    /// or off first, as the web does, and saves nothing if that is refused.
    @discardableResult
    public func save(_ draft: AlarmDraft, wakeLight: WakeLightController?) async -> Bool {
        guard problems(draft).isEmpty else { return false }
        if let wakeLight, let source = wakeLight.config.source(for: config.side) {
            let keys = draft.days.map { WakeLight.linkKey(source: source.id, day: $0, time: draft.time) }
            guard await wakeLight.setLinks(keys, enabled: draft.wakeLightEnabled) else { return false }
        }
        let current = alarms
        let original = draft.editingId.flatMap { id in current.first { $0.id == id } }
        if draft.editingId != nil && original == nil { return false }
        let remaining = original.map { original in current.filter { $0.id != original.id } } ?? current
        let stamp = makeRequestId()
        let added = draft.days.enumerated().map { offset, day in
            var alarm = original ?? BedAlarm.new(day: day, time: draft.time, id: "")
            alarm.day = day
            alarm.enabled = draft.enabled
            alarm.time = draft.time
            alarm.index = remaining.filter { $0.day == day }.count
            alarm.id = original.flatMap { $0.day == day ? $0.id : nil } ?? "\(original == nil ? "new" : "edited")-\(stamp)-\(offset)-\(day.rawValue)"
            return alarm
        }
        setAlarms(remaining + added)
        return true
    }

    /// Deletes the draft's alarm, turning its wake link off first.
    @discardableResult
    public func delete(_ draft: AlarmDraft, wakeLight: WakeLightController?) async -> Bool {
        guard alarmsEditable, let id = draft.editingId, let alarm = alarms.first(where: { $0.id == id }) else { return false }
        if let wakeLight, let source = wakeLight.config.source(for: config.side) {
            guard await wakeLight.setLinks([WakeLight.linkKey(source: source.id, day: alarm.day, time: alarm.time)], enabled: false) else { return false }
        }
        setAlarms(alarms.filter { $0.id != id })
        return true
    }

    /// Turns one alarm on or off from its row toggle.
    @discardableResult
    public func setEnabled(_ alarm: BedAlarm, _ enabled: Bool) -> Bool {
        guard alarmsEditable, let current = alarms.first(where: { $0.id == alarm.id }), current == alarm else { return false }
        guard current.enabled != enabled else { return true }
        setAlarms(alarms.map { $0.id == alarm.id ? { var copy = $0; copy.enabled = enabled; return copy }($0) : $0 })
        return true
    }

    /// Creates bed alarms at `time` on `days` for the wake light's "Add to <bed>" (web `useWakeLightBedProvisioning`).
    public func createAlarms(days: [Weekday], time: String) {
        guard alarmsEditable, let time = ClockTime.normalized(time), !days.isEmpty else { return }
        let stamp = makeRequestId()
        let added = days.enumerated().map { BedAlarm.new(day: $1, time: time, id: "wake-light-\(stamp)-\($0)-\($1.rawValue)") }
        let next = (sourceAlarms + added).normalizedIndexes()
        if scope.controlsWholeBed {
            run(.solo("replace_alarms", ["alarm_rows": Self.alarmRows(next)]), rollback: [])
        } else {
            publish(SleepypodSchedule.alarmPayload(next, side: config.side))
        }
    }

    private func setAlarms(_ next: [BedAlarm]) {
        guard alarmsEditable else { return }
        let sorted = next.normalizedIndexes()
        if alarmOverride == nil { alarmBaseKey = sourceAlarms.contentKey }
        alarmOverride = sorted
        pendingAlarms = sorted
        alarmTimer?.cancel()
        alarmTimer = scheduler.schedule(after: Self.alarmDebounce) { [weak self] in self?.flushAlarms() }
    }

    private func flushAlarms() {
        alarmTimer = nil
        guard let records = pendingAlarms else { return }
        pendingAlarms = nil
        guard alarmsEditable, alarmBaseKey == sourceAlarms.contentKey || publishedAlarmKeys.contains(sourceAlarms.contentKey) else {
            dropAlarmOverride()
            return
        }
        publishedAlarmKeys = Array((publishedAlarmKeys + [records.contentKey]).suffix(8))
        if scope.controlsWholeBed {
            run(.solo("replace_alarms", ["alarm_rows": Self.alarmRows(records)]), rollback: [])
        } else {
            publish(SleepypodSchedule.alarmPayload(records, side: config.side))
        }
        alarmRevertTimer?.cancel()
        alarmRevertTimer = scheduler.schedule(after: Self.alarmListRevert) { [weak self] in self?.dropAlarmOverride() }
    }

    private func dropAlarmOverride() {
        alarmTimer?.cancel()
        alarmTimer = nil
        alarmRevertTimer?.cancel()
        alarmRevertTimer = nil
        pendingAlarms = nil
        alarmOverride = nil
        alarmBaseKey = nil
    }

    /// Reconciles the optimistic alarm list with Home Assistant (web: clear on a confirmed serialization, drop on
    /// someone else's change, keep across our own intermediate acknowledgements).
    private func reconcileAlarms() {
        let sourceKey = sourceAlarms.contentKey
        var acknowledged = false
        if let index = publishedAlarmKeys.firstIndex(of: sourceKey) {
            publishedAlarmKeys.removeSubrange(...index)
            alarmBaseKey = sourceKey
            acknowledged = true
        }
        guard let override = alarmOverride else { return }
        if override.contentKey == sourceKey, pendingAlarms == nil {
            dropAlarmOverride()
        } else if !acknowledged && alarmBaseKey != sourceKey {
            dropAlarmOverride()
        }
    }

    static func alarmRows(_ alarms: [BedAlarm]) -> [[String: any Sendable]] {
        alarms.map {
            ["alarmTemperature": $0.alarmTemperature, "day": $0.day.rawValue, "duration": $0.duration, "enabled": $0.enabled,
             "time": $0.time, "vibrationIntensity": $0.vibrationIntensity, "vibrationPattern": $0.vibrationPattern]
        }
    }

    // MARK: - Sending

    /// What a control sends.
    enum Effect {
        /// A plain service call.
        case service(String, String, [String: any Sendable])
        /// A Household Away `sleepypod_command` that controls the whole bed.
        case solo(String, [String: any Sendable])
    }

    private func publish(_ payload: JSONValue) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(payload), let text = String(data: data, encoding: .utf8) else { return }
        run(.service("mqtt", "publish", ["topic": MasterBedroom.scheduleSetTopic, "payload": text]), rollback: [])
    }

    private func run(_ effect: Effect, rollback: [(String, Int?)]) {
        let caller = caller
        let scope = scope
        let side = config.side
        let requestId = makeRequestId
        let task = Task { @MainActor [weak self] in
            var refused: String?
            do {
                switch effect {
                case let .service(domain, service, data):
                    try await caller.callService(domain, service, data: data)
                case let .solo(action, extra):
                    let data = scope.commandData(action: action, side: side, extra: extra, requestId: requestId())
                    let response = try await caller.callServiceWithResponse("script", MasterBedroom.householdAwayScript, data: data)
                    switch CommandOutcome(response: response) {
                    case .accepted?: break
                    case .rejected?: refused = "Home Assistant could not apply the Solo Trip change. Try again."
                    case nil: refused = "Home Assistant did not confirm the Solo Trip change. Wait for the dashboard to refresh before sending another request."
                    }
                }
            } catch {
                refused = "failed"
            }
            guard let self, let refused else { return }
            for (key, generation) in rollback { self.overlay.fail(key, generation: generation) }
            if case .solo = effect { self.commandError = refused }
        }
        inFlight.append(task)
    }

    /// Waits for every call started so far (tests).
    public func waitForCalls() async {
        let tasks = inFlight
        inFlight.removeAll()
        for task in tasks { await task.value }
    }

    // MARK: - Live updates

    private var observedIds: [String] {
        [config.climateEntityId, config.targetLevelEntityId, config.schedulePhaseEntityId, config.hotFlashActiveEntityId,
         config.alarmStateEntityId, MasterBedroom.scheduleEntityId, MasterBedroom.householdAwayEntityId]
            + config.stageLevelEntityIds.values.sorted()
    }

    func liveDidChange() {
        for id in [config.climateEntityId, config.targetLevelEntityId] {
            let value = live(id)
            if let value, !value.isUnavailable {
                if held[id] != value { held[id] = value }
                holdTimers[id]?.cancel()
                holdTimers[id] = nil
            } else if held[id] != nil, holdTimers[id] == nil {
                holdTimers[id] = scheduler.schedule(after: Self.unavailableHold) { [weak self] in
                    self?.held[id] = nil
                    self?.holdTimers[id] = nil
                }
            }
        }
        overlay.liveChanged("power", to: liveSideOn ? "on" : "off")
        overlay.liveChanged("target", to: liveTarget.map(Self.key))
        overlay.liveChanged("hotFlash", to: live(config.hotFlashActiveEntityId)?.state == "on" ? "on" : "off")
        overlay.liveChanged("alarm", to: BedAlarmState(state: live(config.alarmStateEntityId)?.state).rawValue)
        for phase in SchedulePhase.allCases {
            let value = config.stageLevelEntityIds[phase].flatMap(live).flatMap { Double($0.state) }
            overlay.liveChanged("stage.\(phase.rawValue)", to: value.map(Self.key))
        }
        // A new stage drops a pending target and any open scope question (web: phase change cancels the target).
        let phaseState = live(config.schedulePhaseEntityId)?.state
        if let last = lastPhaseState, last != phaseState {
            overlay.reset("target")
            if scopeRequest?.phase != activePhase { scopeRequest = nil }
        }
        lastPhaseState = .some(phaseState)
        if !sideAvailable || scope.readOnly { scopeRequest = nil }
        reconcileAlarms()
    }

    private func observeLive() {
        let ids = observedIds
        withObservationTracking {
            for id in ids { _ = store.entity(id).state }
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.liveDidChange()
                self?.observeLive()
            }
        }
    }

    // MARK: - Helpers

    /// The overlay key for a number (`3.0`), shared by commits and live values so they compare equal.
    static func key(_ value: Double) -> String { String(value) }

}
