import Foundation
import Observation

/// Drives one vacuum's sheet: live state from ``EntityStore``, optimistic values over it, the resolved status
/// and every command (web `VacuumCard.tsx`).
///
/// Home Assistant stays the source of truth. Optimistic values are feedback only: the vacuum state clears on any
/// live change, settings and rooms clear on confirmation, and everything reverts after its timeout. A clean waits
/// until every pending setting is confirmed and quiet, then starts, and reports an error if the vacuum never
/// begins (web `useVacuumCommandCoordinator`).
@MainActor
@Observable
public final class VacuumController {
    // MARK: - Types

    /// How a command button looks.
    public enum ActionTone: String, Sendable { case primary, neutral, warning, danger }

    /// One button in the Controls or Actions tab.
    public struct Action: Equatable, Sendable, Identifiable {
        public enum Kind: String, Sendable {
            case clean, cleanArea, dock, stop, resume, cancelResume, pause, cancelSession
            case cleanDock, stopDockClean, dryMops, stopDrying, emptyBin
        }
        public var kind: Kind
        public var title: String
        public var icon: String
        public var tone: ActionTone
        public var detail: String?
        public var isDisabled: Bool
        public var id: String { kind.rawValue }

        public init(kind: Kind, title: String, icon: String, tone: ActionTone, detail: String?, isDisabled: Bool) {
            self.kind = kind
            self.title = title
            self.icon = icon
            self.tone = tone
            self.detail = detail
            self.isDisabled = isDisabled
        }
    }

    /// A select row (mode, fan, water, passes).
    public struct Setting: Equatable, Sendable, Identifiable {
        public var entityId: String
        public var title: String
        public var icon: String
        public var detail: String?
        public var value: String
        public var valueLabel: String
        public var options: [String]
        public var isDisabled: Bool
        /// Which row of the Cleaning Settings group this is; `.other` outside it.
        public var role: VacuumSettingRole = .other
        public var id: String { entityId }

        /// Label for an option. Only the mode setting spells its options as modes ("Vacuum and Mop").
        public func label(for option: String) -> String {
            if role == .mode, let mode = VacuumCleaningMode(option: option).label { return mode }
            return role == .passes ? VacuumFormat.passes(option) : VacuumFormat.state(option)
        }
    }

    // MARK: - Timing (web constants)

    public static let optimisticRevert: Duration = .seconds(8)
    public static let cleanStartRevert: Duration = .seconds(30)
    static let settleQuiet: TimeInterval = 0.65

    // MARK: - Properties

    public let vacuum: VacuumConfig
    public let store: EntityStore
    /// `domain.service` names Home Assistant offers; `nil` until loaded.
    public var services: Set<String>?
    /// The drawn cleaning area, in grid cells.
    public var areaSelection: MapGridRect?

    /// The last clean failure, shown under the actions.
    public private(set) var cleanError: String?
    /// A clean was requested and the vacuum has not started yet.
    public private(set) var cleanStartPending = false
    /// A clean waits for settings to confirm.
    public private(set) var queuedClean: ServiceCall?
    /// Bumped on every intent; views use it to re-read pending state.
    public private(set) var intentRevision = 0

    let overlay: OptimisticOverlay
    private struct Intent { var value: String; var orderAt: Date; var generation: Int }
    private var intents: [String: Intent] = [:]
    @ObservationIgnored private var intentTimers: [String: any ScheduledWork] = [:]
    @ObservationIgnored private var settleTimer: (any ScheduledWork)?
    @ObservationIgnored private var cleanStartTimer: (any ScheduledWork)?
    @ObservationIgnored private var lastIntentAt: Date = .distantPast
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private let caller: any HassServiceCalling
    @ObservationIgnored private let scheduler: any RevertScheduler
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private var inFlight: [Task<Void, Never>] = []

    // MARK: - Init

