import Foundation
import Observation

/// State and commands for the household Settings pages (`.agents/pages/settings/household.md`).
///
/// Toggles send an explicit `turn_on` / `turn_off` chosen from the shown state rather than the web's
/// `homeassistant.toggle`, so a tap always means what the tile showed (and matches the lights rule in
/// `.agents/patterns/entity-tile.md`). Toggles and presence modes show their new value at once and give way
/// to Home Assistant on confirmation, failure, or after ``revertAfter`` (web `useOptimisticState`).
@MainActor
@Observable
public final class HouseholdSettingsController {
    /// Immutable targets for a controller instance. Composition callers supply these explicitly;
    /// the legacy feature can continue to use its configured defaults.
    public struct Targets: Equatable, Sendable {
        public let toggleEntityIds: [String]
        public let presenceTitles: [String: String]
        public let relayEntityId: String?
        public let guestEntityId: String?
        public let powerRecoveryEntityId: String?

        public init(toggleEntityIds: [String], presenceTitles: [String: String],
                    relayEntityId: String? = nil, guestEntityId: String? = nil,
                    powerRecoveryEntityId: String? = nil) {
            self.toggleEntityIds = toggleEntityIds
            self.presenceTitles = presenceTitles
            self.relayEntityId = relayEntityId
            self.guestEntityId = guestEntityId
            self.powerRecoveryEntityId = powerRecoveryEntityId
        }
    }

    // MARK: - Displays

    /// How a toggle tile shows.
    public struct ToggleDisplay: Equatable, Sendable {
        public var isOn: Bool
        public var isUnavailable: Bool
        /// The last flip was rejected: the tile shows its failed face for 4 s.
        public var isFailed = false
        /// The state as text, e.g. `On`, or "Didn't Respond" while ``isFailed``.
        public var subtitle: String
    }

    /// How a read-only tile shows.
    public struct ReadOnlyDisplay: Equatable, Sendable {
        /// The state as text, or `nil` when the tile hides it.
        public var subtitle: String?
        public var isActive: Bool
        public var isUnavailable: Bool
    }

    // MARK: - Properties

    /// Live state.
    public let store: EntityStore
    /// Optimistic toggle states, and presence modes under ``presenceKey(_:)``.
    public let overlay: OptimisticOverlay

    /// Where service calls go; Car Doors runs its lock call through `OptimisticActions` on the same caller.
    @ObservationIgnored public let caller: any HassServiceCalling
    /// Told when a command fails, with a sentence to show or speak (the view announces it). A failed tap otherwise only
    /// reverts after ``revertAfter`` with no word to say why.
    @ObservationIgnored public var onFailure: (@MainActor (String) -> Void)?
    @ObservationIgnored private var inFlight: [Task<Void, Never>] = []
    /// Targets are fixed for the lifetime of the controller.
    public let targets: Targets
    private var executing: [String: Int] = [:]
    @ObservationIgnored private let toggleIds: [String]
    @ObservationIgnored private let presenceIds: [String]

    /// How long an optimistic value waits for Home Assistant (web `DEFAULT_OPTIMISTIC_REVERT_MS`).
    public static let revertAfter: Duration = .seconds(2)

    // MARK: - Init

    /// Creates a controller.
    /// - Parameters:
    ///   - store: Live state.
    ///   - caller: Where service calls go: the connection in the app, a recorder in tests and the gallery.
    ///   - scheduler: Runs revert timers.
    ///   - targets: The entities the controller drives, built from the document's controls by the caller.
    public init(store: EntityStore, caller: any HassServiceCalling, scheduler: any RevertScheduler = TaskRevertScheduler(),
                targets: Targets) {
        self.store = store
        self.caller = caller
        self.targets = targets
        toggleIds = targets.toggleEntityIds
        presenceIds = targets.presenceTitles.keys.sorted()
        var rules: [String: OptimisticOverlay.ClearRule] = [:]
        for id in toggleIds { rules[id] = .confirmation }
        for id in presenceIds { rules[Self.presenceKey(id)] = .confirmation }
        overlay = OptimisticOverlay(rules: rules, scheduler: scheduler)
        liveDidChange()
        observeLive()
    }

    /// The overlay key for a room's presence mode.
    public static func presenceKey(_ entityId: String) -> String { "presence:" + entityId }

    // MARK: - Toggles

    /// How a toggle tile shows.
    public func toggle(_ entityId: String) -> ToggleDisplay {
        let live = store.entity(entityId).state
        let shown = overlay.displayed(entityId, live: live?.state)
        let unavailable = live == nil || live?.isUnavailable == true
        let failed = !unavailable && overlay.isFailed(entityId)
        return ToggleDisplay(
            isOn: !unavailable && shown == "on",
            isUnavailable: unavailable,
            isFailed: failed,
            subtitle: unavailable ? "Unavailable" : failed ? "Didn't Respond" : Self.format(shown)
        )
    }

    /// Turns the entity to the opposite of what it shows. Does nothing while it is unavailable.
    public func flip(_ entityId: String, title: String? = nil) {
        let shown = toggle(entityId)
        guard !shown.isUnavailable else { return }
        let next = shown.isOn ? "off" : "on"
        let domain = String(entityId.prefix { $0 != "." })
        let serviceDomain = ["input_boolean", "switch"].contains(domain) ? domain : "homeassistant"
        perform(ServiceCall(serviceDomain, shown.isOn ? "turn_off" : "turn_on", target: entityId),
                key: entityId, value: next, live: store.entity(entityId).state?.state, failure: Self.failureText(title: title))
    }

