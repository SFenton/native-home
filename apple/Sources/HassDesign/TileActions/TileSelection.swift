import SwiftUI

/// What the disc of a tile that *chooses* shows (owner, 2026-10-27, option C of selection-tiles; pattern:
/// `.agents/patterns/action-tiles.md`, Selection face). HassDesign's twin of HassCore's `TileActionSpec.Selection`.
///
/// A chosen tile fills in its family colour and its disc is white; an unchosen tile stays dark and its disc is an empty ring.
/// VoiceOver reads the "selected" trait, never "switch".
public enum TileSelection: Equatable, Sendable {
    /// One of several: a white disc with a `checkmark` when chosen, an empty ring when not.
    case single(isSelected: Bool)
    /// One of an ordered set (vacuum rooms): a white disc with the 1-based order when chosen, an empty ring when `position` is nil.
    case ordered(position: Int?)

    /// Whether the tile is chosen.
    public var isSelected: Bool {
        switch self {
        case let .single(isSelected): isSelected
        case let .ordered(position): position != nil
        }
    }

    /// The place in the order, for a chosen ordered selection.
    public var position: Int? {
        if case let .ordered(position) = self { return position }
        return nil
    }
}
