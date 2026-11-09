import Foundation
import Observation

/// Shared plumbing for the room device controllers (bathroom fan, air purifier, humidifier, grill): live reads
/// from ``EntityStore``, an ``OptimisticOverlay`` over them, and service calls that undo their optimistic values
/// when Home Assistant rejects them (web `useOptimisticState` + `callService`).
@MainActor
@Observable
public final class RoomDeviceCommands {
    /// Live state.
    public let store: EntityStore
    /// Optimistic values by entity id.
    public let overlay: OptimisticOverlay

    @ObservationIgnored private let caller: any HassServiceCalling
    @ObservationIgnored private let liveValue: @MainActor (String) -> String?
    @ObservationIgnored private var inFlight: [Task<Void, Never>] = []

    /// Creates the plumbing.
    /// - Parameters:
    ///   - store: Live state.
    ///   - caller: The connection in the app, a recorder in tests and the gallery.
    ///   - rules: Each optimistic entity and when its value clears.
    ///   - scheduler: Runs revert timers.
    ///   - liveValue: The live value the overlay compares against; defaults to the raw state. The bathroom fan
    ///     passes its on/off/unavailable flag so `unknown` and `unavailable` compare equal, as on the web.
    public init(store: EntityStore, caller: any HassServiceCalling, rules: [String: OptimisticOverlay.ClearRule],
                scheduler: any RevertScheduler, liveValue: (@MainActor (String) -> String?)? = nil) {
        self.store = store
        self.caller = caller
        overlay = OptimisticOverlay(rules: rules, scheduler: scheduler)
        self.liveValue = liveValue ?? { [store] in store.entity($0).state?.state }
        for key in overlay.trackedKeys { overlay.liveChanged(key, to: self.liveValue(key)) }
        observeLive()
    }

    // MARK: - Reading

    /// The entity's state, observed.
    public func entity(_ entityId: String) -> EntityState? { store.entity(entityId).state }

    /// The value the overlay compares against (raw state unless a mapping was given).
    public func live(_ entityId: String) -> String? { liveValue(entityId) }

    /// Whether the last command for `entityId` failed and its failed face is still showing (4 s).
    public func isFailed(_ entityId: String) -> Bool { overlay.isFailed(entityId) }

    /// The shown value: optimistic if pending, else live.
    public func displayed(_ entityId: String) -> String? { overlay.displayed(entityId, live: live(entityId)) }

    // MARK: - Acting

    /// Shows `intents` at once and calls `call`; a failed call drops exactly those values.
    public func perform(_ call: ServiceCall, intents: [OptimisticIntent] = []) {
        let commits: [(String, Int)] = intents.compactMap { intent in
            overlay.commit(intent.entityId, value: intent.value, live: live(intent.entityId), revertAfter: intent.revertAfter)
                .map { (intent.entityId, $0) }
        }
        let caller = caller
        inFlight.append(Task { @MainActor [weak self] in
            do {
                try await caller.call(call)
            } catch {
                for (entityId, generation) in commits { self?.overlay.fail(entityId, generation: generation) }
            }
        })
    }

    /// Waits for every call started so far. Tests use it to observe calls and failures.
    public func waitForCalls() async {
        let tasks = inFlight
        inFlight.removeAll()
        for task in tasks { await task.value }
    }

    // MARK: - Live changes

    private func observeLive() {
        let ids = overlay.trackedKeys
        withObservationTracking {
            for id in ids { _ = store.entity(id).state }
        } onChange: { [weak self] in
            // onChange fires before the new value lands; read it on the next main-actor turn.
            Task { @MainActor [weak self] in
                guard let self else { return }
                for key in self.overlay.trackedKeys { self.overlay.liveChanged(key, to: self.live(key)) }
                self.observeLive()
            }
        }
    }
}

// MARK: - Shared state helpers

/// State parsing the device sheets share (web `entityState.ts`).
public enum DeviceState {
    /// `on` / `off` / `unavailable` (web `binaryFlag`).
    public static func binaryFlag(_ state: String?) -> String {
        EntityState.isUnavailable(state) ? "unavailable" : state == "on" ? "on" : "off"
    }

    /// A number parsed from the state.
    public static func number(_ entity: EntityState?) -> Double? {
        guard let state = entity?.state, let value = Double(state), value.isFinite else { return nil }
        return value
    }

    /// The compact state text the web shows under a card title (web `formatCompactEntityState`).
    public static func compact(_ entity: EntityState?, fallback: String = "Unavailable") -> String {
        guard let entity else { return fallback }
        if entity.state == "unavailable" { return "Unavailable" }
        if entity.entityId.hasPrefix("binary_sensor.") { return entity.state == "on" ? "Active" : "Clear" }
        if entity.entityId.hasPrefix("sensor.") { return entity.state }
        return StateText.titleCase(entity.state)
    }
}