    /// Creates a controller.
    /// - Parameters:
    ///   - vacuum: The vacuum.
    ///   - store: Live state.
    ///   - caller: The connection in the app, a recorder in tests and the gallery.
    ///   - scheduler: Runs revert and settle timers.
    ///   - now: The clock for room order and the settle window.
    public init(vacuum: VacuumConfig, store: EntityStore, caller: any HassServiceCalling,
                scheduler: any RevertScheduler = TaskRevertScheduler(), now: @escaping @MainActor () -> Date = Date.init) {
        self.vacuum = vacuum
        self.store = store
        self.caller = caller
        self.scheduler = scheduler
        self.now = now
        var rules: [String: OptimisticOverlay.ClearRule] = [vacuum.entityId: .liveChange, vacuum.statusFlagEntityId: .confirmation]
        if let dock = vacuum.dockControls { rules[dock.dockStatusEntityId] = .confirmation }
        for room in vacuum.autoCleanDisabledRooms { rules[room.entityId] = .confirmation }
        overlay = OptimisticOverlay(rules: rules, scheduler: scheduler)
        liveDidChange()
        observeLive()
    }

    // MARK: - Reading

    func entity(_ id: String?) -> EntityState? { id.flatMap { store.entity($0).state } }
    func live(_ id: String?) -> String? { entity(id)?.state }

    /// The vacuum's live state, or `unknown`.
    public var liveState: String { live(vacuum.entityId) ?? "unknown" }

    /// The shown vacuum state.
    public var state: String { overlay.displayed(vacuum.entityId, live: liveState) ?? liveState }

    /// The resolved status and command policy.
    public var status: ResolvedVacuumStatus {
        let flag = entity(vacuum.statusFlagEntityId)
        return VacuumStatusResolver.resolve(.init(
            vacuumEntityId: vacuum.entityId, vacuumState: live(vacuum.entityId), vacuumExists: entity(vacuum.entityId) != nil,
            batteryState: live(vacuum.batteryEntityId), errorState: live(vacuum.errorEntityId),
            statusFlagState: flag?.state, statusFlagChanged: flag?.lastChanged,
            hasDockControls: vacuum.dockControls != nil, dockState: live(vacuum.dockControls?.dockStatusEntityId),
            statusAttributes: entity(vacuum.statusEntityId)?.attributes))
    }

    /// Full (cleaning setup) or minimal (runtime actions only).
    public var runtimeMode: VacuumRuntimeMode {
        VacuumRuntime.mode(policy: status.policyMode, displayState: state, statusFlag: live(vacuum.statusFlagEntityId), error: live(vacuum.errorEntityId))
    }

    /// Tabs for the current mode.
    public var tabs: [VacuumTab] { tabs(in: runtimeMode) }

    /// Tabs for `mode`: the sheet keeps showing the outgoing mode's tabs while its content fades out.
    public func tabs(in mode: VacuumRuntimeMode) -> [VacuumTab] {
        VacuumRuntime.tabs(for: vacuum, mode: mode, dockState: live(vacuum.dockControls?.dockStatusEntityId))
    }

    /// The state shown in the status pill (live while unavailable).
    public var statusState: String { status.primaryAvailable ? state : liveState }

    /// `87%`, or Unknown.
    public var batteryLabel: String {
        guard status.primaryAvailable, let battery = live(vacuum.batteryEntityId), !VacuumStatusResolver.isUnavailable(battery) else { return "Unknown" }
        return "\(battery)%"
    }

    /// The coordinator's while-away report, with Main Floor reconciliations applied.
    public var whileAway: VacuumWhileAway {
        var reconciled: [String: String] = [:]
        for (roomId, entityId) in Vacuums.outcomeReconciliations(vacuum.vacuumMapId) {
            if let value = live(entityId), !value.isEmpty { reconciled[roomId] = value }
        }
        return VacuumWhileAway.read(entity(vacuum.coordinatorSessionEntityId)?.attributes, reconciled: reconciled)
    }

    /// The dock's live state.
    public var dockState: String? { live(vacuum.dockControls?.dockStatusEntityId) }

    /// The dock status label.
    public var dockLabel: String { status.primaryAvailable ? VacuumFormat.state(dockState, fallback: "Unknown") : "Unknown" }

    var isResumable: Bool { live(vacuum.statusFlagEntityId) == "resumable" }
    var isLowBattery: Bool { live(vacuum.errorEntityId) == "Low battery" }

    /// The dock is washing pads before a run leaves (`vacuumDockPreparationActive`).
    public var dockPreparationActive: Bool { state == "cleaning" && displayedDockState == "cleaning" }

