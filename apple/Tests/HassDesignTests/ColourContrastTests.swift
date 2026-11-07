import Foundation
@testable import HassDesign
import SwiftUI
import Testing

/// The colour and contrast decisions (`.agents/design/mockups/proposals/colour-contrast`, decided 2026-10-24): the tokens
/// that replaced system greens, oranges and grays, the unavailable gray, and the control track. Contrast is computed on the
/// raw values over their real backgrounds (sheet ground and cell in both appearances, the thin module over a mid wallpaper
/// patch), 4.5:1 for text and 3:1 for glyphs and control boundaries (WCAG 1.4.3 and 1.4.11).
struct ColourContrastTests {
    typealias Palette = HassTokens.Palette

    // MARK: Helpers

    private func linear(_ channel: Double) -> Double {
        channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
    }

    private func luminance(_ rgb: (Double, Double, Double)) -> Double {
        0.2126 * linear(rgb.0) + 0.7152 * linear(rgb.1) + 0.0722 * linear(rgb.2)
    }

    private func rgb(_ value: UInt32) -> (Double, Double, Double) {
        (Double((value >> 16) & 0xFF) / 255, Double((value >> 8) & 0xFF) / 255, Double(value & 0xFF) / 255)
    }

    /// `top` at `alpha` over `bottom`, unrounded.
    private func blend(_ top: UInt32, _ alpha: Double, over bottom: UInt32) -> (Double, Double, Double) {
        let (t, b) = (rgb(top), rgb(bottom))
        return (t.0 * alpha + b.0 * (1 - alpha), t.1 * alpha + b.1 * (1 - alpha), t.2 * alpha + b.2 * (1 - alpha))
    }

