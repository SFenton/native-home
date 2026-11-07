import Foundation

/// The *shape* of a tile's action list: which ids, in which order, and whether any is custom. The strip animates only
/// when this changes (an off remote's Power beside the chevron becoming a playing remote's transport), never on a
/// value change (a symbol swap, a phase, a verb), so live updates stay still.
public struct TileActionSlotSet: Equatable, Sendable {
    /// Spec ids in order.
    public var ids: [String]
    /// Whether any action is custom (no service call) or the tile hosts a custom control such as a volume slider.
    public var hasCustom: Bool

    /// The number of actions.
    public var count: Int { ids.count }

    /// Creates the shape of `specs`.
    /// - Parameters:
    ///   - specs: The tile's actions.
    ///   - hasCustomControl: The tile also hosts a custom control (the volume slider).
    public init(_ specs: [TileActionSpec], hasCustomControl: Bool = false) {
        ids = specs.map(\.id)
        hasCustom = hasCustomControl || specs.contains { $0.call == nil }
    }
}
