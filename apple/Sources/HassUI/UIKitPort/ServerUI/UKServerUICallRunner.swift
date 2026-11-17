#if os(iOS)
import HassCore
import Observation

// MARK: - Authored service calls

/// Runs authored `call-service` actions through the one connection and the shared optimistic path.
///
/// A call site (a control, a button, a row) owns one ``OptimisticActions``: the declared optimistic values show at once, the call
/// goes through `HassServiceCalling.callService`, and a rejected call rolls back exactly what it committed and shows the failed
/// face for four seconds. Optimistic values are feedback only; Home Assistant's own state replaces them.
///
/// Reads are observable, so a predicate or control that reads an entity through ``pendingState(_:)`` follows the optimistic value
/// and returns to the live one without a rebuild.
@MainActor
@Observable
final class UKServerUICallRunner {
    @ObservationIgnored private let context: UKContext
    private var models: [String: OptimisticActions] = [:]
    private var calls: [String: Int] = [:]
    /// Calls that were sent, by site, for tests and diagnostics.
    @ObservationIgnored private(set) var sentCount = 0
    @ObservationIgnored private var finishers: [Task<Void, Never>] = []

    init(context: UKContext) { self.context = context }

    /// The optimistic state a call has put on `entityID`, or `nil` while Home Assistant's own value shows.
    func pendingState(_ entityID: String) -> String? {
        for model in models.values where model.isPending(entityID) { return model.shown(entityID) }
        return nil
    }

    /// Whether a call from `node` (a control's own id, or a slot of it) is on its way or still showing an optimistic value.
    ///
    /// A node is never hidden while this is true, so a tap in flight cannot disappear under the finger.
    func isBusy(node: String) -> Bool {
        for (site, model) in models where site == node || site.hasPrefix(node + "#") {
            if (calls[site] ?? 0) > 0 || model.overlay.trackedKeys.contains(where: { model.isPending($0) }) { return true }
        }
        return calls.contains { ($0.key == node || $0.key.hasPrefix(node + "#")) && $0.value > 0 }
    }

    /// Whether a call from `node` is on the wire now, as opposed to showing an optimistic value after Home Assistant took it.
    func isSending(node: String) -> Bool {
        calls.contains { ($0.key == node || $0.key.hasPrefix(node + "#")) && $0.value > 0 }
    }

    /// Whether the last call from `node` failed and the failed face is still showing.
    func isFailed(node: String) -> Bool {
        models.contains { site, model in
            (site == node || site.hasPrefix(node + "#"))
                && (model.isFailed(site) || model.overlay.trackedKeys.contains { model.isFailed($0) })
        }
    }

    /// Sends one resolved call. Returns `false` when there is no connection to send it on.
    /// - Parameters:
    ///   - site: The call site (`"<node id>"` or `"<node id>#<slot>"`).
    ///   - entities: The entity each declared optimistic value belongs to.
    @discardableResult
    func run(site: String, call: ServerUICallService, resolved: ServerUICallService.Resolved,
             entities: [(entityID: String, value: ServerUICallService.Optimistic)]) -> Bool {
        guard let caller = context.caller else { return false }
        var seen = Set<String>()
        let unique = entities.filter { seen.insert($0.entityID).inserted }
        let keys = Set(unique.map(\.entityID))
        let model: OptimisticActions
        if let existing = models[site], Set(existing.overlay.trackedKeys) == keys {
            model = existing
        } else {
            model = OptimisticActions(store: context.store, rules: Dictionary(uniqueKeysWithValues: keys.map { ($0, .liveChange) }),
                                      caller: caller)
            models[site] = model
        }
        let intents = unique.map {
            OptimisticIntent($0.entityID, $0.value.value, revertAfter: .seconds($0.value.revertAfterSeconds),
                             failsOnTimeout: $0.value.failsOnTimeout)
        }
        calls[site, default: 0] += 1
        sentCount += 1
        let task = model.perform(resolved.domain, resolved.service, data: resolved.data.mapValues(\.foundationValue),
                                 showing: intents, failing: site)
        finishers.append(Task { [weak self] in
            await task.value
            self?.calls[site, default: 1] -= 1
        })
        if finishers.count > 64 { finishers.removeFirst(finishers.count - 63) }
        return true
    }

    /// Waits for every call started so far (tests).
    func waitForCalls() async {
        let tasks = finishers
        finishers.removeAll()
        for task in tasks { await task.value }
    }
}
#endif