    /// The sentence spoken when a command for `entityId` fails.
    public static func failureText(title: String?) -> String {
        "Couldn't change \(title ?? "that setting"). It shows its current state."
    }

    /// Relay Control Mode and Guest Room guest mode are both on (web `showRelayGuestModeWarning`, live state).
    public var showsRelayGuestModeWarning: Bool {
        guard let relay = targets.relayEntityId, let guest = targets.guestEntityId else { return false }
        return store.entity(relay).state?.state == "on" && store.entity(guest).state?.state == "on"
    }

    // MARK: - Presence modes

    /// A room's shown presence mode: optimistic if pending, else live.
    public func presence(_ entityId: String) -> PresenceOverrideState {
        let live = PresenceOverrideState(entity: store.entity(entityId).state)
        guard live != .unavailable else { return .unavailable }
        return overlay.displayed(Self.presenceKey(entityId), live: live.rawValue).flatMap(PresenceOverrideState.init(rawValue:)) ?? live
    }

    /// Whether the last change to a room's presence mode was rejected and its message is still showing.
    public func presenceFailed(_ entityId: String) -> Bool { overlay.isFailed(Self.presenceKey(entityId)) }

    /// Whether the Power Recovery automation failed to run and its tile still shows the failed face.
    public var powerRecoveryFailed: Bool {
        targets.powerRecoveryEntityId.map { overlay.isFailed($0) } ?? false
    }

    /// Sets a room's presence mode. Does nothing while the room is unavailable.
    public func setPresence(_ entityId: String, to mode: PresenceOverrideState) {
        let live = PresenceOverrideState(entity: store.entity(entityId).state)
        guard live != .unavailable, let call = mode.command(for: entityId) else { return }
        perform(call, key: Self.presenceKey(entityId), value: mode.rawValue, live: live.rawValue,
                failure: Self.failureText(title: targets.presenceTitles[entityId]))
    }

    // MARK: - Commands and read-only tiles

    /// Runs the living room power recovery automation (`automation.trigger`).
    public func triggerPowerRecovery() {
        guard let id = targets.powerRecoveryEntityId, !id.isEmpty else {
            onFailure?(Self.failureText(title: nil))
            return
        }
        perform(ServiceCall("automation", "trigger", target: id), key: id, value: nil, live: nil)
    }

    /// How a read-only tile shows (web `EntityActionCard` without an action).
    public func readOnly(_ tile: HouseholdSettingsConfig.Tile) -> ReadOnlyDisplay {
        let entity = store.entity(tile.entityId).state
        let unavailable = entity == nil || entity?.isUnavailable == true
        return ReadOnlyDisplay(
            subtitle: tile.showsState ? Self.compactState(entity) : nil,
            isActive: entity.map { Self.webActiveStates.contains($0.state) } ?? false,
            isUnavailable: unavailable
        )
    }

    /// States the web counts as active (`entityState.ts` `isActiveState`).
    static let webActiveStates: Set<String> = ["on", "open", "playing", "recording", "home", "heat", "cool"]

    // MARK: - Formatting

    /// A state as title-case words: `on` → `On`, `armed_away` → `Armed Away` (web `titleCaseState`).
    public static func format(_ state: String?) -> String { StateText.titleCase(state) }

    /// Web `formatCompactEntityState`: sensors show their raw value, everything else title case.
    public static func compactState(_ entity: EntityState?) -> String {
        guard let entity, entity.state != "unavailable" else { return "Unavailable" }
        if entity.domain == "sensor" { return entity.state }
        return format(entity.state)
    }

    // MARK: - Calls

    /// A service request is outstanding even if its optimistic display has already reverted.
    /// Publication guards must also retain controls while confirmation UI is open.
    public func isExecuting(_ key: String) -> Bool { (executing[key] ?? 0) > 0 }

    private func perform(_ call: ServiceCall, key: String?, value: String?, live: String?, failure: String? = nil) {
        if let key { overlay.clearFailure(key) }
        let generation = key.flatMap { key in
            value.flatMap { overlay.commit(key, value: $0, live: live, revertAfter: Self.revertAfter) }
        }
        if let key { executing[key, default: 0] += 1 }
        let caller = caller
        let task = Task { @MainActor [weak self] in
            defer {
                if let key, let self {
                    let remaining = (self.executing[key] ?? 1) - 1
                    self.executing[key] = remaining > 0 ? remaining : nil
                }
            }
            do {
                try await caller.call(call)
            } catch {
                // No generation: a command with no optimistic value (Power Recovery) still shows the failed face.
                if let key { self?.overlay.fail(key, generation: generation) }
                if let failure { self?.onFailure?(failure) }
            }
        }
        inFlight.append(task)
    }

    /// Waits for every service call started so far. Tests use it to observe calls and failures.
    public func waitForCalls() async {
        let tasks = inFlight
        inFlight.removeAll()
        for task in tasks { await task.value }
    }

    // MARK: - Live observation

    private func liveDidChange() {
        for id in toggleIds { overlay.liveChanged(id, to: store.entity(id).state?.state) }
        for id in presenceIds {
            overlay.liveChanged(Self.presenceKey(id), to: PresenceOverrideState(entity: store.entity(id).state).rawValue)
        }
    }

    private func observeLive() {
        let ids = toggleIds + presenceIds
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
