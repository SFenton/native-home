import SwiftUI

/// The floating action bar's tokens, shared with the UIKit bar (`UKFloatingActionBar`), which draws the bar itself
/// (pattern: `.agents/patterns/floating-actions.md`, direction G's page bottom toolbar). The SwiftUI bar, search field
/// and `floatingActionBar(_:search:)` modifier were removed with the SwiftUI app.
public enum FloatingActionBar {
    /// The prominent capsule's fill: G's `#0071E3`, 4.6:1 under white (``HassTokens/Ink/actionFill``).
    public static let tint = Color(tintToken)
    /// ``tint`` as raw sRGB.
    public static let tintToken = HassTokens.RGB.Ink.actionFill
    /// An active circle's fill (a sort or filter is applied): system gray 6 light, `#F2F2F7`, under a black glyph
    /// (mockup n6, `.n6-tool.active`).
    public static let activeTint = Color(activeTintToken)
    /// ``activeTint`` as raw sRGB.
    public static let activeTintToken = HassRGB(rgb: HassTokens.Palette.activeControlFill)
    /// The glyph on an active circle.
    public static let activeGlyph = Color(activeGlyphToken)
    /// ``activeGlyph`` as raw sRGB.
    public static let activeGlyphToken = HassRGB.black

    /// Button height: comfortably above the 44 pt minimum, like the web's 56 px FAB and G's 52 pt toolbar circles.
    public static let size: CGFloat = 52
    /// How far the buttons grow with Dynamic Type: 1.5 times the base size.
    public static let maxGrowth: CGFloat = 1.5
}
