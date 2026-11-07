import Foundation

/// A device kind's actions: state in, specs out. Conformers are value types, one per device kind, each with a test
/// suite. Providers are pure; the view feeds them the *shown* state (live with the optimistic overlay applied).
///
/// An unavailable entity yields the same specs, all ``TileActionSpec/Phase/unavailable``, so the strip dims in place
/// and nothing moves.
public protocol TileActionProviding: Sendable {
    /// The tile's actions for `state` (`nil` when the entity is missing).
    func actions(for state: EntityState?) -> [TileActionSpec]

    /// Every state string the tile can show, so the grid can size a tile for its longest possible state and a live
    /// update never re-spans it.
    var stateTextCandidates: [String] { get }
}

public extension TileActionProviding {
    /// No candidates beyond what the title says.
    var stateTextCandidates: [String] { [] }
}
