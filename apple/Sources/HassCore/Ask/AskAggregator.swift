import Foundation

// MARK: - Aggregator

/// Counts and lists over leaf entities, computed in code so the model never counts.
///
/// Membership follows the house document first (a room's light group, its contact sensors, its occupancy sensors, its
/// vents) and the registry second (area and floor), counts leaf entities only (a group entity and a colour channel are not
/// lights) and keeps an explicit "not in a room" bucket rather than dropping an entity with no room.
public struct AskAggregator: Sendable {
    /// The index the aggregates read.
    public let index: AskableIndex

    /// Creates an aggregator over `index`.
    public init(index: AskableIndex) { self.index = index }

    // MARK: Membership

    /// Kinds the house document lists room by room (lights, contact sensors, occupancy, temperature, vents).
    static let documentListKinds: Set<AskKind> = [.light, .window, .door, .occupancy, .temperature, .vent]

    /// The entities of `kind` in `scope`, leaf entities only, in a stable order.
    ///
    /// The configuration defines the set. A room with a house-document list for the kind is answered from that list. The
    /// whole house, and a floor, is the union of those lists when the document keeps any for the kind, else (and for a room
    /// with no list) the configured entities the registry places there. A kind the document keeps one list for (the garage
    /// doors, the locks, the cameras) is that list. One thing reported twice counts once (``collapsingSameThing(_:)``).
    public func members(kind: AskKind, scope: AskScope) -> [AskEntry] {
        var ids: [String] = []
        func add(_ list: [String]) { for id in list where !ids.contains(id) { ids.append(id) } }
        let wholeHouse: Bool = { if case .house = scope { return true } else { return false } }()
        let roomOnly: Bool = { if case .room = scope { return true } else { return false } }()
        // A light is a `light` entity: the switch that feeds one is not counted twice.
        let registry = index.entries.values.filter { $0.askable && $0.kind == kind && (kind != .light || $0.domain == "light") }.sorted { $0.id < $1.id }
        if wholeHouse, let list = index.deviceLists[kind] {
            add(list)
        } else {
            let docDefines = Self.documentListKinds.contains(kind) && index.documentGroups.values.contains { !Self.list($0, kind: kind).isEmpty }
            if case .floor(let floorId) = scope {
                // A floor is what its configured entities' areas say: the document's lists, kept to the entities that sit on it.
                let pool = docDefines ? index.documentGroups.keys.sorted().flatMap { documentList(kind: kind, roomKey: $0) } : registry.map(\.id)
                add(pool.filter { index.entry($0)?.floorId == floorId })
            }
            for key in roomKeys(in: scope) where !isFloor(scope) {
                let doc = documentList(kind: kind, roomKey: key)
                if !doc.isEmpty { add(doc) } else if roomOnly || !docDefines { add(registry.filter { $0.roomKey == key }.map(\.id)) }
            }
            if wholeHouse {
                if kind == .door || kind == .window { add(index.houseContactIds.filter { index.entry($0)?.kind == kind }) }
                if !docDefines { add(registry.filter { $0.roomKey == nil }.map(\.id)) }
            }
        }
        return collapsingSameThing(ids.compactMap { index.entry($0) }.filter { !$0.excludedFromAggregates && (kind != .light || $0.domain == "light") })
    }

    /// `entries` with each thing counted once: an overlay "same as" set keeps its first present member, and a contact sensor
    /// on the same device as a cover of the same kind (a door or garage door reported twice) gives way to the cover, so the
    /// door is named by the door.
    public func collapsingSameThing(_ entries: [AskEntry]) -> [AskEntry] {
        var drop = Set<String>()
        let present = Set(entries.map(\.id))
        for list in index.configuration.sameAs {
            let here = list.filter { present.contains($0) }
            for id in here.dropFirst() { drop.insert(id) }
        }
        let covers = entries.filter { $0.domain == "cover" && $0.deviceId != nil }
        for e in entries where e.domain == "binary_sensor" && e.deviceId != nil {
            if covers.contains(where: { $0.deviceId == e.deviceId && $0.kind == e.kind }) { drop.insert(e.id) }
        }
        return drop.isEmpty ? entries : entries.filter { !drop.contains($0.id) }
    }

