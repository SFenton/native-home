import Foundation
@testable import HassDesign
import SwiftUI
import Testing

/// The ink of an action disc per face and state, and the button style's metrics.
@MainActor
struct TileActionInkTests {
    private func rgba(_ color: Color) -> (r: Int, g: Int, b: Int, a: Double) {
        var environment = EnvironmentValues()
        environment.colorScheme = .dark
        let value = color.resolve(in: environment)
        return (Int((Double(value.red) * 255).rounded()), Int((Double(value.green) * 255).rounded()),
                Int((Double(value.blue) * 255).rounded()), Double(value.opacity))
    }

    @Test(arguments: [TileActionFace.dark, .filled])
    func onIsASolidWhiteDiscWithTheFamilyFillAsGlyph(face: TileActionFace) {
        for family in ColorFamily.allCases {
            let ink = TileActionInk.resolve(face: face, isOn: true, family: family)
            #expect(ink.disc == .white)
            #expect(ink.glyph == (family.fill ?? LitTile.ink))
        }
    }

    @Test func aFilledTileRestsOnABlackDiscWithAWhiteGlyph() {
        let ink = TileActionInk.resolve(face: .filled, isOn: false, family: .air)
        #expect(ink.disc == Color.black.opacity(0.18))
        #expect(ink.glyph == .white)
    }

    @Test func theLitTileKeepsItsDarkDiscOnOrOff() {
        for isOn in [false, true] {
            let ink = TileActionInk.resolve(face: .lit, isOn: isOn, family: .lights)
            #expect(ink.disc == LitTile.ink)
            #expect(ink.glyph == .white)
        }
        // White on the near-black disc reads far above 3:1.
        #expect(ChipTint.contrast(0xFFFFFF, 0x1C1C1E) > 12)
    }

    @Test func aDarkTileRestsOnAWhiteSixteenPercentDisc() {
        for family in ColorFamily.allCases {
            let ink = TileActionInk.resolve(face: .dark, isOn: false, family: family)
            #expect(ink.disc == Color.white.opacity(0.16))
            #expect(ink.glyph == (TileActionInk.offGlyphPasses(family) ? family.offGlyph : .white))
        }
        #expect(TileActionInk.resolve(face: .dark, isOn: false, family: nil).glyph == .white, "No family: white")
    }

    @Test(arguments: ColorFamily.allCases)
    func theGlyphOnADarkDiscKeepsThreeToOne(family: ColorFamily) {
        // Measured: the disc (white 16%) composited over the thin module, against the glyph the disc draws.
        let glyph = TileActionInk.resolve(face: .dark, isOn: false, family: family).glyph
        let resolved = rgba(glyph)
        let glyphRGB = UInt32(resolved.r) << 16 | UInt32(resolved.g) << 8 | UInt32(resolved.b)
        #expect(ChipTint.contrast(glyphRGB, TileActionInk.darkDiscRGB) >= TileActionInk.minimumContrast, "\(family)")
    }

    @Test func theDiscRGBIsTheModuleLiftedBySixteenPercentWhite() {
        // 0x1C = 28 -> 28 + (255 - 28) * 0.16 = 64.3
        #expect(TileActionInk.darkDiscRGB == 0x404042 || TileActionInk.darkDiscRGB == 0x404041 || TileActionInk.darkDiscRGB == 0x404040)
    }

    // MARK: Button style metrics

    @Test func theDiscIs44AtTheDefaultAndCapsAt66() {
        #expect(TileActionButtonStyle.diameter(scaled: 44) == 44)
        #expect(TileActionButtonStyle.diameter(scaled: 30) == 44)
        #expect(TileActionButtonStyle.diameter(scaled: 60) == 60)
        #expect(TileActionButtonStyle.diameter(scaled: 140) == 66)
    }

    @Test func theGlyphStaysUnder45PercentOfTheDisc() {
        for scaled in stride(from: 18.0, through: 60.0, by: 6) {
            let circle = TileActionButtonStyle.diameter(scaled: scaled * 44 / 18)
            #expect(TileActionButtonStyle.glyphSize(scaled: scaled, diameter: circle) <= circle * 0.45 + 0.001)
        }
        #expect(TileActionButtonStyle.glyphSize(scaled: 18, diameter: 44) == 18)
    }

    @Test func theStripWidthIsDiscsPlusTwelvePointGaps() {
        #expect(TileActionButtonStyle.stripWidth(count: 0, diameter: 44) == 0)
        #expect(TileActionButtonStyle.stripWidth(count: 1, diameter: 44) == 44)
        #expect(TileActionButtonStyle.stripWidth(count: 2, diameter: 44) == 100)
        #expect(TileActionButtonStyle.stripWidth(count: 3, diameter: 66) == 222)
        #expect(TileActionButtonStyle.gap >= 12)
    }
}
