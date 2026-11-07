import SwiftUI

/// Where a tile's action strip goes.
public enum TileActionSlot: Equatable, Sendable {
    /// No actions.
    case none
    /// Vertically centred at the trailing edge (left of the chevron's reserve on a navigation tile).
    case trailing
    /// Centred under the text.
    case below
}