    /// Entities that exist in Home Assistant but are not configured, of `kind`, within `scope`. Names only; used to tell
    /// "not set up" from "does not exist".
    public func outsiders(kind: AskKind, scope: AskScope) -> [AskEntry] {
        index.outsiders.values.filter { $0.kind == kind && index.contains(scope, $0) }.sorted { $0.id < $1.id }
    }

    /// Whether the configuration defines a house-wide set for `kind`.
    public func definesHouseSet(_ kind: AskKind) -> Bool { index.configuration.houseSetKinds.contains(kind) }

    private static func list(_ g: AskableIndex.DocumentRoomGroups, kind: AskKind) -> [String] {
        switch kind {
        case .light: return g.lights
        case .window, .door: return g.contacts.filter { $0.kind == kind }.map(\.entityId)
        case .occupancy: return g.occupancy
        case .temperature: return g.temperatures
        case .vent: return g.vents
        default: return []
        }
    }

    private func documentList(kind: AskKind, roomKey: String) -> [String] {
        guard let g = index.documentGroups[roomKey] else { return [] }
        return Self.list(g, kind: kind)
    }

    private func isFloor(_ scope: AskScope) -> Bool { if case .floor = scope { return true } else { return false } }

    /// The room keys a scope covers.
    public func roomKeys(in scope: AskScope) -> [String] {
        switch scope {
        case .house: return index.rooms.keys.sorted()
        case .room(let key): return [key]
        case .floor(let id): return index.rooms.values.filter { $0.floorId == id }.map(\.key).sorted()
        }
    }

    // MARK: Summary

    /// A count over one set of entities.
    public struct Summary: Sendable, Equatable {
        /// Every member.
        public var members: [String]
        /// The members in the asked state, oldest change first.
        public var matching: [String]
        /// The members reporting unavailable or unknown.
        public var unavailable: [String]
        /// Members with no room.
        public var unplaced: [String]
        /// The total.
        public var total: Int { members.count }
    }

    /// Splits `members` into those for which `isMatching` holds and the rest, oldest change first.
    public func summarize(_ members: [AskEntry], isMatching: (AskEntry) -> Bool) -> Summary {
        let usable = members.filter { !$0.isUnavailable }
        let match = usable.filter(isMatching).sorted { $0.state.lastChanged < $1.state.lastChanged }
        return Summary(
            members: members.map(\.id), matching: match.map(\.id), unavailable: members.filter(\.isUnavailable).map(\.id),
            unplaced: members.filter { $0.roomKey == nil }.map(\.id)
        )
    }

    /// The mean of the numeric states of `members`, or nil when none reads a number.
    public func mean(_ members: [AskEntry]) -> Double? {
        let values = members.compactMap { Double($0.state.state) }
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    /// The reading of a room: the mean of its sensors of `kind`.
    public func roomReading(kind: AskKind, roomKey: String) -> Double? {
        mean(members(kind: kind, scope: .room(roomKey)).filter { !$0.isUnavailable })
    }

    /// Every room that has at least one reading of `kind`, with the reading, for a ranking.
    public func roomReadings(kind: AskKind) -> [(roomKey: String, value: Double)] {
        var out: [(String, Double)] = []
        for key in index.rooms.keys.sorted() {
            if let v = roomReading(kind: kind, roomKey: key) { out.append((key, v)) }
        }
        // A document alias can map two titles to one room; list each room once.
        var seen = Set<String>()
        return out.filter { seen.insert(index.rooms[$0.0]?.key ?? $0.0).inserted }.map { (roomKey: $0.0, value: $0.1) }
    }
}
