import SwiftUI

/// The ink of an action disc (`.agents/design/action-navigation-tiles.md`, Discs). Pure, so it is unit-tested apart from the
/// drawing in ``TileActionButtonStyle``.
public enum TileActionInk {
    /// The disc fill and glyph colour for a face and state.
    ///
    /// - On: a solid white disc with the family fill as the glyph.
    /// - Lit tile: the dark disc (`LitTile.ink`) with a white glyph, on or off, because a lit band can end under the disc and
    ///   ink chosen for the tile measured 1.9:1 there.
    /// - Filled tile, off: black at 18% with a white glyph.
    /// - Dark tile, off: white at 16% with the family's off-glyph colour, or white for a family whose off glyph measures
    ///   under 3:1 against that disc (``offGlyphPasses(_:)``).
    public static func resolve(face: TileActionFace, isOn: Bool, family: ColorFamily?) -> (disc: Color, glyph: Color) {
        if face == .lit { return (LitTile.ink, .white) }
        if isOn { return (.white, family?.fill ?? LitTile.ink) }
        switch face {
        case .filled, .lit: return (.black.opacity(filledDiscOpacity), .white)
        case .dark:
            guard let family, offGlyphPasses(family) else { return (.white.opacity(darkDiscOpacity), .white) }
            return (.white.opacity(darkDiscOpacity), family.offGlyph)
        }
    }

    /// ``resolve(face:isOn:family:)`` as raw sRGB, which the UIKit port draws.
    public static func resolveTokens(face: TileActionFace, isOn: Bool, family: ColorFamily?) -> (disc: HassRGB, glyph: HassRGB) {
        if face == .lit { return (LitTile.inkToken, .white) }
        if isOn { return (.white, family?.fillToken ?? LitTile.inkToken) }
        switch face {
        case .filled, .lit: return (HassRGB.black.opacity(filledDiscOpacity), .white)
        case .dark:
            guard let family, offGlyphPasses(family) else { return (HassRGB.white.opacity(darkDiscOpacity), .white) }
            return (HassRGB.white.opacity(darkDiscOpacity), family.offGlyphToken)
        }
    }

    /// The white disc's opacity on a dark tile.
    public static let darkDiscOpacity = 0.16
    /// The black disc's opacity on a filled tile.
    public static let filledDiscOpacity = 0.18
    /// The least contrast a glyph keeps against its disc (WCAG 1.4.11).
    public static let minimumContrast = 3.0

    /// The ground a dark tile's disc is measured over: the thin module's colour.
    static var darkGround: UInt32 { HassTokens.Palette.moduleThin }

    /// The dark disc composited over ``darkGround``, as `0xRRGGBB`.
    static var darkDiscRGB: UInt32 { ColorFamily.mix(0xFFFFFF, darkGround, darkDiscOpacity) }

    /// The contrast of a family's off glyph against the resting dark disc.
    public static func offGlyphContrast(_ family: ColorFamily) -> Double {
        ChipTint.contrast(family.offGlyphRGB(.dark), darkDiscRGB)
    }

    /// Whether the family's off glyph keeps 3:1 against the resting dark disc.
    public static func offGlyphPasses(_ family: ColorFamily) -> Bool {
        offGlyphContrast(family) >= minimumContrast
    }
}
