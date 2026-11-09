import SwiftUI

/// The one round action button of a tile: a 44 pt disc (``TileActionDisc``) that replaces the bathroom fan's `FanRailButton` and
/// ``BrightnessTile``'s power button (pattern: `.agents/patterns/action-tiles.md`).
///
/// The style draws the symbol itself, so it can swap it for a progress arc while an action is in flight; give the `Button` an
/// empty label. The press highlight reads `configuration.isPressed`, so the style keeps no state. The disc scales with
/// Dynamic Type up to 1.5× and the glyph stays under 45% of its width.
public enum TileActionButtonStyle {
    // MARK: Metrics

    /// Space between discs (HIG: about 12 pt between bezeled targets).
    public static let gap: CGFloat = 12

    /// The disc's diameter: 44 pt at the default size, never more than 66.
    public static func diameter(scaled: CGFloat) -> CGFloat {
        min(max(scaled, HassTokens.minTarget), HassTokens.minTarget * 1.5)
    }

    /// The glyph's point size: scales with text, but stays within 45% of the disc.
    public static func glyphSize(scaled: CGFloat, diameter: CGFloat) -> CGFloat {
        min(scaled, diameter * 0.45)
    }

    /// The width of `count` discs of `diameter` with ``gap`` between them.
    public static func stripWidth(count: Int, diameter: CGFloat) -> CGFloat {
        guard count > 0 else { return 0 }
        return CGFloat(count) * diameter + CGFloat(count - 1) * gap
    }
}
