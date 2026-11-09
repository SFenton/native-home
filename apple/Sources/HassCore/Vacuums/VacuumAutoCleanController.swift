import Foundation
import Observation

/// The page's Auto-Clean tiles (web `VacuumAutoCleanControls.tsx`): each tile turns a vacuum's automatic
/// cleaning on or off, shows the new value at once and keeps it until Home Assistant confirms or 8 s pass.
@MainActor
@Observable
public final class VacuumAutoCleanController {
    /// One tile's state.
    public struct Display: Equatable, Sendable {
        public var isEnabled: Bool
        public var isUnavailable: Bool
        /// The last flip failed (the call threw, or Home Assistant did not confirm in 8 s) and the message still shows.
        public var isFailed = false
        /// Enabled, Paused or Unavailable, or "Didn't Respond" for 4 s after a failed flip.
        public var subtitle: String
    }

    public let store: EntityStore
    let overlay: OptimisticOverlay
    @ObservationIgnored private let caller: any HassServiceCalling
    @ObservationIgnored private var inFlight: [Task<Void, Never>] = []

    /// Creates the controller.
    public init(store: EntityStore, caller: any HassServiceCalling, scheduler: any RevertScheduler = TaskRevertScheduler()) {
        self.store = store
        self.caller = caller
        overlay = OptimisticOverlay(rules: Dictionary(Vacuums.autoCleanControls.map { ($0.entityId, .confirmation) }, uniquingKeysWith: { first, _ in first }),
                                    scheduler: scheduler)
        observeLive()
    }

    /// A tile's shown state.
    public func display(_ control: Vacuums.AutoCleanControl) -> Display {
        let live = store.entity(control.entityId).state?.state
        guard let live, !VacuumStatusResolver.isUnavailable(live) else {
            return Display(isEnabled: false, isUnavailable: true, subtitle: "Unavailable")
        }
        let enabled = control.isEnabled(state: overlay.displayed(control.entityId, live: live) ?? live)
        let failed = overlay.isFailed(control.entityId)
        return Display(isEnabled: enabled, isUnavailable: false, isFailed: failed,
                       subtitle: failed ? "Didn't Respond" : enabled ? "Enabled" : "Paused")
    }

    /// Flips a tile: the pause switch turns off to enable, automations turn on.
    public func toggle(_ control: Vacuums.AutoCleanControl) {
        let current = display(control)
        guard !current.isUnavailable else { return }
        let enable = !current.isEnabled
        let on = control.kind == .pause ? !enable : enable
        let live = store.entity(control.entityId).state?.state
        let generation = overlay.commit(control.entityId, value: on ? "on" : "off", live: live, revertAfter: VacuumController.optimisticRevert,
                                       failsOnTimeout: true)
        let call = ServiceCall(control.domain, on ? "turn_on" : "turn_off", target: control.entityId)
        let caller = caller
        inFlight.append(Task { @MainActor [weak self] in
            do { try await caller.call(call) } catch { self?.overlay.fail(control.entityId, generation: generation) }
        })
    }

    /// Waits for every service call so far (tests).
    public func waitForCalls() async {
        let tasks = inFlight
        inFlight.removeAll()
        for task in tasks { await task.value }
    }

    private func observeLive() {
        let ids = overlay.trackedKeys
        withObservationTracking {
            for id in ids { _ = store.entity(id).state }
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                for id in ids { self.overlay.liveChanged(id, to: self.store.entity(id).state?.state) }
                self.observeLive()
            }
        }
    }
}
