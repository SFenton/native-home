import SwiftUI

/// Direction G's lit tile for lights that are on (direction-g.md, Colour families: Lights).
public enum LitTile {
    /// The bright band, top to bottom.
    public static let bandTop = Color(bandTopToken)
    public static let bandBottom = Color(bandBottomToken)
    /// The tile under the band, past the brightness level.
    public static let base = Color(baseToken)
    /// The bulb glyph.
    public static let glyph = Color(glyphToken)
    /// Titles on the lit tile.
    public static let ink = Color(inkToken)
    /// How strong the status text is: `#1C1C1E` at 85%. At 72% it measured 4.2:1 on a blue bulb's band (Custom
    /// Lights, "41%"); 85% keeps 5.3:1 under the strongest bulb tint (``bulbTint``).
    public static let secondaryInkOpacity = 0.85
    /// Status text on the lit tile.
    public static let secondaryInk = Color(secondaryInkToken)
    /// How much a coloured bulb tints its band.
    public static let bulbTint = 0.3

    /// Power's fill runs from a lighter yellow at the top.
    public static let powerTop = Color(powerTopToken)

    // MARK: Raw sRGB (the source of the `Color`s above)

    public static let bandTopToken = HassRGB(rgb: 0xFFF3DE)
    public static let bandBottomToken = HassRGB(rgb: 0xFFE2B2)
    public static let baseToken = HassRGB(rgb: 0xEADBC4)
    public static let glyphToken = HassRGB(rgb: 0xD97A00)
    public static let inkToken = HassRGB(rgb: 0x1C1C1E)
    public static let secondaryInkToken = HassRGB(rgb: 0x1C1C1E).opacity(secondaryInkOpacity)
    public static let powerTopToken = HassRGB(rgb: 0xFFE45C)
}
