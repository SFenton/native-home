import Foundation

// MARK: - Grid groups (`sh.grid-state-groups@1`)

/// A `tile-grid` grouped by the state its tiles draw (`sh.grid-state-groups@1`). Each tile sits under the heading of the group that holds its
/// state. A group with no tiles is not drawn; the grid stays one grid, so its columns are solved once (`.agents/design/mockups/proposals/sim-fidelity-contract` README: group heading, owner picked A, the title only).
public struct ServerUIGridGroups: Equatable, Sendable {
    /// The three faces a tile draws, and so the three states a group holds.
    public enum State: String, Sendable, CaseIterable { case active, idle, unavailable }

    /// The most groups: one per state.
    public static let maximumGroups = 3

    /// One heading and the states under it.
    public struct Group: Equatable, Sendable, Identifiable {
        public let id: String
        public let title: String
        public let states: [State]

        /// Creates a group.
        public init(id: String, title: String, states: [State]) {
            self.id = id
            self.title = title
            self.states = states
        }
    }

    /// The groups in drawn order.
    public let items: [Group]

    /// Creates groups.
    public init(items: [Group]) { self.items = items }

    /// One problem the shape cannot say, as a code at a pointer below `props/groups`.
    struct Problem: Equatable {
        let code: ServerUICompositionError.Code
        let at: String
    }

    /// The checks the shape cannot make: a group id is unique, a state appears in one group once, and every state appears.
    static func problems(_ items: [(id: String, states: [State])]) -> [Problem] {
        var found: [Problem] = []
        var ids: Set<String> = []
        var seen: Set<State> = []
        for (at, group) in items.enumerated() {
            if !ids.insert(group.id).inserted { found.append(.init(code: .duplicateID, at: "/items/\(at)/id")) }
            for (offset, state) in group.states.enumerated() where !seen.insert(state).inserted {
                found.append(.init(code: .invalidCombination, at: "/items/\(at)/states/\(offset)"))
            }
        }
        if State.allCases.contains(where: { !seen.contains($0) }) { found.append(.init(code: .invalidCombination, at: "/items")) }
        return found
    }

    /// The index of the group that holds `state`; a state no group holds goes under the last group.
    public func index(of state: State) -> Int {
        items.firstIndex { $0.states.contains(state) } ?? items.count - 1
    }

    /// One drawn group: its heading and the keys of its tiles in the grid's order.
    public struct Section<Key: Hashable & Sendable>: Equatable, Sendable {
        public let group: Group
        public let keys: [Key]
    }

    /// The tiles of each group, in the groups' order and the grid's order inside a group; a group with no tile is dropped.
    public func arrange<Key: Hashable & Sendable>(_ tiles: [(key: Key, state: State)]) -> [Section<Key>] {
        var buckets = items.map { (group: $0, keys: [Key]()) }
        guard !buckets.isEmpty else { return [] }
        for tile in tiles { buckets[index(of: tile.state)].keys.append(tile.key) }
        return buckets.filter { !$0.keys.isEmpty }.map { Section(group: $0.group, keys: $0.keys) }
    }
}
