import SwiftUI

/// The tile ground a disc sits on.
public enum TileActionFace: Equatable, Sendable {
    /// An off tile: dark ground.
    case dark
    /// A tile filled with its family colour.
    case filled
    /// The warm lit tile of a light that is on (``BrightnessTile``).
    case lit
}
