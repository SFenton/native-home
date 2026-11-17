import SwiftUI
@testable import HassDesign
import Testing

// MARK: - The ink a document gives a state tile (`sh.tile-ink@1`)

/// Where the authored icon colour, button icon colour and soft ink apply, and that with none of them every ink is what it always was.
struct AuthoredTileInkTests {
    private let purple = HassRGB(rgb: 0xC18CEE)
    private let plain = HassRGB(rgb: 0x112233)

    // MARK: The icon colour

    @Test func theIconColourAppliesOnTheDarkFacesOnly() {
        for style in [TileFaceStyle.off, .tinted, .warning] {
            #expect(AuthoredTileInk.glyphTintApplies(to: style), "\(style) takes the tint")
            #expect(AuthoredTileInk.glyphToken(style: style, tint: purple, plain: plain) == purple)
        }
        for style in [TileFaceStyle.lit, .filled(.cleaning), .colored(0x785AA0), .error] {
            #expect(!AuthoredTileInk.glyphTintApplies(to: style), "\(style) keeps its own ink")
            #expect(AuthoredTileInk.glyphToken(style: style, tint: purple, plain: plain) == plain)
        }
    }

    @Test func withNoIconColourTheGlyphIsWhatItWas() {
        for style in [TileFaceStyle.off, .tinted, .warning, .lit, .error, .colored(0x785AA0), .filled(.cleaning)] {
            #expect(AuthoredTileInk.glyphToken(style: style, tint: nil, plain: plain) == plain)
        }
    }

    @Test func aPairIsOneAdaptiveTokenAndASingleColourIsFixed() {
        let pair = AppearanceFill(light: 0x8E6DAC, dark: 0xC18CEE).token
        #expect(pair.components(isDark: false, increasedContrast: false) == HassRGB.Components(rgb: 0x8E6DAC))
        #expect(pair.components(isDark: true, increasedContrast: false) == HassRGB.Components(rgb: 0xC18CEE))
        #expect(AppearanceFill(0x8E6DAC).token.isFixed)
    }

    // MARK: The button icon colour

    @Test func theButtonIconColourAppliesToAnOffDiscOnADarkFace() {
        #expect(AuthoredTileInk.discGlyphTintApplies(to: .dark))
        #expect(!AuthoredTileInk.discGlyphTintApplies(to: .filled) && !AuthoredTileInk.discGlyphTintApplies(to: .lit))
        let tinted = TileActionInk.resolveTokens(face: .dark, isOn: false, family: nil, discGlyphTint: purple)
        #expect(tinted.glyph == purple && tinted.disc == HassRGB.white.opacity(TileActionInk.darkDiscOpacity))
    }

    @Test func aFilledFaceAndAnOnDiscKeepTheirInkWhateverTheTint() {
        let filled = TileActionInk.resolveTokens(face: .filled, isOn: false, family: nil, discGlyphTint: purple)
        #expect(filled.glyph == .white && filled.disc == HassRGB.black.opacity(TileActionInk.filledDiscOpacity))
        let lit = TileActionInk.resolveTokens(face: .lit, isOn: false, family: nil, discGlyphTint: purple)
        #expect(lit == TileActionInk.resolveTokens(face: .lit, isOn: false, family: nil))
        let on = TileActionInk.resolveTokens(face: .dark, isOn: true, family: .cleaning, discGlyphTint: purple)
        #expect(on == TileActionInk.resolveTokens(face: .dark, isOn: true, family: .cleaning))
    }

    @Test func withNoButtonColourEveryDiscInkIsWhatItWas() {
        for family in [nil] + ColorFamily.allCases.map(Optional.some) {
            for face in [TileActionFace.dark, .filled, .lit] {
                for isOn in [true, false] {
                    #expect(TileActionInk.resolveTokens(face: face, isOn: isOn, family: family, discGlyphTint: nil)
                            == TileActionInk.resolveTokens(face: face, isOn: isOn, family: family))
                }
            }
        }
        let white = TileActionInk.resolveTokens(face: .dark, isOn: false, family: nil)
        #expect(white.glyph == .white && white.disc == HassRGB.white.opacity(0.16))
    }

    // MARK: The ink of the state line on a fill

    @Test func theSoftInkIsWhiteAt92PercentAndOnlyOnAStyleFill() {
        #expect(AuthoredTileInk.softFillInkOpacity == 0.92)
        let colored = TileFaceStyle.colored(0x785AA0)
        #expect(AuthoredTileInk.stateLineToken(style: colored, softFillInk: true, plain: .white) == HassRGB.white.opacity(0.92))
        #expect(AuthoredTileInk.stateLineToken(style: colored, softFillInk: false, plain: .white) == .white)
        for style in [TileFaceStyle.off, .tinted, .lit, .error, .warning, .filled(.cleaning)] {
            #expect(AuthoredTileInk.stateLineToken(style: style, softFillInk: true, plain: plain) == plain)
        }
    }

    @Test func theSoftInkIsTheOldFamilyFillsSupportingInk() {
        #expect(AuthoredTileInk.stateLineToken(style: .colored(0x785AA0), softFillInk: true, plain: .white) == ColorFamily.cleaning.secondaryInkToken)
    }

    // MARK: The defaults

    @Test func theDefaultStateTileInksArePinned() {
        let appearance = TileAppearance.dark
        // The grey the generic state tile draws for its icon, with no family and a family of neutral.
        let off = TileFaceInk.glyphToken(style: .off, appearance: appearance, finish: .solid, isEnabled: true, family: .neutral, tintGlyph: .white)
        #expect(off == ColorFamily.neutral.offGlyphToken)
        let muted = TileFaceInk.glyphToken(style: .off, appearance: appearance, finish: .solid, isEnabled: false, family: .neutral, tintGlyph: .white)
        #expect(muted == TileFaceInk.mutedToken(appearance: appearance))
        let colored = TileFaceStyle.colored(0x785AA0)
        #expect(TileFaceInk.secondaryToken(style: colored, appearance: appearance, finish: .solid, surface: .page, hasWash: false) == RoomPalette.inkToken)
        #expect(RoomPalette.inkToken == .white)
    }
}