    var displayedDockState: String {
        guard let id = vacuum.dockControls?.dockStatusEntityId else { return "unknown" }
        return overlay.displayed(id, live: live(id) ?? "unknown") ?? "unknown"
    }

    /// Whether `domain.service` exists (`hassServiceAvailable`).
    public func hasService(_ action: String) -> Bool { services?.contains(action) ?? false }

    // MARK: - Settings

    /// A select's shown value: a pending intent, else live.
    public func displayedValue(_ entityId: String) -> String? { intents[entityId]?.value ?? live(entityId) }

    /// Commands are blocked while a clean is starting.
    public var controlsDisabled: Bool { cleanStartPending }

    /// Normal commands (clean, start) are blocked.
    public var normalCommandsDisabled: Bool { controlsDisabled || status.policyMode != .normal }
    var recoveryCommandsDisabled: Bool { controlsDisabled || status.policyMode == .none }

    func setting(_ entityId: String?, title: String, icon: String, detail: String?, disabled: Bool, valueLabel: String? = nil) -> Setting? {
        guard let entityId, let entity = entity(entityId) else { return nil }
        let options = entity.attributes["options"]?.array?.compactMap(\.string) ?? []
        let value = displayedValue(entityId) ?? ""
        let label = value == entity.state && valueLabel != nil ? valueLabel! : (entityId == vacuum.passesEntityId ? VacuumFormat.passes(value) : VacuumFormat.state(value, fallback: title))
        let shown = options.contains(value) || value.isEmpty ? options : [value] + options
        return Setting(entityId: entityId, title: title, icon: icon, detail: detail, value: value, valueLabel: label,
                       options: shown, isDisabled: disabled || entity.isUnavailable || options.isEmpty,
                       role: entityId == vacuum.passesEntityId ? .passes : .other)
    }

    /// Mode, fan and water, as the web's Power Settings shows them: only the rows that show now.
    public var powerSettings: [Setting] { powerSettings(in: runtimeMode) }

    /// Power settings as shown in `mode` (none in minimal mode).
    public func powerSettings(in mode: VacuumRuntimeMode) -> [Setting] {
        settingRows(in: mode).filter { $0.isShown && $0.role != .passes }.map(\.setting)
    }

    /// Every row of the Cleaning Settings group in `mode`: Mode, Fan, Water and, while a clean can be set up, Passes. A row
    /// the chosen mode makes meaningless is still listed with `isShown` false, so the sheet can animate it in and out.
    public func settingRows(in mode: VacuumRuntimeMode) -> [VacuumCleaningSettingRow] {
        guard mode == .full else { return [] }
        let disabled = controlsDisabled
        let modeEntity = entity(vacuum.modeEntityId)
        let hasMode = vacuum.modeEntityId != nil && !(modeEntity?.isUnavailable ?? true)
        let shownMode = hasMode ? displayedValue(vacuum.modeEntityId ?? "") : modeEntity?.state
        let chosen = VacuumCleaningMode(option: shownMode)
        let modeText = live(vacuum.modeTextEntityId)
        let meaningful = modeText.map { !VacuumStatusResolver.isUnavailable($0) } ?? false
        // The web shows the helper text as is; here a text that names a known mode reads like the menu ("Vacuum and Mop"),
        // a recorded departure for consistency (owner, 2026-10-29). Any other text is shown raw.
        let modeValue = modeText.map { VacuumCleaningMode(option: $0).label ?? $0 }
        var rows: [VacuumCleaningSettingRow] = []
        if hasMode, let row = setting(vacuum.modeEntityId, title: "Mode", icon: "mdi:robot-vacuum",
                                      detail: "Choose whether the robot vacuums, mops, or combines both for the next run.",
                                      disabled: disabled, valueLabel: meaningful ? modeValue : nil) {
            rows.append(.init(setting: row, role: .mode, isShown: true))
        }
        if !(entity(vacuum.fanEntityId)?.isUnavailable ?? true),
           let row = setting(vacuum.fanEntityId, title: "Fan", icon: "mdi:fan",
                             detail: "Adjust suction strength for carpets, hard floors, and quieter cleaning.", disabled: disabled) {
            rows.append(.init(setting: row, role: .fan, isShown: chosen.showsFan))
        }
        if !(entity(vacuum.waterEntityId)?.isUnavailable ?? true),
           let row = setting(vacuum.waterEntityId, title: "Water", icon: "mdi:water",
                             detail: "Set mop water flow so floors get the right amount of moisture.", disabled: disabled) {
            rows.append(.init(setting: row, role: .water, isShown: !hasMode || chosen.showsWater))
        }
        if showsCleaningSetup(in: mode), let passes = passesSetting {
            rows.append(.init(setting: passes, role: .passes, isShown: true))
        }
        return rows
    }

