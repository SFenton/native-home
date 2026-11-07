import Foundation
import Observation

/// Drives one media remote: reads live state from ``EntityStore``, layers optimistic values over it and runs
/// actions through one ``HassServiceCalling`` (web `MediaRemoteModalContent.tsx`).
///
/// Views read the derived values below, which observe only the entities they touch, and call the action
/// methods. Home Assistant stays the source of truth: optimistic values are feedback only and clear on
/// confirmation, failure or their revert time.
@MainActor
@Observable
public final class MediaRemoteController {
    // MARK: - Types

    /// How a device tile shows (web `DeviceButton`).
    public struct DeviceDisplay: Equatable, Sendable {
        /// The shown state after optimistic values and holds.
        public var state: String
        public var subtitle: String
        public var isActive: Bool
        public var isUnavailable: Bool
        /// Unavailable and actionable: the tile can't be tapped.
        public var isDisabled: Bool
        public var semantics: ControlSemantics
    }

    /// How an app tile shows (web `AppButton`).
    public struct AppDisplay: Equatable, Sendable {
        public var isActive: Bool
        public var isUnavailable: Bool
        public var semantics: ControlSemantics
    }

    /// A Hue Sync on/off tile (web `HueSyncToggleTile`).
    public struct ToggleDisplay: Equatable, Sendable {
        public var isOn: Bool
        public var isUnavailable: Bool
        public var subtitle: String
    }

    /// A Hue Sync select (web `useHueSyncSelectControl`).
    public struct SelectDisplay: Equatable, Sendable {
        public var selected: String
        public var options: [String]
        public var isUnavailable: Bool
    }

    /// The Hue Sync brightness slider (web `HueSyncBrightnessField`).
    public struct BrightnessDisplay: Equatable, Sendable {
        public var value: Double
        public var range: ClosedRange<Double>
        public var step: Double
        public var isUnavailable: Bool
        /// Read instead of the number while unavailable.
        public var unavailableText: String?
    }

    /// One HDMI input tile (web `HueSyncHdmiInputTile`).
    public struct HdmiInputDisplay: Equatable, Sendable, Identifiable {
        public var option: String
        public var statusEntityId: String
        public var isSelected: Bool
        public var isDisconnected: Bool
        public var isDisabled: Bool
        public var subtitle: String
        public var id: String { option }
    }

    // MARK: - Properties

    /// The remote.
    public let config: MediaRemoteConfig
    /// Live state.
    public let store: EntityStore
    /// Optimistic entity states for ``MediaRemoteConfig/optimisticEntityIds``.
    public let overlay: OptimisticOverlay
    /// The optimistic volume slider value (percent), keyed by the volume entity.
    public let volumeOverlay: OptimisticOverlay
    let holds: ActiveHoldTracker

    @ObservationIgnored private let caller: any HassServiceCalling
    @ObservationIgnored private var inFlight: [Task<Void, Never>] = []

    /// How long the volume slider keeps its value while waiting for the speaker (web `VOLUME_OPTIMISTIC_REVERT_MS`).
    public static let volumeRevert: Duration = .milliseconds(2500)

    // MARK: - Init

    /// Creates a controller.
    /// - Parameters:
    ///   - config: The remote.
    ///   - store: Live state.
    ///   - caller: Where service calls go: the connection in the app, a recorder in tests.
    ///   - scheduler: Runs revert and hold timers.
    public init(config: MediaRemoteConfig, store: EntityStore, caller: any HassServiceCalling, scheduler: any RevertScheduler = TaskRevertScheduler()) {
        self.config = config
        self.store = store
        self.caller = caller
        let liveChange = Set(config.liveChangeEntityIds)
        var rules: [String: OptimisticOverlay.ClearRule] = [:]
        for id in config.optimisticEntityIds { rules[id] = liveChange.contains(id) ? .liveChange : .confirmation }
        overlay = OptimisticOverlay(rules: rules, scheduler: scheduler)
        volumeOverlay = OptimisticOverlay(rules: [config.volumeEntityId: .confirmation], scheduler: scheduler)
        holds = ActiveHoldTracker(scheduler: scheduler)
        liveDidChange()
        observeLive()
    }

    // MARK: - Reading state

    /// An entity's live state.
    public func liveState(_ entityId: String) -> String? { store.entity(entityId).state?.state }

    /// An entity's shown state: optimistic if pending, else live.
    public func displayedState(_ entityId: String) -> String? { overlay.displayed(entityId, live: liveState(entityId)) }

    /// The control entity is off, unavailable or unknown.
    public var isControlOff: Bool { MediaRemoteState.isOff(displayedState(config.controlEntityId)) }

    /// The d-pad, navigation and playback controls are disabled.
    public var controlsDisabled: Bool { isControlOff }

