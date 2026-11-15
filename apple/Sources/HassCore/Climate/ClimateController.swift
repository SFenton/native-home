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
    @ObservationIgnored private let configuredEntityIds: Set<String>?
    /// Actual service-call lifetime, independent of the two-second optimistic timeout.
    public private(set) var pendingCommandCount = 0

    /// How long an optimistic value waits for Home Assistant (web `DEFAULT_OPTIMISTIC_REVERT_MS`).
    public static let revert: Duration = .seconds(2)
    /// Overlay key for the hub's HVAC mode.
    public nonisolated static var hubModeKey: String { "\(ClimateConfig.hubEntityId)#hvac_mode" }
    /// Overlay key for the hub's fan mode.
    public nonisolated static var hubFanKey: String { "\(ClimateConfig.hubEntityId)#fan_mode" }

    /// Creates a controller.
    public init(store: EntityStore, caller: any HassServiceCalling, scheduler: any RevertScheduler = TaskRevertScheduler(),
                configuredEntityIds: [String]? = nil) {
        self.store = store
        self.caller = caller
        self.configuredEntityIds = configuredEntityIds.map(Set.init)
        var rules: [String: OptimisticOverlay.ClearRule] = [:]
        let keys = configuredEntityIds.map { ids in ids.flatMap { [$0, "\($0)#hvac_mode", "\($0)#fan_mode", "\($0)#preset_mode"] } }
            ?? (ClimateConfig.toggleEntityIds + [ClimateConfig.ecoCriticalEntityId, ClimateConfig.ecoAwayEntityId, Self.hubModeKey, Self.hubFanKey])
        for id in keys {
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
        if let separator = key.firstIndex(of: "#") {
            let id = String(key[..<separator]), attribute = String(key[key.index(after: separator)...])
            return attribute == "hvac_mode" ? entity(id)?.state : entity(id)?.attributes[attribute]?.string
        }
        return switch key {
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

    /// Executes an injected-target command, revalidating HA availability and supported choices at dispatch.
    /// The caller awaits the real command; publication guards must not use optimistic timeout as completion.
    public func execute(_ intent: ClimateConfiguredIntent) async throws {
        let call: ServiceCall
        let key: String?
        let value: String?
        func check(_ ids: [String], domains: [String]) throws {
            guard !ids.isEmpty, Set(ids).count == ids.count,
                  ids.allSatisfy({ id in
                      (configuredEntityIds?.contains(id) ?? false) &&
                      domains.contains(String(id.prefix(while: { $0 != "." }))) && !isUnavailable(id)
                  }) else { throw ClimateConfiguredError.unavailable }
        }
        func choice(_ id: String, _ option: String, attribute: String, domain: String) throws {
            try check([id], domains: [domain])
            guard entity(id)?.attributes[attribute]?.array?.contains(.string(option)) == true else {
                throw ClimateConfiguredError.unsupportedOption
            }
        }
        switch intent {
        case .toggle(let id):
            try check([id], domains: ["switch", "input_boolean"])
            key = id; value = isOn(id) ? "off" : "on"
            call = ServiceCall("homeassistant", "toggle", target: id)
        case .setSwitch(let id, let on):
            try check([id], domains: ["switch"])
            key = id; value = on ? "on" : "off"
            call = ServiceCall("switch", on ? "turn_on" : "turn_off", target: id)
        case .select(let id, let option):
            try choice(id, option, attribute: "options", domain: "select")
            key = id; value = option
            call = ServiceCall("select", "select_option", target: id, data: ["option": .string(option)])
        case .mode(let id, let option), .fan(let id, let option), .preset(let id, let option):
            let attribute: String
            switch intent {
            case .mode: attribute = "hvac_mode"
            case .fan: attribute = "fan_mode"
            default: attribute = "preset_mode"
            }
            let supported = attribute == "hvac_mode" ? "hvac_modes" : attribute + "s"
            try choice(id, option, attribute: supported, domain: "climate")
            key = "\(id)#\(attribute)"; value = option
            call = ServiceCall("climate", "set_\(attribute)", target: id, data: [attribute: .string(option)])
        case .temperature(let ids, let values, let unit):
            try check(ids, domains: ["climate"])
            let keys = Set(values.keys)
            guard ["°C", "°F"].contains(unit),
                  keys == ["temperature"] || keys == ["target_temp_low", "target_temp_high"],
                  values.values.allSatisfy(\.isFinite),
                  (values["target_temp_low"] ?? 0) <= (values["target_temp_high"] ?? 0) else {
                throw ClimateConfiguredError.invalidIntent
            }
            for id in ids {
                let attributes = entity(id)?.attributes ?? [:]
                if let reported = attributes["temperature_unit"]?.string ?? attributes["unit_of_measurement"]?.string,
                   reported != unit { throw ClimateConfiguredError.invalidIntent }
                if let min = attributes["min_temp"]?.finiteNumber, values.values.contains(where: { $0 < min }) {
                    throw ClimateConfiguredError.invalidIntent
                }
                if let max = attributes["max_temp"]?.finiteNumber, values.values.contains(where: { $0 > max }) {
                    throw ClimateConfiguredError.invalidIntent
                }
            }
            var data = values.mapValues(JSONValue.number)
            data["entity_id"] = ids.count == 1 ? .string(ids[0]) : .array(ids.map(JSONValue.string))
            key = nil; value = nil
            call = ServiceCall("climate", "set_temperature", data: data)
        }
        if let key, let value, shown(key) == value { return }
        let generation = key.flatMap { key in value.flatMap { overlay.commit(key, value: $0, live: liveValue(key), revertAfter: Self.revert) } }
        pendingCommandCount += 1
        defer { pendingCommandCount -= 1 }
        do { try await caller.call(call) }
        catch {
            if let key { overlay.fail(key, generation: generation) }
            throw error
        }
    }

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
