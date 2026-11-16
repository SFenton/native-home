#if os(iOS)
import Foundation
import HassCore
import Observation

// MARK: - Canonical configured alarm

/// One literal panel, with separate confirmation and network lifetimes. Tracked alarm calls have
/// no optimistic overlay, so `OptimisticActions.isPending` cannot protect their target.
@MainActor
@Observable
final class UKServerUIAlarmSource {
    struct Ticket: Equatable {
        let id: UUID
        let entityID: String
        let spec: TileActionSpec
        let modeState: String?
        let liveState: String?
    }

    struct Projection {
        let spec: TileActionSpec
        let state: String?
        let failed: Bool
    }

    let entityID: String
    @ObservationIgnored private let context: UKContext
    private(set) var confirmation: Ticket?
    private(set) var network: Ticket?
    private(set) var actions: OptimisticActions?
    @ObservationIgnored private(set) var completion: Task<Void, Never>?

    init(entityID: String, context: UKContext) {
        self.entityID = entityID
        self.context = context
    }

    var hasPendingIntent: Bool { confirmation != nil || network != nil || actions?.isPending(entityID) == true }
    var shownState: String? { actions?.shown(entityID) ?? context.store.entity(entityID).state?.state }
    var canSend: Bool {
        !context.valuesPending && context.caller != nil
            && context.connection.map({ SecurityScreen.canSend($0.status) }) != false && !ScreenshotPrivacy.isRedacting
    }

    func modeSpec(_ state: String, confirmation: TileActionSpec.Confirmation) -> TileActionSpec? {
        let live = context.store.entity(entityID).state
        guard var spec = ServerUISecurity.alarmMode(entityID: entityID, live: live, selected: state, confirmation: confirmation) else { return nil }
        if !canSend {
            spec = spec.with(phase: .unavailable)
        }
        if network != nil { spec = spec.with(phase: .inFlight) }
        return spec
    }

    func reserveMode(_ state: String, expected: TileActionSpec, confirmation: TileActionSpec.Confirmation) throws -> Ticket {
        guard let spec = modeSpec(state, confirmation: confirmation), self.confirmation == nil, network == nil,
              shownState != state, spec.phase == .ready, spec == expected else { throw unavailable() }
        let ticket = Ticket(id: UUID(), entityID: entityID, spec: spec, modeState: state,
                            liveState: context.store.entity(entityID).state?.state)
        self.confirmation = ticket
        return ticket
    }

    private var providerSpec: TileActionSpec {
        var spec = StateStyle.alarm.spec(for: context.store.entity(entityID).state, entityId: entityID)
            ?? TileActionSpec(id: StateStyle.alarm.actionId, verb: "Arm Home", symbol: "shield.lefthalf.filled", phase: .unavailable, feedback: .tracked)
        if !canSend {
            spec = spec.with(phase: .unavailable)
        }
        return spec
    }

    var projection: Projection {
        var spec = providerSpec
        if network != nil { spec = spec.with(phase: .inFlight) }
        let failed = actions?.isFailed(entityID) == true
        spec.isError = failed
        return Projection(spec: spec, state: context.store.entity(entityID).state?.state, failed: failed)
    }

    /// Captures the exact provider command before asking. No source or component may change it.
    func reserve(expected: TileActionSpec? = nil) throws -> Ticket {
        let spec = providerSpec
        var expected = expected
        expected?.isError = false
        guard !hasPendingIntent, spec.phase == .ready, spec.call != nil,
              expected == nil || expected == spec else { throw unavailable() }
        let ticket = Ticket(id: UUID(), entityID: entityID, spec: spec, modeState: nil,
                            liveState: context.store.entity(entityID).state?.state)
        confirmation = ticket
        return ticket
    }

    /// Cancel has no service side effect and never clears another interaction's reservation.
    func cancel(_ ticket: Ticket) {
        if confirmation == ticket { confirmation = nil }
    }

    /// Revalidates after confirmation, then retains the target through actual call completion.
    func execute(_ ticket: Ticket) throws {
        guard confirmation == ticket else { throw unavailable() }
        defer { confirmation = nil }
        let current: TileActionSpec?
        if let mode = ticket.modeState {
            current = modeSpec(mode, confirmation: ticket.spec.confirmation ?? StateStyle.alarmDisarmConfirmation)
        } else { current = providerSpec }
        guard ticket.entityID == entityID, current == ticket.spec,
              ticket.liveState == context.store.entity(entityID).state?.state,
              let call = ticket.spec.call, let caller = context.caller else { throw unavailable() }
        let actions = actions ?? OptimisticActions(store: context.store, rules: [entityID: .liveChange], caller: caller)
        self.actions = actions
        network = ticket
        let task = actions.perform(call, showing: ticket.spec.optimistic + ticket.spec.tracking, failing: entityID)
        // Strong retention is intentional: removing a page cannot abandon command tracking/feedback.
        completion = Task { @MainActor in
            await task.value
            if self.network == ticket { self.network = nil }
            self.completion = nil
        }
    }

    private func unavailable() -> UKServerUIRendererError {
        UKServerUIRendererError(code: .unavailableSource, pointer: "/document/dataSources")
    }
}
#endif
