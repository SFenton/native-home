import Foundation
import Observation

// MARK: - Configured light intent adapter

/// Pins the actual call lifetime independently of the shorter optimistic overlay lifetime.
@MainActor
@Observable
public final class ServerUIHomeLightSource {
    /// The authored failure choices.
    public enum Failure: Error, Equatable { case unavailable, invalidCommand }
    public let entityId: String
    public let memberEntityIds: [String]
    public private(set) var inFlight = 0
    public let actions: OptimisticActions
    @ObservationIgnored private let read: @MainActor () -> EntityState?
    @ObservationIgnored private let readMember: @MainActor (String) -> EntityState?
    @ObservationIgnored private var generation = 0

    /// Creates a server uihome light source.
    public init(entityId: String, memberEntityIds: [String] = [], caller: any HassServiceCalling,
                scheduler: any RevertScheduler = TaskRevertScheduler(), actions: OptimisticActions? = nil,
                readMember: @escaping @MainActor (String) -> EntityState? = { _ in nil },
                read: @escaping @MainActor () -> EntityState?) {
        self.entityId = entityId
        self.memberEntityIds = memberEntityIds
        self.read = read
        self.readMember = readMember
        let ids = Set([entityId] + memberEntityIds)
        self.actions = actions ?? OptimisticActions(rules: Dictionary(uniqueKeysWithValues: ids.map { ($0, .liveChange) }),
            caller: caller, scheduler: scheduler) { id in id == entityId ? read()?.state : readMember(id)?.state }
    }

    public var hasPendingIntent: Bool { inFlight > 0 || ([entityId] + memberEntityIds).contains(where: actions.isPending) }
    public var isFailed: Bool { actions.isFailed(entityId) }
    public var shown: EntityState? { read()?.showing(actions.shown(entityId)) }

    /// The room disc uses the canonical aggregate rule and its exact group/member optimism.
    public func roomPower(title: String) -> TileActionSpec {
        let members = memberEntityIds.isEmpty ? [entityId] : memberEntityIds
        let group = RoomGroup(title, entityId: entityId, members.map { RoomGroupItem("", $0) })
        let spec = RoomLightsPowerActions(group).actions { id in
            let entity = id == self.entityId ? self.read() : self.readMember(id)
            return entity?.isUnavailable == false ? entity?.showing(self.actions.shown(id)) : entity
        }[0]
        return read()?.isUnavailable == false ? spec : spec.with(phase: .unavailable)
    }

    /// Toggles the room lights and returns the task that finishes the call.
    @discardableResult
    public func performRoomPower(title: String, expected: TileActionSpec) throws -> Task<Void, Never> {
        guard expected == roomPower(title: title), expected.phase == .ready else { throw Failure.unavailable }
        return try perform(LightControl.power(entityId, on: expected.isOn != true))
    }

    /// Validates again at the gesture boundary; callers cannot smuggle a different target/service.
    @discardableResult
    public func perform(_ command: LightControl.Command) throws -> Task<Void, Never> {
        guard let entity = read(), !entity.isUnavailable else { throw Failure.unavailable }
        guard entity.entityId == entityId, ["light", "switch", "input_boolean"].contains(entity.domain) else { throw Failure.invalidCommand }
        let expected: LightControl.Command
        if let percent = command.brightnessPercent {
            guard LightControl.isDimmable(entity), (1...100).contains(percent) else { throw Failure.invalidCommand }
            expected = LightControl.brightness(entityId, percent: Double(percent))
        } else {
            guard command.service == "turn_on" || command.service == "turn_off" else { throw Failure.invalidCommand }
            expected = LightControl.power(entityId, on: command.service == "turn_on")
        }
        guard command == expected else { throw Failure.invalidCommand }
        inFlight += 1
        generation += 1
        let generation = generation
        let call = actions.perform(command.domain, command.service, data: command.serviceData,
                                   showing: Set([entityId] + memberEntityIds).sorted().map {
                                       OptimisticIntent($0, value: command.service == "turn_off" ? "off" : "on")
                                   },
                                   failing: entityId, onFailure: { [weak self] in
            guard let self, self.generation == generation, !actions.isFailed(entityId) else { return }
            actions.overlay.markFailed(entityId)
        })
        return Task { @MainActor [self] in
            await call.value
            inFlight -= 1
        }
    }
}
