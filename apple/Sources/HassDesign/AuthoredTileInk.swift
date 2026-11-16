import Foundation

// MARK: - The ink a document gives a state tile (`sh.tile-ink@1`)

/// Where an authored tile ink applies, decided apart from the drawing so the UIKit port and its tests read one rule.
///
/// Each rule reproduces what the old family atom drew, so a lowered tile matches it: the icon tint is the off glyph of a family face
/// (`TileFaceInk.glyphToken`, `.off`), the button tint is the off glyph of a dark disc (`TileActionInk.resolveTokens`, `.dark`), and the soft
/// ink is the family fill's supporting text (`ColorFamily.secondaryInkToken`, white at 92%). Every default leaves the tile as it was.
public enum AuthoredTileInk {
    /// The opacity of the soft ink on a fill: white at 92% (`StateFillInk.soft`, `ColorFamily.secondaryInkToken`).
    public static let softFillInkOpacity = 0.92

    /// Whether an authored icon colour replaces the glyph on this face.
    ///
    /// It applies on a face that is neither filled nor an error: the dark faces (`off`, `tinted`, `warning`). The lit face (`filledWhen`), a
    /// family fill and a style fill keep their fixed ink, and the error face keeps its red.
    public static func glyphTintApplies(to style: TileFaceStyle) -> Bool {
        switch style {
        case .off, .tinted, .warning: true
        case .lit, .filled, .colored, .error: false
        }
    }

    /// The glyph colour of a face: `tint` where it applies, else `plain`, which the caller decided without it.
    public static func glyphToken(style: TileFaceStyle, tint: HassRGB?, plain: HassRGB) -> HassRGB {
        guard let tint, glyphTintApplies(to: style) else { return plain }
        return tint
    }

    /// Whether the button glyphs take the authored colour on this disc face: only a dark face does; a filled face keeps its black 18% disc with a
    /// white glyph.
    public static func discGlyphTintApplies(to face: TileActionFace) -> Bool { face == .dark }

    /// The state line's colour: the soft ink (white at 92%) on a style fill when asked, else `plain`.
    public static func stateLineToken(style: TileFaceStyle, softFillInk: Bool, plain: HassRGB) -> HassRGB {
        guard softFillInk, style.isColored else { return plain }
        return HassRGB.white.opacity(softFillInkOpacity)
    }
}