    private func contrast(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double {
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    private func contrast(_ a: UInt32, _ b: UInt32) -> Double { contrast(rgb(a), rgb(b)) }

    @MainActor
    private func resolved(_ color: Color, _ scheme: ColorScheme) -> (r: Int, g: Int, b: Int, a: Double) {
        var environment = EnvironmentValues()
        environment.colorScheme = scheme
        let value = color.resolve(in: environment)
        return (Int((Double(value.red) * 255).rounded()), Int((Double(value.green) * 255).rounded()),
                Int((Double(value.blue) * 255).rounded()), Double(value.opacity))
    }

    /// The thin module over a mid-dark wallpaper patch.
    private var moduleOverWallpaper: (Double, Double, Double) { blend(Palette.moduleThin, 0.66, over: 0x404040) }

    // MARK: Unavailable gray

    @MainActor
    @Test func theUnavailableInkResolvesPerAppearance() {
        let light = resolved(HassTokens.Ink.unavailable, .light)
        #expect((light.r, light.g, light.b) == (0x63, 0x63, 0x66))
        let dark = resolved(HassTokens.Ink.unavailable, .dark)
        #expect((dark.r, dark.g, dark.b) == (0x8E, 0x8E, 0x93))
    }

    @MainActor
    @Test func everyUnavailableGrayUsesTheToken() {
        #expect(resolved(StatusPill.color(.unavailable), .light) == resolved(HassTokens.Ink.unavailable, .light))
        #expect(resolved(StatusPill.color(.unavailable), .dark) == resolved(HassTokens.Ink.unavailable, .dark))
    }

    @Test func theUnavailableGrayHoldsTextContrastOnItsGrounds() {
        for ground in [Palette.sheetGroundLight, Palette.sheetCellLight] {
            #expect(contrast(Palette.unavailableLight, ground) >= 4.5, "light \(String(ground, radix: 16))")
        }
        #expect(contrast(rgb(Palette.unavailable), blend(Palette.sheetGround, 1, over: 0)) >= 4.5, "dark sheet ground")
        #expect(contrast(rgb(Palette.unavailable), moduleOverWallpaper) >= 4.5, "dark module")
        // On the sheet cell (#2C2C2E) it is a glyph, which needs 3:1.
        #expect(contrast(Palette.unavailable, Palette.sheetCell) >= 3)
    }

    // MARK: Section A tokens

    @Test func successWarningAndDangerGlyphsHold3To1OnALightSheet() {
        for ground in [Palette.sheetGroundLight, Palette.sheetCellLight] {
            #expect(contrast(Palette.successLight, ground) >= 4.5)
            #expect(contrast(Palette.orangeLight, ground) >= 4.5)
            #expect(contrast(Palette.redLight, ground) >= 4.5)
        }
        for ground in [Palette.sheetGround, Palette.sheetCell] {
            #expect(contrast(Palette.success, ground) >= 4.5)
            #expect(contrast(Palette.orange, ground) >= 4.5)
            #expect(contrast(Palette.red, ground) >= 4.5)
        }
    }

    @Test func theSuccessGlyphHoldsOnItsOwnNoticeWash() {
        let wash = HassTokens.Wash.notice
        let light = blend(Palette.successLight, wash, over: Palette.sheetCellLight)
        #expect(contrast(rgb(Palette.successLight), light) >= 4.2, "light: 4.28, a glyph needs 3")
        let dark = blend(Palette.success, wash, over: Palette.sheetCell)
        #expect(contrast(rgb(Palette.success), dark) >= 4.5, "dark")
    }

    @Test func theUnselectedOptionGlyphHoldsOnALightSheet() {
        let ink = (Palette.secondaryLabelLight, Palette.secondaryInSheetLightOpacity)
        for ground in [Palette.sheetGroundLight, Palette.sheetCellLight] {
            #expect(contrast(blend(ink.0, ink.1, over: ground), rgb(ground)) >= 4.5)
        }
    }

    @Test func thePowerGlyphReadsOnItsSuccessDisc() {
        #expect(contrast(0xFFFFFF, Palette.successLight) >= 4.5, "white on the light disc")
        #expect(contrast(Palette.sheetGround, Palette.success) >= 4.5, "dark on the dark disc")
    }

    @MainActor
    @Test func theGlyphOnTheSuccessDiscFlipsWithAppearance() {
        let light = resolved(HassTokens.Ink.onSuccessFill, .light)
        #expect((light.r, light.g, light.b) == (255, 255, 255))
        let dark = resolved(HassTokens.Ink.onSuccessFill, .dark)
        #expect((dark.r, dark.g, dark.b) == (0x1C, 0x1C, 0x1E))
    }

    // MARK: Control track

    /// The label colour is black in light and white in dark.
    @Test func theTrackClearsThreeToOneOnTheGroundsADialSitsOn() {
        // Light: the sheet cell is white and the ground #F2F2F7; 43% is 3.09:1 on the ground (42% was 2.99).
        #expect(contrast(blend(0x000000, HassTokens.Palette.trackOpacity, over: Palette.sheetCellLight), rgb(Palette.sheetCellLight)) >= 3.0)
        #expect(contrast(blend(0x000000, HassTokens.Palette.trackOpacity, over: Palette.sheetGroundLight), rgb(Palette.sheetGroundLight)) >= 3.0)
        // Dark: sheet ground, sheet cell, the thin module and a pure black page patch.
        for ground in [Palette.sheetGround, Palette.sheetCell, 0x000000] as [UInt32] {
            #expect(contrast(blend(0xFFFFFF, HassTokens.Palette.trackOpacity, over: ground), rgb(ground)) >= 3.0, "dark \(String(ground, radix: 16))")
        }
        let module = moduleOverWallpaper
        let track = (module.0 + (1 - module.0) * HassTokens.Palette.trackOpacity, module.1 + (1 - module.1) * HassTokens.Palette.trackOpacity, module.2 + (1 - module.2) * HassTokens.Palette.trackOpacity)
        #expect(contrast(track, module) >= 3.0, "dark module")
    }

    @Test func increaseContrastRaisesTheTrackWellPastThree() {
        #expect(HassTokens.Palette.trackOpacityIncreased > HassTokens.Palette.trackOpacity)
        for ground in [Palette.sheetGroundLight, Palette.sheetCellLight] {
            #expect(contrast(blend(0x000000, HassTokens.Palette.trackOpacityIncreased, over: ground), rgb(ground)) >= 5)
        }
        for ground in [Palette.sheetGround, Palette.sheetCell] {
            #expect(contrast(blend(0xFFFFFF, HassTokens.Palette.trackOpacityIncreased, over: ground), rgb(ground)) >= 5)
        }
    }

    @Test func theTrackTokenStepsUpWithIncreaseContrast() {
        #expect(HassTokens.Ink.track(increasedContrast: true) != HassTokens.Ink.track(increasedContrast: false))
        #expect(HassTokens.Palette.trackOpacity == 0.43 && HassTokens.Palette.trackOpacityIncreased == 0.60)
    }
}
