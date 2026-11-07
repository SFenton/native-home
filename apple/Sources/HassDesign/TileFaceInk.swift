import SwiftUI

/// The inks of a tile face (glyph, title, state), decided apart from the drawing so the SwiftUI ``GlassTileFace`` and the UIKit
/// port draw the same colours.
///
/// The lit tile and the family fills are fixed grounds with fixed inks, in every appearance. The off, tinted and error faces sit on
/// a dark module (pages) or the sheet's cell, which is white in a light sheet: their inks follow the ``TileAppearance``.
///
/// Each ink is decided once on raw ``HassRGB`` (the `…Token` functions); the `Color` functions derive from them, and the UIKit port
/// reads the tokens as `UIColor(_:)`.
public enum TileFaceInk {
    /// A grey for glyphs and chevrons that carry no meaning of their own.
    public static func muted(appearance: TileAppearance) -> Color { Color(mutedToken(appearance: appearance)) }

    /// ``muted(appearance:)`` as raw sRGB.
    public static func mutedToken(appearance: TileAppearance) -> HassRGB {
        appearance == .light ? HassTokens.RGB.Surface.secondaryInSheet : HassTokens.RGB.Surface.secondaryOnModule
    }

    /// The glyph colour.
    /// - Parameters:
    ///   - style: The face.
    ///   - appearance: Light only for a tile in a light sheet.
    ///   - finish: The finish drawn.
    ///   - isEnabled: False draws the neutral glyph in the muted grey.
    ///   - family: The tile's family, for the off glyph.
    ///   - tintGlyph: The caller's tint made legible for the appearance.
    public static func glyph(style: TileFaceStyle, appearance: TileAppearance, finish: TileFinish, isEnabled: Bool,
                             family: ColorFamily?, tintGlyph: Color) -> Color {
        switch style {
        case .tinted where isEnabled: tintGlyph
        default: Color(glyphToken(style: style, appearance: appearance, finish: finish, isEnabled: isEnabled,
                                  family: family, tintGlyph: HassRGB.white))
        }
    }

    /// ``glyph(style:appearance:finish:isEnabled:family:tintGlyph:)`` as raw sRGB, for a tint given as raw sRGB.
    public static func glyphToken(style: TileFaceStyle, appearance: TileAppearance, finish: TileFinish, isEnabled: Bool,
                                  family: ColorFamily?, tintGlyph: HassRGB) -> HassRGB {
        switch style {
        case .off:
            isEnabled ? (family.map { family in
                finish == .solid ? family.offGlyphToken : HassRGB(rgb: family.offGlyphRGB(appearance.scheme, under: finish))
            } ?? mutedToken(appearance: appearance)) : mutedToken(appearance: appearance)
        case .lit: LitTile.glyphToken
        case let .filled(family): family.inkToken
        case .colored: RoomPalette.inkToken
        case .tinted: isEnabled ? tintGlyph : mutedToken(appearance: appearance)
        case .error: HassRGB(rgb: appearance.errorRGB)
        }
    }

    /// The title colour.
    public static func primary(style: TileFaceStyle, appearance: TileAppearance) -> Color {
        Color(primaryToken(style: style, appearance: appearance))
    }

    /// ``primary(style:appearance:)`` as raw sRGB.
    public static func primaryToken(style: TileFaceStyle, appearance: TileAppearance) -> HassRGB {
        switch style {
        case .lit: LitTile.inkToken
        case let .filled(family): family.inkToken
        case .colored: RoomPalette.inkToken
        default: appearance == .light ? HassTokens.RGB.Ink.primary : .white
        }
    }

    /// The state-line colour.
    /// - Parameters:
    ///   - hasWash: A state wash lifts the dark ground toward its colour, and over a bright sky the 68% ink fell to 4.3:1.
    ///   - surface: Where the tile is drawn.
    public static func secondary(style: TileFaceStyle, appearance: TileAppearance, finish: TileFinish, surface: TileSurface,
                                 hasWash: Bool) -> Color {
        Color(secondaryToken(style: style, appearance: appearance, finish: finish, surface: surface, hasWash: hasWash))
    }

    /// ``secondary(style:appearance:finish:surface:hasWash:)`` as raw sRGB.
    public static func secondaryToken(style: TileFaceStyle, appearance: TileAppearance, finish: TileFinish, surface: TileSurface,
                                      hasWash: Bool) -> HassRGB {
        switch style {
        case .lit: LitTile.secondaryInkToken
        case let .filled(family): family.secondaryInkToken
        case .colored: RoomPalette.inkToken
        case .error: HassRGB(rgb: appearance.errorRGB)
        default:
            if appearance == .light { hasWash ? HassTokens.RGB.Ink.secondary : HassTokens.RGB.Surface.secondaryInSheet }
            else if hasWash { HassTokens.RGB.Surface.secondaryOnWash }
            // A tinted glass ground is a little lighter than the thin module, so its state text takes the denser wallpaper ink.
            else if finish != .solid, surface == .page { HassTokens.RGB.Surface.secondaryOnWallpaper }
            else { HassTokens.RGB.Surface.secondaryOnModule }
        }
    }
}