    /// Cleaning passes.
    public var passesSetting: Setting? {
        setting(vacuum.passesEntityId, title: "Passes", icon: "mdi:numeric", detail: nil,
                disabled: normalCommandsDisabled, valueLabel: VacuumFormat.passes(live(vacuum.passesEntityId)))
    }

    /// Picks an option, showing it at once and holding any clean until Home Assistant confirms it.
    public func select(_ entityId: String, option: String) {
        guard displayedValue(entityId) != option else { return }
        registerIntent(entityId, option)
        perform(ServiceCall(String(entityId.prefix { $0 != "." }), "select_option", target: entityId, data: ["option": .string(option)]))
    }

    // MARK: - Rooms

    /// The 1-based cleaning order of each selected room by entity id. A zone repeated by the house document keeps its first order.
    public var roomOrders: [String: Int] { Self.roomOrders(for: selectedZones) }

    /// The 1-based order of each zone by entity id; a zone listed twice keeps its first place.
    /// - Parameter zones: The zones in cleaning order.
    public static func roomOrders(for zones: [VacuumConfig.Zone]) -> [String: Int] {
        Dictionary(zones.enumerated().map { ($1.entityId, $0 + 1) }, uniquingKeysWith: { first, _ in first })
    }

    /// Selected rooms in cleaning order (`orderedSelectedVacuumZones`).
    public var selectedZones: [VacuumConfig.Zone] {
        vacuum.zones.enumerated().compactMap { index, zone -> (Double, Int, VacuumConfig.Zone)? in
            guard isSelected(zone) else { return nil }
            let order: Double
            if let intent = intents[zone.entityId] { order = intent.orderAt.timeIntervalSince1970 }
            else if let changed = entity(zone.entityId)?.lastChanged, changed != .distantPast { order = changed.timeIntervalSince1970 }
            else { order = Double(index) }
            return (order, index, zone)
        }
        .sorted { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1 < $1.1 }
        .map(\.2)
    }

    /// Whether a room is selected (pending intent first).
    public func isSelected(_ zone: VacuumConfig.Zone) -> Bool { displayedValue(zone.entityId) == "on" }

    /// A room's 1-based cleaning order.
    public func order(of zone: VacuumConfig.Zone) -> Int? {
        selectedZones.firstIndex { $0.entityId == zone.entityId }.map { $0 + 1 }
    }

    /// Rooms can change only in full mode while no clean is starting.
    public var roomsEditable: Bool { runtimeMode == .full && !controlsDisabled }

    /// Turning a room on while an area is drawn discards the area, so the view confirms first.
    public func roomToggleNeedsConfirmation(_ zone: VacuumConfig.Zone) -> Bool { !isSelected(zone) && areaSelection != nil }

    /// Flips a room and sets the mode its rooms need (`toggleRoom`).
    public func toggleRoom(_ zone: VacuumConfig.Zone) {
        guard runtimeMode == .full else { return }
        let next = !isSelected(zone)
        if next { areaSelection = nil }
        registerIntent(zone.entityId, next ? "on" : "off")
        perform(ServiceCall("input_boolean", next ? "turn_on" : "turn_off", target: zone.entityId))
        let rooms = vacuum.zones.filter { $0.entityId == zone.entityId ? next : isSelected($0) }
        setRoomMode(rooms)
    }

    func requiresMop(_ zone: VacuumConfig.Zone) -> Bool {
        if let hint = entity(zone.mopRequiredEntityId)?.attributes["mop_required"]?.bool { return hint }
        return zone.mopRequired ?? true
    }