    /// The keyboard button is hidden (only with ``MediaRemoteConfig/hideKeyboardWhenOff``).
    public var hidesKeyboard: Bool { config.hideKeyboardWhenOff && isControlOff }

    /// The volume entity is off or unavailable: its slider and buttons are disabled.
    public var volumeDisabled: Bool { MediaRemoteState.isOff(liveState(config.volumeEntityId)) }

    /// Whether the volume section shows.
    public var showsVolume: Bool {
        config.showVolumeWhenOff ? store.entity(config.volumeEntityId).state != nil : !volumeDisabled
    }

    /// The speaker's live volume in percent.
    public var liveVolumePercent: Int {
        let level = store.entity(config.volumeEntityId).state?.attributes["volume_level"]?.number ?? 0
        return Int((level * 100).rounded())
    }

    /// The slider's shown volume in percent.
    public var volumePercent: Int {
        volumeOverlay.displayed(config.volumeEntityId, live: String(liveVolumePercent)).flatMap(Int.init) ?? liveVolumePercent
    }

    /// The power pill's visible text.
    public var powerTitle: String { isControlOff ? "Power On" : "Power Off" }

    /// A button's semantics; the power button decides from the control entity's shown state.
    public func semantics(for button: MediaRemoteButton) -> ControlSemantics {
        let state = button == config.power ? displayedState(config.controlEntityId) : nil
        return button.semantics?.semantics(for: state) ?? .command
    }

    /// A button's icon tone, if it has a color rule.
    public func iconTone(for button: MediaRemoteButton) -> IconTone? {
        button.iconColorRule?.tone(displayedState: displayedState)
    }

    // MARK: - Devices and apps

    /// How a device tile shows.
    public func display(_ device: MediaRemoteDevice) -> DeviceDisplay {
        let facts = deviceFacts(device)
        let shown = holds.held(device.title, displayed: facts.displayed, activeStates: device.activeStates,
                               hasOverride: facts.hasOverride, hold: device.activeHold)
        let unavailable = EntityState.isUnavailable(facts.live)
        let active = device.activeStates.isEmpty ? !MediaRemoteState.isOff(shown) : device.activeStates.contains(shown)
        return DeviceDisplay(
            state: shown,
            subtitle: device.stateLabels[shown] ?? MediaRemoteState.format(shown),
            isActive: active,
            isUnavailable: unavailable,
            isDisabled: unavailable && device.action != nil,
            semantics: device.semantics?.semantics(for: shown) ?? (device.action == nil ? .state : .command)
        )
    }

    /// How an app tile shows.
    public func display(_ app: MediaRemoteApp) -> AppDisplay {
        let live = app.stateEntityId.flatMap(liveState)
        let shown = app.stateEntityId.flatMap(displayedState)
        return AppDisplay(
            isActive: shown.map(app.activeStates.contains) ?? false,
            isUnavailable: app.stateEntityId != nil && EntityState.isUnavailable(live),
            semantics: app.semantics?.semantics(for: shown) ?? .command
        )
    }

    private struct DeviceFacts {
        var live: String
        var displayed: String
        var hasOverride: Bool
    }

    private func deviceFacts(_ device: MediaRemoteDevice) -> DeviceFacts {
        let ids = device.stateEntityIds ?? [device.entityId]
        var liveStates: [String: String] = [:]
        var shownStates: [String: String] = [:]
        for id in ids {
            liveStates[id] = liveState(id)
            shownStates[id] = displayedState(id)
        }
        let live = device.stateResolver?.resolve(liveStates) ?? liveStates[device.entityId] ?? "unavailable"
        let displayed = device.stateResolver?.resolve(shownStates) ?? shownStates[device.entityId] ?? live
        let hasOverride = ids.contains { overlay.hasOverride($0, live: liveState($0)) }
        return DeviceFacts(live: live, displayed: displayed, hasOverride: hasOverride)
    }

    // MARK: - Actions

    /// Runs a button. Returns the keyboard's target when the button opens the text prompt instead.
    @discardableResult
    public func press(_ button: MediaRemoteButton) -> String? {
        run(button.action)
    }

    /// Taps a device tile.
    public func tap(_ device: MediaRemoteDevice) {
        guard let action = device.action else { return }
        let override = device.stateResolver == nil ? nil : display(device).state
        run(action, entityId: device.entityId, stateOverride: override)
    }

    /// Taps an app tile.
    public func tap(_ app: MediaRemoteApp) { run(app.action) }

    /// Resolves and runs an action (web `runAction`).
    /// - Returns: The keyboard's target entity when the action is a text prompt (nothing is called).
    @discardableResult
    public func run(_ action: MediaRemoteAction, entityId: String? = nil, stateOverride: String? = nil) -> String? {
        switch action.resolve(entityId: entityId, stateOverride: stateOverride, displayedState: displayedState) {
        case let .textPrompt(target):
            return target
        case let .service(call, optimistic):
            perform(call, intents: optimistic)
            return nil
        }
    }

