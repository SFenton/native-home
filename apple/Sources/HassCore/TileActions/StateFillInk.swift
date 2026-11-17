import Foundation

// MARK: - Ink of a state line on a fill

/// The ink of a state tile's state line on its style fill (`sh.tile-ink@1`, `fillInk`).
///
/// The old family fill drew its supporting text in white at 92% (`ColorFamily.secondaryInkToken`, `ColorFamily.swift:195` at 2678f1d1); the
/// authored fill drew white at 100% (`RoomPalette.inkToken`). The words are authored so a lowered tile can match either. It changes the state
/// line only, never the title.
public enum StateFillInk: String, Equatable, Sendable, CaseIterable {
    /// White at 100%. The default, and what a tile without the field draws.
    case white
    /// White at 92% (``softOpacity``).
    case soft

    /// The opacity of ``soft``.
    public static let softOpacity = 0.92

    /// The white's opacity: 1 for ``white``, ``softOpacity`` for ``soft``.
    public var opacity: Double { self == .soft ? Self.softOpacity : 1 }
}
