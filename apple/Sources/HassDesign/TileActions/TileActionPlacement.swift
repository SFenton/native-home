import SwiftUI

/// The owner's placement rules, encoded once (`.agents/design/action-navigation-tiles.md`, option B).
public enum TileActionPlacement {
    /// Up to two actions trail on any tile; three or more, accessibility text sizes, or a tile too narrow go below.
    /// - Parameters:
    ///   - count: How many actions the tile has.
    ///   - behavior: The body behaviour. It does not move the slot: a navigation tile's discs sit left of the chevron.
    ///   - accessibilitySize: Whether text is at an accessibility size.
    ///   - fitsTrailing: Whether the discs fit beside the text at the tile's width.
    public static func slot(count: Int, behavior: TileBehavior, accessibilitySize: Bool, fitsTrailing: Bool) -> TileActionSlot {
        guard count > 0 else { return .none }
        if accessibilitySize || count > 2 || !fitsTrailing { return .below }
        return .trailing
    }

    /// Whether the tile draws no leading glyph because the first disc carries the state glyph: an action tile with
    /// trailing discs. Navigation and read-only tiles keep the glyph leading, so the shape tells the classes apart.
    public static func carriesGlyph(behavior: TileBehavior, slot: TileActionSlot) -> Bool {
        if case .perform = behavior { return slot == .trailing }
        return false
    }

    /// Whether the single disc is hidden from VoiceOver because it repeats the tile body exactly: one item, and the body
    /// performs that item. The tile is then one element.
    public static func discIsAccessibilityHidden(behavior: TileBehavior, items: [TileActionItem]) -> Bool {
        guard items.count == 1, case let .perform(id) = behavior else { return false }
        return items[0].id == id
    }
}
