import SwiftUI

/// What tapping the tile's body does.
public enum TileBehavior: Equatable, Sendable {
    /// The body tap runs this action (the primary of a set, or the only one).
    case perform(TileActionItem.ID)
    /// The body tap opens something; a chevron sits at the trailing edge.
    case navigate
    /// A read-only tile: flat, not a button.
    case inert
}