    private func setRoomMode(_ rooms: [VacuumConfig.Zone]) {
        guard let modeId = vacuum.modeEntityId, !rooms.isEmpty else { return }
        let option = rooms.allSatisfy { !requiresMop($0) } ? "vacuum" : "vacuum_and_mop"
        let options = entity(modeId)?.attributes["options"]?.array?.compactMap(\.string) ?? []
        guard options.contains(option), displayedValue(modeId) != option else { return }
        select(modeId, option: option)
    }

    /// Clears selected rooms before drawing an area (the view confirms first when any are selected).
    public func clearRoomsForArea() {
        for zone in selectedZones {
            registerIntent(zone.entityId, "off")
            perform(ServiceCall("input_boolean", "turn_off", target: zone.entityId))
        }
    }

    // MARK: - Auto-clean rooms

    /// Whether the coordinator skips a room.
    public func isAutoCleanDisabled(_ room: VacuumConfig.AutoCleanRoom) -> Bool {
        overlay.displayed(room.entityId, live: live(room.entityId)) == "on"
    }

    /// Flips a room's skip switch.
    public func toggleAutoClean(_ room: VacuumConfig.AutoCleanRoom) {
        guard let liveValue = live(room.entityId), !VacuumStatusResolver.isUnavailable(liveValue) else { return }
        let next = !isAutoCleanDisabled(room)
        commitOverlay(room.entityId, next ? "on" : "off", revert: Self.optimisticRevert)
        perform(ServiceCall("switch", next ? "turn_on" : "turn_off", target: room.entityId))
    }

    // MARK: - Runtime actions

    /// Buttons for the Controls tab (`VacuumStateActions`), cleaning setup excluded.
    public var runtimeActions: [Action] {
        let state = state
        guard !VacuumStatusResolver.isUnavailable(state) else { return [] }
        let resumable = isResumable
        let cancelPending = resumable && live(vacuum.statusFlagEntityId) != overlay.displayed(vacuum.statusFlagEntityId, live: live(vacuum.statusFlagEntityId))
        let recovery = recoveryCommandsDisabled
        let prep = dockPreparationActive
        var actions: [Action] = []
        func add(_ kind: Action.Kind, _ title: String, _ icon: String, _ tone: ActionTone, _ detail: String, _ disabled: Bool) {
            actions.append(.init(kind: kind, title: title, icon: icon, tone: tone, detail: detail, isDisabled: disabled))
        }
        if state == "idle" { add(.dock, "Dock", "mdi:home", .neutral, "Send the robot back to the dock.", recovery || cancelPending) }
        if state == "error" && !resumable && !isLowBattery {
            add(.stop, "Stop", "mdi:stop", .danger, "Stop the current vacuum task.", recovery)
            add(.dock, "Dock", "mdi:home", .neutral, "Send the robot back to the dock.", recovery)
        }
        if resumable && (state == "docked" || state == "idle") {
            add(.resume, "Resume", "mdi:play", .primary, "Continue the interrupted cleaning run.", recovery || cancelPending)
        }
        if resumable && ["docked", "error", "idle", "returning"].contains(state) {
            add(.cancelResume, "Cancel", "mdi:stop", .danger, "Cancel the pending cleaning resume.", recovery || cancelPending)
        }
        if state == "cleaning" {
            add(.pause, "Pause", "mdi:pause", .warning,
                prep ? "Pause becomes available after the robot leaves the dock." : "Pause the current cleaning run.", recovery || prep)
            if prep {
                add(.cancelSession, "Cancel Cleaning Session", "mdi:stop", .danger, "Cancel this cleaning session before the robot leaves the dock.", recovery)
            } else {
                add(.stop, "Stop", "mdi:stop", .danger, "Stop the current cleaning run.", recovery)
            }
        }
        if state == "paused" {
            add(.resume, "Resume", "mdi:play", .primary, "Continue the paused cleaning run.", recovery)
            add(.stop, "Stop", "mdi:stop", .danger, "Stop the paused cleaning run.", recovery)
        }
        if state == "returning" { add(.pause, "Pause", "mdi:pause", .warning, "Pause the return-to-dock action.", recovery || cancelPending) }
        return actions
    }

