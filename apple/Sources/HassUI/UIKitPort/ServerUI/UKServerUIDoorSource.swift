#if os(iOS)
import Foundation
import HassCore
import Observation

// MARK: - Configured lock and garage adapters

/// Retains canonical command state and pins the immutable target through actual network completion.
@MainActor
@Observable
final class UKServerUIDoorSource {
    struct Ticket: Equatable {
        let id: UUID
        let entityID: String
        let liveState: String?
        let spec: TileActionSpec
    }

    let entityID: String
    let kind: ServerUICompositionDocument.DoorKind
    @ObservationIgnored private let context: UKContext
    @ObservationIgnored private let bag = UKObservationBag()
    private(set) var actions: OptimisticActions?
    private(set) var garage: GarageDoorController?
    private(set) var network: Ticket?
    @ObservationIgnored private(set) var completion: Task<Void, Never>?

    init(entityID: String, kind: ServerUICompositionDocument.DoorKind, context: UKContext) {
        self.entityID = entityID
        self.kind = kind
        self.context = context
        if kind == .garage, let caller = context.caller {
            garage = GarageDoorController(entityId: entityID, liveState: context.store.entity(entityID).state?.state,
                                          caller: caller, scheduler: TaskRevertScheduler())
        }
        let box = context.store.entity(entityID)
        bag.observe { [weak self] in
            let state = box.state?.state
            let available = !context.valuesPending && context.caller != nil
                && context.connection.map({ SecurityScreen.canSend($0.status) }) != false
            Task { @MainActor [weak self] in
                self?.garage?.liveDidChange(state)
                self?.garage?.connectionDidChange(canSend: available)
            }
        }
    }

    var hasPendingIntent: Bool {
        network != nil || actions?.isPending(entityID) == true
            || garage.map { $0.networkCount > 0 || $0.isInteractionLocked || $0.phase == .sending || $0.phase == .pending } == true
    }
    var state: String? { garage?.displayState ?? actions?.shown(entityID) ?? context.store.entity(entityID).state?.state }
    var failed: Bool { garage?.phase == .error || actions?.isFailed(entityID) == true }

    /// The style the door's state is read through: the garage door's, or the lock's.
    var style: StateStyle { kind == .lock ? .lock : .garageDoor }

    var spec: TileActionSpec {
        let live = context.store.entity(entityID).state
        var spec: TileActionSpec
        if let garage {
            let state = EntityState(entityId: entityID, state: garage.liveState)
            spec = StateStyle.garageDoor.spec(for: state, entityId: entityID, requestInFlight: garage.phase == .sending) ?? Self.noAction
            if garage.isInteractionLocked || garage.networkCount > 0 { spec.phase = .inFlight }
        } else if kind == .lock {
            spec = StateStyle.lock.spec(for: live?.showing(actions?.shown(entityID)), entityId: entityID) ?? Self.noAction
            if network != nil { spec.phase = .inFlight }
        } else {
            spec = (StateStyle.garageDoor.spec(for: live, entityId: entityID) ?? Self.noAction).with(phase: .unavailable)
        }
        if context.valuesPending || context.caller == nil || context.connection.map({ !SecurityScreen.canSend($0.status) }) == true
            || ScreenshotPrivacy.isRedacting || live?.isUnavailable != false {
            spec.phase = .unavailable
        }
        return spec
    }

    /// A style that offers no disc here would be a style error; the tile stays unavailable.
    private static let noAction = TileActionSpec(id: "door", verb: "Open", symbol: "door.garage.closed", phase: .unavailable, feedback: .tracked)

    func reserve(expected: TileActionSpec) throws -> Ticket {
        guard network == nil, (garage?.networkCount ?? 0) == 0, garage?.isInteractionLocked != true,
              spec == expected, spec.phase == .ready, spec.call != nil else { throw unavailable() }
        return Ticket(id: UUID(), entityID: entityID, liveState: context.store.entity(entityID).state?.state, spec: spec)
    }

    func execute(_ ticket: Ticket) throws {
        guard ticket.entityID == entityID, ticket.liveState == context.store.entity(entityID).state?.state,
              network == nil, (garage?.networkCount ?? 0) == 0, garage?.isInteractionLocked != true,
              ticket.spec == spec, spec.phase == .ready,
              let call = ticket.spec.call, let caller = context.caller else { throw unavailable() }
        if let garage {
            garage.liveDidChange(ticket.liveState)
            garage.connectionDidChange(canSend: true)
            guard GarageDoorController.command(for: ticket.liveState)?.service == call.service else { throw unavailable() }
            garage.send()
        } else {
            let actions = actions ?? OptimisticActions(store: context.store, rules: [entityID: .liveChange], caller: caller)
            self.actions = actions
            network = ticket
            let task = actions.perform(call, showing: [OptimisticIntent(entityID, value: call.service == "lock" ? "locking" : "unlocking")],
                                       failing: entityID)
            completion = Task { @MainActor in
                await task.value
                if self.network == ticket { self.network = nil }
                self.completion = nil
            }
        }
    }

    private func unavailable() -> UKServerUIRendererError {
        .init(code: .unavailableSource, pointer: "/document/dataSources")
    }
}
#endif
