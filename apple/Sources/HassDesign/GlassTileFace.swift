import CoreGraphics

/// The entity tile face's shared metrics (the face itself is drawn by `UKGlassTileFaceView`).
///
/// Direction G faces (``TileFaceStyle``): off is dark with the glyph in its family colour, a light that is on is
/// the warm lit tile, other devices fill with their family colour, and an error is a red glyph and state.
public enum GlassTileFace {
    /// Width the text keeps clear for the centred chevron: its glyph plus the gap before it.
    public static let chevronReserve: CGFloat = 20

    /// The row layout's glyph column: wide enough for the widest symbol so every title starts at the same x.
    public static let rowGlyphWidth: CGFloat = 30
}