    /// The cleaning setup shows (full mode, no pending resume).
    public var showsCleaningSetup: Bool { showsCleaningSetup(in: runtimeMode) }

    /// Whether the cleaning setup shows in `mode`.
    public func showsCleaningSetup(in mode: VacuumRuntimeMode) -> Bool { mode == .full && !isResumable }

    /// The Clean button for selected rooms.
    public var cleanAction: Action {
        .init(kind: .clean, title: "Clean", icon: "mdi:play", tone: .primary, detail: nil, isDisabled: normalCommandsDisabled)
    }

    /// Whether area cleaning is configured.
    public var supportsAreaCleaning: Bool { vacuum.areaCleaning != nil }

    /// The area script is installed (else the web shows a local-preview note).
    public var areaServiceReady: Bool { vacuum.areaCleaning.map { hasService($0.script) } ?? false }

    /// The Clean button for the drawn area (it reads Clean in both modes, owner 2026-10-28). `mapReady` and `selectionAllowed` come from the map.
    public func areaCleanAction(mapReady: Bool, selectionAllowed: Bool) -> Action {
        .init(kind: .cleanArea, title: "Clean", icon: "mdi:play", tone: .primary, detail: nil,
              isDisabled: runtimeMode != .full || areaSelection == nil || !selectionAllowed || !mapReady || !areaServiceReady || normalCommandsDisabled)
    }

    /// Runs a Controls or Actions button.
    /// - Parameter pixelSize: The map's cell size, for ``Action/Kind/cleanArea``.
    public func run(_ kind: Action.Kind, pixelSize: Double? = nil) {
        switch kind {
        case .clean: requestClean(ServiceCall.action(vacuum.cleanScript))
        case .cleanArea:
            guard let area = vacuum.areaCleaning, let rect = areaSelection, let pixelSize else { return }
            requestClean(ServiceCall.action(area.script, data: rect.serviceData(pixelSize: pixelSize)))
        case .dock: commitAndCall("returning", "return_to_base")
        case .stop: liveState == "error" ? commitAndCall("idle", "stop") : commitAndCall("returning", "return_to_base")
        case .cancelSession: commitAndCall("docked", "return_to_base")
        case .cancelResume:
            commitOverlay(vacuum.statusFlagEntityId, "none", revert: Self.optimisticRevert)
            commitAndCall(state == "docked" ? "docked" : "idle", "stop")
        case .pause: commitAndCall("paused", "pause")
        case .resume: commitAndCall("cleaning", "start")
        case .cleanDock, .stopDockClean: runDock(clean: true)
        case .dryMops, .stopDrying: runDock(clean: false)
        case .emptyBin:
            guard let button = vacuum.dockButtonEntityId else { return }
            perform(ServiceCall("button", "press", target: button))
        }
    }

    /// Asks the robot to beep (`vacuum.locate`).
    public func locate() { perform(ServiceCall("vacuum", "locate", target: vacuum.entityId)) }

    private func commitAndCall(_ next: String, _ service: String) {
        guard status.policyMode != .none else { return }
        // A robot in an error state flaps through other states while it tries the command, and the first change would
        // drop the optimistic value (the tap looked ignored): hold it until confirmed or reverted.
        let rule: OptimisticOverlay.ClearRule? = liveState == "error" ? .confirmation : nil
        overlay.commit(vacuum.entityId, value: next, live: liveState, revertAfter: Self.optimisticRevert, clearing: rule)
        perform(ServiceCall("vacuum", service, target: vacuum.entityId))
    }

    // MARK: - Dock

    /// Whether the dock bridge service exists (`valetudo_vacuum_coordinator.dock_action`).
    public var dockBridgeAvailable: Bool { hasService("valetudo_vacuum_coordinator.dock_action") }

    /// The mop pads are attached.
    public var mopAttached: Bool { live(vacuum.dockControls?.mopAttachmentEntityId) == "on" }

