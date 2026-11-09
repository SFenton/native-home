import SwiftUI
import Testing
@testable import HassDesign

/// The inks of a tile face: one decision per ink on raw sRGB, and the SwiftUI colours are exactly those tokens.
struct TileFaceInkTests {
    static let styles: [TileFaceStyle] = [.off, .lit, .filled(.occupancy), .tinted, .error, .colored(0x3366CC)]

    @Test func theMutedGreyFollowsTheAppearance() {
        #expect(TileFaceInk.mutedToken(appearance: .light) != TileFaceInk.mutedToken(appearance: .dark),
                "the muted grey differs between light and dark (the SwiftUI colour is checked in the hosted probe tests)")
        #expect(TileFaceInk.mutedToken(appearance: .light) == HassTokens.RGB.Surface.secondaryInSheet)
        #expect(TileFaceInk.mutedToken(appearance: .dark) == HassTokens.RGB.Surface.secondaryOnModule)
    }

    @Test(arguments: styles)
    func theTitleColourIsItsTokenAndWhiteOnADarkTile(style: TileFaceStyle) {
        switch style {
        case .off, .tinted, .error:
            #expect(TileFaceInk.primaryToken(style: style, appearance: .dark) == .white)
            #expect(TileFaceInk.primaryToken(style: style, appearance: .light) == HassTokens.RGB.Ink.primary, "dark ink on a light sheet")
        case .lit:
            #expect(TileFaceInk.primaryToken(style: style, appearance: .dark) == LitTile.inkToken, "a lit tile has the same ink in every appearance")
            #expect(TileFaceInk.primaryToken(style: style, appearance: .light) == LitTile.inkToken)
        default: break
        }
    }

    @Test func aTintedFaceKeepsTheCallersTintOnlyWhileItIsEnabled() {
        let tint = Color.orange
        let enabled = TileFaceInk.glyph(style: .tinted, appearance: .dark, finish: .solid, isEnabled: true, family: nil, tintGlyph: tint)
        #expect(enabled == tint)
        let disabled = TileFaceInk.glyph(style: .tinted, appearance: .dark, finish: .solid, isEnabled: false, family: nil, tintGlyph: tint)
        #expect(disabled == TileFaceInk.muted(appearance: .dark), "a disabled tile reads in the muted grey")
        #expect(TileFaceInk.glyphToken(style: .tinted, appearance: .dark, finish: .solid, isEnabled: true, family: nil, tintGlyph: HassRGB(rgb: 0x123456))
                == HassRGB(rgb: 0x123456))
    }

    @Test(arguments: styles)
    func everyOtherGlyphColourIsItsToken(style: TileFaceStyle) {
        for appearance in [TileAppearance.dark, .light] {
            for enabled in [true, false] {
                if case .tinted = style, enabled { continue }
                #expect(TileFaceInk.glyphToken(style: style, appearance: appearance, finish: .solid, isEnabled: enabled,
                                               family: .occupancy, tintGlyph: HassRGB(rgb: 0xFF0000))
                        == TileFaceInk.glyphToken(style: style, appearance: appearance, finish: .solid, isEnabled: enabled,
                                                  family: .occupancy, tintGlyph: .white), "only a tinted, enabled face takes the caller's tint")
            }
        }
    }

    @Test func theOffGlyphTakesTheFamilyTintOrTheMutedGreyWithoutOne() {
        let family = TileFaceInk.glyphToken(style: .off, appearance: .dark, finish: .solid, isEnabled: true, family: .occupancy, tintGlyph: .white)
        #expect(family == ColorFamily.occupancy.offGlyphToken)
        let none = TileFaceInk.glyphToken(style: .off, appearance: .dark, finish: .solid, isEnabled: true, family: nil, tintGlyph: .white)
        #expect(none == TileFaceInk.mutedToken(appearance: .dark))
        let glass = TileFaceInk.glyphToken(style: .off, appearance: .dark, finish: .tintedGlass, isEnabled: true, family: .occupancy, tintGlyph: .white)
        #expect(glass == HassRGB(rgb: ColorFamily.occupancy.offGlyphRGB(.dark, under: .tintedGlass)), "under glass the off glyph is lifted for contrast")
    }

    @Test func theStateLineIsDenserOverAWashAndOnTheLightSheet() {
        func token(_ appearance: TileAppearance, wash: Bool, finish: TileFinish = .solid, surface: TileSurface = .page) -> HassRGB {
            TileFaceInk.secondaryToken(style: .off, appearance: appearance, finish: finish, surface: surface, hasWash: wash)
        }
        #expect(token(.light, wash: true) == HassTokens.RGB.Ink.secondary)
        #expect(token(.light, wash: false) == HassTokens.RGB.Surface.secondaryInSheet)
        #expect(token(.dark, wash: true) == HassTokens.RGB.Surface.secondaryOnWash)
        #expect(token(.dark, wash: false) == HassTokens.RGB.Surface.secondaryOnModule)
        #expect(token(.dark, wash: false, finish: .tintedGlass) == HassTokens.RGB.Surface.secondaryOnWallpaper, "glass on the wallpaper")
        #expect(token(.dark, wash: false, finish: .tintedGlass, surface: .sheet) == HassTokens.RGB.Surface.secondaryOnModule, "not on a sheet")
        #expect(TileFaceInk.secondaryToken(style: .error, appearance: .dark, finish: .solid, surface: .page, hasWash: true)
                == HassRGB(rgb: TileAppearance.dark.errorRGB), "an error face's state is red")
        #expect(TileFaceInk.secondaryToken(style: .lit, appearance: .dark, finish: .solid, surface: .page, hasWash: true) == LitTile.secondaryInkToken)
    }
}
