import Foundation

/// The room power disc on a Home overview Lights room card (audit item 12, owner 2026-10-27): one disc that turns the room's lights off
/// when any is on, else on.
///
/// It is not a ``TileActionProviding``: the answer comes from many entities (each light and the room's group light), not from one, so
/// the view hands it a reader. The call is the one the room's lights sheet already makes for the whole room, an explicit `turn_on` /
/// `turn_off` (never `toggle`, which Presence Based Lighting reverts, ``LightControl``) on the room's **group entity**
/// (``RoomGroup/entityId``, web `toggleEntityId`); the optimistic values cover the group and each light, so the card and the
/// lights beneath it move together.
///
/// | room | verb | symbol | isOn | phase |
/// |---|---|---|---|---|
/// | any light on (``RoomOverview/isActive(_:_:read:)``) | Turn Off | `power` | true | ready |
/// | none on | Turn On | `power` | false | ready |
/// | every light unavailable | Turn On | `power` | false | unavailable |
public struct RoomLightsPowerActions: Equatable, Sendable {
    /// The action's id in every state: `<tile-id>.action.power`.
    public static let actionId = "power"

    /// The room's lights.
    public var group: RoomGroup

    /// Creates the provider for a Lights room group.
    public init(_ group: RoomGroup) {
        self.group = group
    }

    /// The group light the call targets; the first light for a room whose group has no entity of its own.
    public var targetEntityId: String? { group.entityId ?? group.items.first?.entityId }

    /// Every entity that shows the new state at once: the group light, then each light, once each.
    public var entityIds: [String] {
        var seen = Set<String>()
        return ([group.entityId].compactMap { $0 } + group.items.map(\.entityId)).filter { seen.insert($0).inserted }
    }

    /// Whether the room reads on: any of its lights is (the card's own fill rule).
    public func isOn(read: RoomOverview.Read) -> Bool {
        RoomOverview.isActive(.lights, group, read: read)
    }

    /// Whether no light in the room answers, so the disc dims in place.
    public func isUnavailable(read: RoomOverview.Read) -> Bool {
        let items = group.items
        return !items.isEmpty && items.allSatisfy { read($0.entityId)?.isUnavailable ?? true }
    }

    /// The disc for the room as `read` shows it (the live state with any optimistic overlay applied).
    public func actions(read: RoomOverview.Read) -> [TileActionSpec] {
        let on = isOn(read: read)
        let command = targetEntityId.map { LightControl.power($0, on: !on) }
        let value = on ? "off" : "on"
        return [TileActionSpec(
            id: Self.actionId, verb: on ? "Turn Off" : "Turn On", symbol: "power", isOn: on,
            phase: isUnavailable(read: read) ? .unavailable : .ready, feedback: .optimistic,
            call: command.map { ServiceCall($0.domain, $0.service, target: $0.entityId) },
            optimistic: entityIds.map { OptimisticIntent($0, value: value) },
            label: "\(on ? "Turn Off" : "Turn On") \(group.room) lights"
        )]
    }

    /// The state lines the card can show, so its width never changes with the state.
    public var stateTextCandidates: [String] { ["Off", "On", "\(group.items.count) On", "Unavailable"] }
}