    /// Buttons for the Actions tab (`VacuumDockControlsSection`). In minimal mode only an active wash or dry shows.
    public var dockActions: [Action] {
        guard vacuum.dockButtonEntityId != nil || vacuum.dockControls != nil else { return [] }
        let activeOnly = runtimeMode == .minimal
        let dockState = displayedDockState
        let docked = state == "docked"
        let cleanActive = dockState == "cleaning", dryActive = dockState == "drying"
        let startAllowed = status.policyMode == .normal && !controlsDisabled
        let stopAllowed = status.policyMode != .none && !controlsDisabled
        var actions: [Action] = []
        if let dock = vacuum.dockControls {
            if (!activeOnly || cleanActive) && !dockPreparationActive {
                let allowed = docked && mopAttached && dockBridgeAvailable && hasService(dock.cleanScript)
                    && ["idle", "cleaning", "pause"].contains(dockState) && (cleanActive ? stopAllowed : startAllowed)
                actions.append(cleanActive
                    ? .init(kind: .stopDockClean, title: "Stop Dock Clean", icon: "mdi:stop", tone: .warning,
                            detail: "Finish the dock-cleaning phase and drain the wash tray into the dirty-water tank.", isDisabled: !allowed)
                    : .init(kind: .cleanDock, title: "Clean Mop Dock", icon: "mdi:water", tone: .neutral,
                            detail: "Start the mop-dock cleaning phase. Use Stop Dock Clean when finished so the dock drains the wash tray.", isDisabled: !allowed))
            }
            if !activeOnly || dryActive {
                let allowed = docked && mopAttached && dockBridgeAvailable && hasService(dock.dryScript)
                    && ["idle", "drying", "pause"].contains(dockState) && (dryActive ? stopAllowed : startAllowed)
                actions.append(dryActive
                    ? .init(kind: .stopDrying, title: "Stop Mop Drying", icon: "mdi:stop", tone: .neutral, detail: "Stop the current mop-drying cycle.", isDisabled: !allowed)
                    : .init(kind: .dryMops, title: "Dry Mops", icon: "mdi:weather-windy", tone: .neutral, detail: "Start drying the attached mop pads.", isDisabled: !allowed))
            }
        }
        if vacuum.dockButtonEntityId != nil && !activeOnly {
            actions.append(.init(kind: .emptyBin, title: "Empty Bin", icon: "mdi:delete-restore", tone: .neutral,
                                 detail: "Trigger the dock to empty the robot dustbin into its dust bag.",
                                 isDisabled: !(docked && ["idle", "pause"].contains(dockState) && startAllowed)))
        }
        return actions
    }

    private func runDock(clean: Bool) {
        guard let dock = vacuum.dockControls, let action = dockActions.first(where: {
            clean ? [.cleanDock, .stopDockClean].contains($0.kind) : [.dryMops, .stopDrying].contains($0.kind)
        }), !action.isDisabled else { return }
        let active = displayedDockState == (clean ? "cleaning" : "drying")
        commitOverlay(dock.dockStatusEntityId, active ? "idle" : (clean ? "cleaning" : "drying"), revert: Self.optimisticRevert)
        perform(ServiceCall.action(clean ? dock.cleanScript : dock.dryScript))
    }

    // MARK: - Clean coordination

    var settingsSettled: Bool { intents.isEmpty && now().timeIntervalSince(lastIntentAt) >= Self.settleQuiet }

    func registerIntent(_ entityId: String, _ value: String) {
        let date = now()
        lastIntentAt = date
        generation += 1
        let generation = generation
        intents[entityId] = Intent(value: value, orderAt: date, generation: generation)
        intentRevision += 1
        intentTimers[entityId]?.cancel()
        intentTimers[entityId] = scheduler.schedule(after: Self.optimisticRevert) { [weak self] in
            guard let self, self.intents[entityId]?.generation == generation else { return }
            self.intents[entityId] = nil
            self.intentTimers[entityId] = nil
            if self.cleanStartPending || self.queuedClean != nil {
                self.failClean("The vacuum settings did not confirm before cleaning could start.")
            }
        }
    }

    private func requestClean(_ call: ServiceCall) {
        guard status.policyMode == .normal else {
            failClean("The queued cleaning request was canceled because the vacuum is no longer ready. Retry when ready.")
            return
        }
        cleanError = nil
        commitOverlay(vacuum.entityId, "cleaning", revert: Self.cleanStartRevert)
        cleanStartPending = true
        if settingsSettled { invokeClean(call) } else { queuedClean = call; scheduleSettleCheck() }
    }

