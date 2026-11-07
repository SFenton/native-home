import SwiftUI

/// The *shape* of a tile's controls: which action ids in which order, and whether a custom control (the volume slider) is shown.
/// The tile animates only when this changes, never on a value change (a symbol swap, a phase, a verb), so live updates stay still.
/// HassDesign's twin of HassCore's `TileActionSlotSet`.
public struct TileActionShape: Equatable, Sendable {
    /// Action ids in order.
    public var ids: [String]
    /// Whether a custom control is shown under the discs.
    public var hasAccessory: Bool

    /// Creates a shape.
    public init(ids: [String], hasAccessory: Bool = false) {
        self.ids = ids
        self.hasAccessory = hasAccessory
    }

    /// The shape of `items`.
    public init(_ items: [TileActionItem], hasAccessory: Bool = false) {
        self.init(ids: items.map(\.id), hasAccessory: hasAccessory)
    }
}
