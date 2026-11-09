import Foundation

/// What kind of tile a card is, from whether it opens something and how many actions it carries (shape tells the class,
/// owner 2026-10-26). One source of truth: HassDesign's `TileBehavior` is mapped from this, never computed twice.
public enum TileClassification: Equatable, Sendable {
    /// Text and disc; the body does what the disc shows. Carries the number of actions.
    case action(Int)
    /// Glyph, text, chevron; up to two discs left of the chevron, more below.
    case navigation(actionCount: Int)
    /// Read-only: glyph, flat face, no press response.
    case state

    /// Classifies from a destination (a sheet or page) and an action count.
    public static func classify(hasDestination: Bool, actions: Int) -> TileClassification {
        if hasDestination { return .navigation(actionCount: max(0, actions)) }
        return actions > 0 ? .action(actions) : .state
    }

    /// Classifies from a destination and the tile's specs.
    public static func classify(hasDestination: Bool, actions: [TileActionSpec]) -> TileClassification {
        classify(hasDestination: hasDestination, actions: actions.count)
    }

    /// The tile takes taps (an action or a navigation tile).
    public var isButton: Bool { self != .state }

    /// The tile is read-only and must draw the flat face.
    public var isInert: Bool { self == .state }

    /// How many actions the tile carries.
    public var actionCount: Int {
        switch self {
        case let .action(count): count
        case let .navigation(actionCount): actionCount
        case .state: 0
        }
    }
}
