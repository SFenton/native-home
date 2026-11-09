import Foundation
import Observation

/// The Climate page's actions and optimistic state. Every toggle, select and hub picker shows its new value at
/// once and gives way to Home Assistant's state when it arrives, fails or the revert time passes (web
/// `useOptimisticState`, 2 s). Calls go through one ``HassServiceCalling``: the connection in the app, a recorder
/// in tests and the gallery.
@MainActor
@Observable
public final class ClimateController {
    /// Live state.
    public let store: EntityStore
    /// Pending optimistic values, keyed by entity id (hub mode and fan mode use ``hubModeKey`` / ``hubFanKey``).
    public let overlay: OptimisticOverlay

    /// Where calls go; the room dials commit through it too.
    @ObservationIgnored public let caller: any HassServiceCalling
    @ObservationIgnored private var inFlight: [Task<Void, Never>] = []

    /// How long an optimistic value waits for Home Assistant (web `DEFAULT_OPTIMISTIC_REVERT_MS`).
    public static let revert: Duration = .seconds(2)
    /// Overlay key for the hub's HVAC mode.
    public nonisolated static var hubModeKey: String { "\(ClimateConfig.hubEntityId)#hvac_mode" }
    /// Overlay key for the hub's fan mode.
    public nonisolated static var hubFanKey: String { "\(ClimateConfig.hubEntityId)#fan_mode" }

    /// Creates a controller.
    public init(store: EntityStore, caller: any HassServiceCalling, scheduler: any RevertScheduler = TaskRevertScheduler()) {
        self.store = store
        self.caller = caller
        var rules: [String: OptimisticOverlay.ClearRule] = [:]
        for id in ClimateConfig.toggleEntityIds + [ClimateConfig.ecoCriticalEntityId, ClimateConfig.ecoAwayEntityId, Self.hubModeKey, Self.hubFanKey] {
            rules[id] = .confirmation
        }
        overlay = OptimisticOverlay(rules: rules, scheduler: scheduler)
        liveDidChange()
        observeLive()
    }

    // MARK: - Reading

    /// An entity's live state, observed.
    public func entity(_ entityId: String) -> EntityState? { store.entity(entityId).state }

    /// Lookup for ``ClimateLogic``.
    public var lookup: EntityLookup { { [store] in store.entity($0).state } }

    /// The live value an overlay key tracks.
    public func liveValue(_ key: String) -> String? {
        switch key {
        case Self.hubModeKey: entity(ClimateConfig.hubEntityId)?.state
        case Self.hubFanKey: entity(ClimateConfig.hubEntityId)?.attributes["fan_mode"]?.string
        default: entity(key)?.state
        }
    }

    /// The shown value: pending, else live.
    public func shown(_ key: String) -> String? { overlay.displayed(key, live: liveValue(key)) }

    /// The entity is missing or unavailable, so its control is disabled.
    public func isUnavailable(_ entityId: String) -> Bool { entity(entityId).map(\.isUnavailable) ?? true }

    /// Whether a switch or input_boolean shows on.
    public func isOn(_ entityId: String) -> Bool { shown(entityId) == "on" }

    /// The tracking summary with optimistic switch states.
    public var trackingSummary: ClimateLogic.TrackingSummary { ClimateLogic.trackingSummary(lookup, state: shown) }

    // MARK: - Actions

    /// Flips a switch or input_boolean with `homeassistant.toggle` (web `ThermostatToggleSetting`, `ThermostatCheckbox`).
    public func toggle(_ entityId: String) {
        guard !isUnavailable(entityId) else { return }
        let next = isOn(entityId) ? "off" : "on"
        perform(ServiceCall("homeassistant", "toggle", target: entityId), key: entityId, value: next)
    }

    /// Sets a switch explicitly (Predictive Comfort's tile and power button use `switch.turn_on` / `turn_off`).
    public func setSwitch(_ entityId: String, on: Bool) {
        guard !isUnavailable(entityId), isOn(entityId) != on else { return }
        perform(ServiceCall("switch", on ? "turn_on" : "turn_off", target: entityId), key: entityId, value: on ? "on" : "off")
    }

    /// Chooses a select option (`select.select_option`); choosing the shown option does nothing.
    public func select(_ entityId: String, option: String) {
        guard shown(entityId) != option else { return }
        perform(ServiceCall("select", "select_option", target: entityId, data: ["option": .string(option)]), key: entityId, value: option)
    }

    /// Sets the hub's HVAC mode (`climate.set_hvac_mode`).
    public func setHubMode(_ mode: String) {
        guard shown(Self.hubModeKey) != mode else { return }
        perform(ServiceCall("climate", "set_hvac_mode", target: ClimateConfig.hubEntityId, data: ["hvac_mode": .string(mode)]),
                key: Self.hubModeKey, value: mode)
    }

    /// Sets the hub's fan mode (`climate.set_fan_mode`).
    public func setHubFan(_ mode: String) {
        guard shown(Self.hubFanKey) != mode else { return }
        perform(ServiceCall("climate", "set_fan_mode", target: ClimateConfig.hubEntityId, data: ["fan_mode": .string(mode)]),
                key: Self.hubFanKey, value: mode)
    }

    /// Waits for every call started so far (tests).
    public func waitForCalls() async {
        let tasks = inFlight
        inFlight.removeAll()
        for task in tasks { await task.value }
    }

    private func perform(_ call: ServiceCall, key: String, value: String) {
        let generation = overlay.commit(key, value: value, live: liveValue(key), revertAfter: Self.revert)
        let caller = caller
        inFlight.append(Task { @MainActor [weak self] in
            do {
                try await caller.call(call)
            } catch {
                self?.overlay.fail(key, generation: generation)
            }
        })
    }

    // MARK: - Live updates

    func liveDidChange() {
        for key in overlay.trackedKeys { overlay.liveChanged(key, to: liveValue(key)) }
    }

    private func observeLive() {
        withObservationTracking {
            for key in overlay.trackedKeys { _ = liveValue(key) }
        } onChange: { [weak self] in
            // onChange fires before the new value lands; read it on the next main-actor turn.
            Task { @MainActor [weak self] in
                self?.liveDidChange()
                self?.observeLive()
            }
        }
    }
}
