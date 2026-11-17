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
    ///   - inkDefault: The document's default ink for an icon with no colour of its own (`sh.tile-ink-default@1`).
    ///   - hasOwnTint: Whether the caller chose the tint; a tinted face with none and no family is an icon with no colour of its own.
    public static func glyph(style: TileFaceStyle, appearance: TileAppearance, finish: TileFinish, isEnabled: Bool,
                             family: ColorFamily?, tintGlyph: Color, inkDefault: TileInkDefault = .muted, hasOwnTint: Bool = true) -> Color {
        switch style {
        case .tinted where isEnabled && !usesPrimaryGlyph(inkDefault, family: family, hasOwnTint: hasOwnTint): tintGlyph
        default: Color(glyphToken(style: style, appearance: appearance, finish: finish, isEnabled: isEnabled,
                                  family: family, tintGlyph: HassRGB.white, inkDefault: inkDefault, hasOwnTint: hasOwnTint))
        }
    }

    /// ``glyph(style:appearance:finish:isEnabled:family:tintGlyph:)`` as raw sRGB, for a tint given as raw sRGB.
    public static func glyphToken(style: TileFaceStyle, appearance: TileAppearance, finish: TileFinish, isEnabled: Bool,
                                  family: ColorFamily?, tintGlyph: HassRGB, inkDefault: TileInkDefault = .muted, hasOwnTint: Bool = true) -> HassRGB {
        // An idle icon takes no colour from the caller's tint; a tinted one does, unless the caller chose none.
        let offPrimary = isEnabled && usesPrimaryGlyph(inkDefault, family: family, hasOwnTint: false)
        let tintedPrimary = isEnabled && usesPrimaryGlyph(inkDefault, family: family, hasOwnTint: hasOwnTint)
        switch style {
        case .off:
            if offPrimary { return primaryToken(style: style, appearance: appearance) }
            guard isEnabled, let family else { return mutedToken(appearance: appearance) }
            return finish == .solid ? family.offGlyphToken : HassRGB(rgb: family.offGlyphRGB(appearance.scheme, under: finish))
        case .lit: return LitTile.glyphToken
        case let .filled(family): return family.inkToken
        case .colored: return RoomPalette.inkToken
        case .tinted:
            if tintedPrimary { return primaryToken(style: style, appearance: appearance) }
            return isEnabled ? tintGlyph : mutedToken(appearance: appearance)
        case .error: return HassRGB(rgb: appearance.errorRGB)
        case .warning: return HassRGB(rgb: appearance.warningRGB)
        }
    }

    /// Whether an icon draws the primary ink: the document asked for it, the tile has no family (or the neutral one) and the caller chose no tint.
    /// An authored `glyphTint` is decided before this (`AuthoredTileInk.glyphTintApplies`), so it still wins.
    public static func usesPrimaryGlyph(_ inkDefault: TileInkDefault, family: ColorFamily?, hasOwnTint: Bool) -> Bool {
        inkDefault == .primary && !hasOwnTint && (family == nil || family == .neutral)
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
                                 hasWash: Bool, inkDefault: TileInkDefault = .muted, isEnabled: Bool = true) -> Color {
        Color(secondaryToken(style: style, appearance: appearance, finish: finish, surface: surface, hasWash: hasWash,
                             inkDefault: inkDefault, isEnabled: isEnabled))
    }

    /// ``secondary(style:appearance:finish:surface:hasWash:)`` as raw sRGB.
    ///
    /// With `inkDefault` primary the state line of an idle or tinted face, enabled, is the title's ink (`sh.tile-ink-default@1`). The lit and
    /// filled faces keep their ink and an error its red. A warning's state line is the primary ink too (the glyph keeps the amber, so the state
    /// is still carried by shape and icon, not colour alone); an unavailable tile (`isEnabled` false) keeps the grey.
    public static func secondaryToken(style: TileFaceStyle, appearance: TileAppearance, finish: TileFinish, surface: TileSurface,
                                      hasWash: Bool, inkDefault: TileInkDefault = .muted, isEnabled: Bool = true) -> HassRGB {
        switch style {
        case .lit: LitTile.secondaryInkToken
        case let .filled(family): family.secondaryInkToken
        case .colored: RoomPalette.inkToken
        case .error: HassRGB(rgb: appearance.errorRGB)
        case .warning where inkDefault == .muted || !isEnabled: HassRGB(rgb: appearance.warningRGB)
        default:
            if inkDefault == .primary, isEnabled { primaryToken(style: style, appearance: appearance) }
            else if appearance == .light { hasWash ? HassTokens.RGB.Ink.secondary : HassTokens.RGB.Surface.secondaryInSheet }
            else if hasWash { HassTokens.RGB.Surface.secondaryOnWash }
            // A tinted glass ground is a little lighter than the thin module, so its state text takes the denser wallpaper ink.
            else if finish != .solid, surface == .page { HassTokens.RGB.Surface.secondaryOnWallpaper }
            else { HassTokens.RGB.Surface.secondaryOnModule }
        }
    }
}