    private func invokeClean(_ call: ServiceCall) {
        queuedClean = nil
        guard status.policyMode == .normal else {
            failClean("The queued cleaning request was canceled because the vacuum is no longer ready. Retry when ready.")
            return
        }
        perform(call) { [weak self] _ in self?.failClean("Home Assistant rejected the cleaning request.") }
        cleanStartTimer?.cancel()
        cleanStartTimer = scheduler.schedule(after: Self.cleanStartRevert) { [weak self] in
            guard let self, self.cleanStartPending else { return }
            self.failClean("The vacuum did not begin cleaning within 30 seconds.")
        }
    }

    private func failClean(_ message: String) {
        cleanError = message
        queuedClean = nil
        cleanStartPending = false
        cleanStartTimer?.cancel()
        cleanStartTimer = nil
        overlay.reset(vacuum.entityId)
    }

    private func scheduleSettleCheck() {
        guard queuedClean != nil, intents.isEmpty else { return }
        settleTimer?.cancel()
        let remaining = max(0, Self.settleQuiet - now().timeIntervalSince(lastIntentAt))
        settleTimer = scheduler.schedule(after: .milliseconds(Int(remaining * 1000))) { [weak self] in
            guard let self, let call = self.queuedClean else { return }
            if self.settingsSettled { self.invokeClean(call) } else { self.scheduleSettleCheck() }
        }
    }

    // MARK: - Calls

    private func commitOverlay(_ key: String, _ value: String, revert: Duration) {
        overlay.commit(key, value: value, live: live(key), revertAfter: revert)
    }

    private func perform(_ call: ServiceCall, onFailure: (@MainActor (Error) -> Void)? = nil) {
        let caller = caller
        inFlight.append(Task { @MainActor in
            do { try await caller.call(call) } catch { onFailure?(error) }
        })
    }

    /// Waits for every service call so far (tests).
    public func waitForCalls() async {
        let tasks = inFlight
        inFlight.removeAll()
        for task in tasks { await task.value }
    }

    // MARK: - Live changes

    var observedEntityIds: [String] {
        var ids = Set(overlay.trackedKeys)
        ids.formUnion([vacuum.entityId, vacuum.errorEntityId, vacuum.statusFlagEntityId, vacuum.statusEntityId, vacuum.batteryEntityId, vacuum.passesEntityId])
        ids.formUnion([vacuum.modeEntityId, vacuum.fanEntityId, vacuum.waterEntityId, vacuum.dockControls?.dockStatusEntityId].compactMap { $0 })
        ids.formUnion(vacuum.zones.map(\.entityId))
        ids.formUnion(vacuum.zones.compactMap(\.mopRequiredEntityId))
        return ids.sorted()
    }

    func liveDidChange() {
        for key in overlay.trackedKeys { overlay.liveChanged(key, to: live(key)) }
        var confirmed = false
        for (id, intent) in intents where live(id) == intent.value {
            intents[id] = nil
            intentTimers[id]?.cancel()
            intentTimers[id] = nil
            confirmed = true
        }
        if confirmed { intentRevision += 1; scheduleSettleCheck() }
        if cleanStartPending && liveState == "cleaning" {
            cleanStartPending = false
            queuedClean = nil
            cleanError = nil
            cleanStartTimer?.cancel()
            cleanStartTimer = nil
        }
        if queuedClean != nil && status.policyMode != .normal {
            failClean("The queued cleaning request was canceled because the vacuum is no longer ready. Retry when ready.")
        }
    }

    private func observeLive() {
        let ids = observedEntityIds
        withObservationTracking {
            for id in ids { _ = store.entity(id).state }
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.liveDidChange()
                self?.observeLive()
            }
        }
    }
}

extension ServiceCall {
    /// `script.name` → a call with no target (`callServiceAction`).
    static func action(_ action: String, data: [String: JSONValue] = [:]) -> ServiceCall {
        let parts = action.split(separator: ".", maxSplits: 1).map(String.init)
        return ServiceCall(parts.first ?? action, parts.count > 1 ? parts[1] : "", data: data)
    }
}