    /// Types `text` on an Android TV (web `submitTextPrompt`: `androidtv.adb_command`). Blank text sends nothing.
    public func sendText(_ text: String, to targetEntityId: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        perform(ServiceCall("androidtv", "adb_command", target: targetEntityId,
                            data: ["command": .string(MediaRemoteState.textInputCommand(text))]), intents: [])
    }

    /// Whether the last volume write failed and the failed face is still showing (4 s). A tile shows "Didn't Respond" for it.
    public var volumeWriteFailed: Bool { volumeOverlay.isFailed(config.volumeEntityId) }

    /// Sets the speaker volume, showing it at once (web `VolumeSlider`). A rejected call drops the shown level and shows the failed face.
    public func setVolume(percent: Int) {
        let percent = min(100, max(0, percent))
        let generation = volumeOverlay.commit(config.volumeEntityId, value: String(percent), live: String(liveVolumePercent), revertAfter: Self.volumeRevert)
        perform(ServiceCall("media_player", "volume_set", target: config.volumeEntityId,
                            data: ["volume_level": .number(Double(percent) / 100)]), intents: []) { [weak self] in
            guard let self else { return }
            volumeOverlay.fail(config.volumeEntityId, generation: generation)
        }
    }

    /// Calls a service with optimistic intents, undoing them if the call fails (web `runOptimisticServiceCommand`).
    func perform(_ call: ServiceCall, intents: [OptimisticIntent], onFailure: (@MainActor () -> Void)? = nil) {
        let commits: [(String, Int)] = intents.compactMap { intent in
            overlay.commit(intent.entityId, value: intent.value, live: liveState(intent.entityId), revertAfter: intent.revertAfter)
                .map { (intent.entityId, $0) }
        }
        let caller = caller
        let task = Task { @MainActor [weak self] in
            do {
                try await caller.call(call)
            } catch {
                for (entityId, generation) in commits { self?.overlay.fail(entityId, generation: generation) }
                onFailure?()
            }
        }
        inFlight.append(task)
        if !intents.isEmpty { updateHolds() }
    }

    /// Waits for every service call started so far. Tests use it to observe calls and failures.
    public func waitForCalls() async {
        let tasks = inFlight
        inFlight.removeAll()
        for task in tasks { await task.value }
    }

    // MARK: - Hue Sync

    /// A Hue Sync switch tile.
    public func hueToggle(_ entityId: String) -> ToggleDisplay {
        let live = liveState(entityId)
        let shown = displayedState(entityId) ?? "unavailable"
        return ToggleDisplay(isOn: shown == "on", isUnavailable: EntityState.isUnavailable(live), subtitle: MediaRemoteState.format(shown))
    }

    /// Flips a Hue Sync switch; `projections` take the same new value optimistically (power off also shows
    /// light sync off; light sync on also shows power on).
    public func toggleHue(_ entityId: String, offProjections: [String] = [], onProjections: [String] = []) {
        let isOn = hueToggle(entityId).isOn
        let next = isOn ? "off" : "on"
        let projections = isOn ? offProjections : onProjections
        let revert = MediaRemotes.MusicRoom.Revert.hueSync
        perform(ServiceCall("switch", isOn ? "turn_off" : "turn_on", target: entityId),
                intents: ([entityId] + projections).map { OptimisticIntent($0, next, revertAfter: revert) })
    }

    /// A Hue Sync select's options and shown value.
    public func hueSelect(_ entityId: String) -> SelectDisplay {
        let options = store.entity(entityId).state?.attributes["options"]?.array?.compactMap(\.string) ?? []
        return SelectDisplay(
            selected: displayedState(entityId) ?? "",
            options: options,
            isUnavailable: EntityState.isUnavailable(liveState(entityId)) || options.isEmpty
        )
    }

    /// Picks a Hue Sync option.
    /// - Parameters:
    ///   - allowSameValue: Send even when the option is already shown.
    ///   - onEntityIds: Entities shown `on` meanwhile (a mode choice starts syncing).
    ///   - resetEntityId: An entity whose optimistic value is dropped first.
    public func selectHue(_ entityId: String, option: String, allowSameValue: Bool = false, onEntityIds: [String] = [], resetEntityId: String? = nil) {
        let select = hueSelect(entityId)
        guard !select.isUnavailable, allowSameValue || option != select.selected else { return }
        if let resetEntityId { overlay.reset(resetEntityId) }
        let revert = MediaRemotes.MusicRoom.Revert.hueSync
        perform(ServiceCall("select", "select_option", target: entityId, data: ["option": .string(option)]),
                intents: [OptimisticIntent(entityId, option, revertAfter: revert)] + onEntityIds.map { OptimisticIntent($0, "on", revertAfter: revert) })
    }

