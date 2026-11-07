import Foundation
@testable import HassDesign
import SwiftUI
import Testing

/// Direction G's palette against WCAG 1.4.3 (text 4.5:1) on the grounds it is drawn on.
struct HassTokensTests {
    typealias Palette = HassTokens.Palette

    private func luminance(_ rgb: UInt32) -> Double {
        func linear(_ shift: UInt32) -> Double {
            let c = Double((rgb >> shift) & 0xFF) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(16) + 0.7152 * linear(8) + 0.0722 * linear(0)
    }

    private func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// The darkest and lightest grounds G text sits on: sheet ground, sheet cells, and the dense module.
    private static let darkGrounds: [UInt32] = [Palette.sheetGround, Palette.sheetCell, Palette.moduleDense]

    @Test(arguments: darkGrounds)
    func tintRedAndOrangeReadOnDarkGrounds(_ ground: UInt32) {
        #expect(contrast(Palette.tintText, ground) >= 4.5, "tint")
        #expect(contrast(Palette.red, ground) >= 4.5, "red")
        #expect(contrast(Palette.orange, ground) >= 4.5, "orange")
    }

    @Test func whiteLabelsReadOnFilledTintAndBadge() {
        #expect(contrast(0xFFFFFF, Palette.tintFill) >= 4.5)
        #expect(contrast(0xFFFFFF, Palette.badge) >= 4.5)
    }

    @Test func systemBlueFailsWhereTheLiftedTintPasses() {
        // Why G lifts the tint: system blue as small text on a sheet cell is below 4.5:1.
        #expect(contrast(0x0A84FF, Palette.sheetCell) < 4.5)
        #expect(contrast(Palette.tintText, Palette.sheetCell) >= 4.5)
    }

    /// `a` over `b` at `amount`.
    private func mix(_ a: UInt32, _ b: UInt32, _ amount: Double) -> UInt32 {
        func channel(_ shift: UInt32) -> UInt32 {
            let ca = Double((a >> shift) & 0xFF), cb = Double((b >> shift) & 0xFF)
            return UInt32((ca * amount + cb * (1 - amount)).rounded()) << shift
        }
        return channel(16) | channel(8) | channel(0)
    }

    /// The brightest ground under a page tile: a white sky under the backdrop's lightest scrim (black at 40%), then
    /// the thin module (#1C1C1E at 66%).
    private var brightModule: UInt32 { mix(Palette.moduleThin, mix(0x000000, 0xFFFFFF, 0.40), 0.66) }

    @Test func secondaryInkReadsOnTheBrightestModule() {
        let ink = mix(Palette.secondaryLabel, brightModule, HassTokens.Surface.secondaryOnModuleOpacity)
        #expect(contrast(ink, brightModule) >= 4.5)
    }

    /// Washes as tiles draw them (their colour at 45-50%, at 60% over the ground): the security, room and food
    /// colours. The 68% ink measured 4.3:1 on the folded Duo's Armed Home tile; the wash ink keeps 4.5:1.
    @Test(arguments: [0x1565C0, 0xC62828, 0x7B1FA2, 0x2A732E, 0xA8420E, 0x076C91] as [UInt32])
    func secondaryInkReadsUnderAWash(_ color: UInt32) {
        let ground = mix(color, brightModule, 0.5 * 0.6)
        let ink = mix(Palette.secondaryLabel, ground, HassTokens.Surface.secondaryOnWashOpacity)
        #expect(contrast(ink, ground) >= 4.5)
        let old = mix(Palette.secondaryLabel, ground, HassTokens.Surface.secondaryOnModuleOpacity)
        #expect(contrast(old, ground) < contrast(ink, ground))
    }

    /// A titled spinner straight on the wallpaper has no module under its label. The photo's brightest part under the
    /// scrim (about `#53565F`) gave the system's 60% secondary 3.1:1 live; the wallpaper ink keeps 4.5:1 there.
    @Test func secondaryInkReadsStraightOnTheWallpaper() {
        let brightWallpaper: UInt32 = 0x53565F
        let ink = mix(Palette.secondaryLabel, brightWallpaper, HassTokens.Surface.secondaryOnWallpaperOpacity)
        #expect(contrast(ink, brightWallpaper) >= 4.5)
        let system = mix(Palette.secondaryLabel, brightWallpaper, 0.6)
        #expect(contrast(system, brightWallpaper) < 4.5, "The 60% system secondary is what failed")
        #expect(HassTokens.Surface.secondaryOnWallpaperOpacity > HassTokens.Surface.secondaryOnModuleOpacity)
    }

    /// The state, wash and weight tokens that replaced per-view literals keep their values.
    @Test func controlStateWashAndTypographyTokens() {
        #expect(HassTokens.ControlState.disabledOpacity == 0.4)
        #expect(HassTokens.ControlState.pressedOpacity == 0.8)
        #expect(HassTokens.Wash.alert == 0.14)
        #expect(HassTokens.Wash.notice == 0.16)
        #expect(HassTokens.Typography.sectionTitle == Font.title3.bold(), "bold is the one section-header weight")
        #expect(HassTokens.Typography.tileTitle == Font.subheadline.bold())
        #expect(HassTokens.Typography.rowTitle == Font.subheadline.weight(.semibold))
        #expect(HassTokens.Typography.bodyEmphasis == Font.body.weight(.semibold))
        #expect(HassTokens.Typography.footnoteEmphasis == Font.footnote.weight(.semibold))
        #expect(HassTokens.Typography.captionEmphasis == Font.caption.weight(.semibold))
        #expect(HassTokens.Ink.onFamilyFill == Color(rgb: Palette.sheetGround))
        #expect(HassTokens.Palette.activeControlFill == 0xF2F2F7)
    }

    @Test func radiiMatchDirectionG() {
        #expect(HassTokens.Radius.tile == 22)
        #expect(HassTokens.Radius.module == 26)
    }
}
