import Foundation

/// How a tile's text sits in the room the grid gave it.
public enum TileTextFit: Equatable, Sendable {
    /// The text wraps to as many lines as it needs (every tile that declares no minimum width).
    case natural
    /// One line: the grid widened the tile to fit it (``TileMinimumWidth``).
    case oneLine
    /// The grid could not widen the tile any more (``DynamicGridMetrics/TileSpan/isCapped``): an overflowing line scrolls as a
    /// ``TickerLabel``, or wraps under Reduce Motion and at accessibility sizes (the ticker's own rule), and the tile grows taller.
    case ticker
}