    /// Whether the Sync Box is powered and syncing light.
    public func isHueSyncing(_ hue: HueSyncConfig) -> Bool {
        displayedState(hue.powerEntityId) == "on" && displayedState(hue.lightSyncEntityId) == "on"
    }

    /// Chooses a sync mode: starts syncing (power and light sync shown on) and drops any optimistic intensity.
    /// Re-sending the current mode is allowed while not syncing, since it starts syncing.
    public func selectSyncMode(_ hue: HueSyncConfig, mode: String) {
        selectHue(hue.syncModeEntityId, option: mode, allowSameValue: !isHueSyncing(hue),
                  onEntityIds: [hue.powerEntityId, hue.lightSyncEntityId], resetEntityId: hue.intensityEntityId)
    }

    /// The brightness slider.
    public func hueBrightness(_ entityId: String) -> BrightnessDisplay {
        let entity = store.entity(entityId).state
        let lower = entity?.attributes["min"]?.number ?? 1
        let upper = max(lower, entity?.attributes["max"]?.number ?? 100)
        let step = entity?.attributes["step"]?.number ?? 1
        func clamp(_ value: Double) -> Double { min(upper, max(lower, value)) }
        let live = clamp(entity.flatMap { Double($0.state) } ?? lower)
        let shown = clamp(displayedState(entityId).flatMap(Double.init) ?? live)
        let unavailable = EntityState.isUnavailable(entity?.state)
        return BrightnessDisplay(value: shown, range: lower...upper, step: step, isUnavailable: unavailable,
                                 unavailableText: unavailable ? MediaRemoteState.format(entity?.state) : nil)
    }

    /// Commits a brightness, skipping a value that is already shown.
    public func setHueBrightness(_ entityId: String, value: Double) {
        guard value != hueBrightness(entityId).value else { return }
        perform(ServiceCall("number", "set_value", target: entityId, data: ["value": .number(value)]),
                intents: [OptimisticIntent(entityId, MediaRemoteState.numberString(value), revertAfter: MediaRemotes.MusicRoom.Revert.hueSync)])
    }

    /// The HDMI input tiles: the select's options, or HDMI 1–4 when it reports none.
    public func hdmiInputs(_ hue: HueSyncConfig) -> [HdmiInputDisplay] {
        let select = hueSelect(hue.hdmiInputEntityId)
        let options = select.options.isEmpty ? hue.hdmiStatusEntityIds.indices.map { "HDMI \($0 + 1)" } : select.options
        return options.enumerated().map { index, option in
            let statusId = index < hue.hdmiStatusEntityIds.count ? hue.hdmiStatusEntityIds[index] : hue.hdmiStatusEntityIds.last ?? ""
            let state = liveState(statusId)
            let disconnected = EntityState.isUnavailable(state) || state == "unplugged"
            let selected = select.selected == option
            let status = MediaRemoteState.format(state)
            return HdmiInputDisplay(option: option, statusEntityId: statusId, isSelected: selected, isDisconnected: disconnected,
                                    isDisabled: select.isUnavailable || disconnected,
                                    subtitle: selected ? "Selected • \(status)" : status)
        }
    }

    // MARK: - Live changes

    /// Every entity whose live changes confirm optimistic values or move holds.
    var observedEntityIds: [String] {
        var ids = Set(overlay.trackedKeys)
        ids.insert(config.volumeEntityId)
        for device in config.devices where device.activeHold != nil {
            ids.formUnion(device.stateEntityIds ?? [device.entityId])
            ids.formUnion(device.activeHoldResetEntityIds)
        }
        return ids.sorted()
    }

    /// Feeds live values to the overlays and holds. Runs on every change to an observed entity.
    func liveDidChange() {
        for key in overlay.trackedKeys { overlay.liveChanged(key, to: liveState(key)) }
        volumeOverlay.liveChanged(config.volumeEntityId, to: String(liveVolumePercent))
        updateHolds()
    }

    /// Re-evaluates the active holds (after live changes and after optimistic commits).
    private func updateHolds() {
        for device in config.devices where device.activeHold != nil {
            let facts = deviceFacts(device)
            let resetKey = device.activeHoldResetEntityIds.map { liveState($0) ?? "unavailable" }.joined(separator: "|")
            holds.update(device.title, liveActive: MediaRemoteState.isActive(facts.live, activeStates: device.activeStates),
                         hasOverride: facts.hasOverride, hold: device.activeHold, resetKey: resetKey)
        }
    }

    private func observeLive() {
        let ids = observedEntityIds
        withObservationTracking {
            for id in ids { _ = store.entity(id).state }
        } onChange: { [weak self] in
            // onChange fires before the new value lands; read it on the next main-actor turn.
            Task { @MainActor [weak self] in
                self?.liveDidChange()
                self?.observeLive()
            }
        }
    }
}
