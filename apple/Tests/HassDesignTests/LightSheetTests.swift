import Foundation
@testable import HassDesign
import SwiftUI
import Testing

/// Sheets follow the system appearance (`.agents/design/direction-g.md`, Layers: Sheets; plan decision 6): the sheet
/// tokens are light and dark pairs, and tiles in a light sheet get a white cell, dark ink and darker glyphs. Contrast
/// is checked on the raw values, text at 4.5:1 and glyphs at 3:1 (WCAG 1.4.3 and 1.4.11), in both appearances.
struct LightSheetTests {
    typealias Palette = HassTokens.Palette

    // MARK: Helpers

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

    /// `a` over `b` at `amount`.
    private func mix(_ a: UInt32, _ b: UInt32, _ amount: Double) -> UInt32 {
        ColorFamily.mix(a, b, amount)
    }

    static let lightGrounds: [UInt32] = [Palette.sheetGroundLight, Palette.sheetCellLight]
    static let darkGrounds: [UInt32] = [Palette.sheetGround, Palette.sheetCell]

    /// The channels a colour resolves to under `scheme`. On the main actor: resolving a dynamic colour hops to the main
    /// queue on macOS, which deadlocks from a test's background thread.
    @MainActor
    private func resolved(_ color: Color, _ scheme: ColorScheme) -> (r: Int, g: Int, b: Int, a: Double) {
        var environment = EnvironmentValues()
        environment.colorScheme = scheme
        let value = color.resolve(in: environment)
        return (Int((Double(value.red) * 255).rounded()), Int((Double(value.green) * 255).rounded()),
                Int((Double(value.blue) * 255).rounded()), Double(value.opacity))
    }

    // MARK: Token pairs

    @MainActor
    @Test func sheetGroundAndCellResolveToThePairsForEachScheme() {
        let light = resolved(HassTokens.Surface.sheetGround, .light)
        #expect((light.r, light.g, light.b) == (0xF2, 0xF2, 0xF7))
        let dark = resolved(HassTokens.Surface.sheetGround, .dark)
        #expect((dark.r, dark.g, dark.b) == (0x1C, 0x1C, 0x1E))
        let lightCell = resolved(HassTokens.Surface.sheetCell, .light)
        #expect((lightCell.r, lightCell.g, lightCell.b) == (0xFF, 0xFF, 0xFF))
        let darkCell = resolved(HassTokens.Surface.sheetCell, .dark)
        #expect((darkCell.r, darkCell.g, darkCell.b) == (0x2C, 0x2C, 0x2E))
    }

    @MainActor
    @Test func separatorIsTheSystemHairlineInLightAndWhiteInDark() {
        let light = resolved(HassTokens.Surface.separator, .light)
        #expect((light.r, light.g, light.b) == (0x3C, 0x3C, 0x43))
        #expect(abs(light.a - 0.29) < 0.01)
        let dark = resolved(HassTokens.Surface.separator, .dark)
        #expect((dark.r, dark.g, dark.b) == (255, 255, 255))
        #expect(abs(dark.a - 0.14) < 0.01)
    }

    @MainActor
    @Test func secondaryInSheetResolvesPerScheme() {
        let light = resolved(HassTokens.Surface.secondaryInSheet, .light)
        #expect((light.r, light.g, light.b) == (0x3C, 0x3C, 0x43))
        #expect(abs(light.a - Palette.secondaryInSheetLightOpacity) < 0.01)
        let dark = resolved(HassTokens.Surface.secondaryInSheet, .dark)
        #expect((dark.r, dark.g, dark.b) == (0xEB, 0xEB, 0xF5))
        #expect(abs(dark.a - Palette.secondaryInSheetDarkOpacity) < 0.01)
    }

    @MainActor
    @Test func inkActionAndSuccessFollowTheScheme() {
        let action = resolved(HassTokens.Ink.action, .light)
        #expect((action.r, action.g, action.b) == (0x00, 0x66, 0xCC))
        let darkAction = resolved(HassTokens.Ink.action, .dark)
        #expect((darkAction.r, darkAction.g, darkAction.b) == (0x40, 0x9C, 0xFF))
        let success = resolved(HassTokens.Ink.success, .light)
        #expect((success.r, success.g, success.b) == (0x1E, 0x7B, 0x34))
        let darkSuccess = resolved(HassTokens.Ink.success, .dark)
        #expect((darkSuccess.r, darkSuccess.g, darkSuccess.b) == (0x30, 0xD1, 0x58))
    }

    // MARK: Contrast, light

    @Test(arguments: LightSheetTests.lightGrounds)
    func lightTextTokensReadOnLightGrounds(_ ground: UInt32) {
        #expect(contrast(Palette.tintTextLight, ground) >= 4.5, "tint")
        #expect(contrast(Palette.redLight, ground) >= 4.5, "red")
        #expect(contrast(Palette.orangeLight, ground) >= 4.5, "orange")
        #expect(contrast(Palette.successLight, ground) >= 4.5, "success")
        let secondary = mix(Palette.secondaryLabelLight, ground, Palette.secondaryInSheetLightOpacity)
        #expect(contrast(secondary, ground) >= 4.5, "secondary in a sheet")
    }

    @Test func systemSecondaryLabelIsTooFaintOnWhite() {
        // Why the light secondary ink is 76%, not the system's 60%.
        let system = mix(Palette.secondaryLabelLight, Palette.sheetCellLight, 0.6)
        #expect(contrast(system, Palette.sheetCellLight) < 4.5)
    }

    @Test(arguments: LightSheetTests.darkGrounds)
    func darkSecondaryInSheetReadsOnDarkGrounds(_ ground: UInt32) {
        let secondary = mix(Palette.secondaryLabel, ground, Palette.secondaryInSheetDarkOpacity)
        #expect(contrast(secondary, ground) >= 4.5)
    }

    @Test(arguments: LightSheetTests.lightGrounds)
    func separatorShowsOnLightGroundsAndCells(_ ground: UInt32) {
        // A hairline is decoration (no contrast rule), but it must still register against the cell.
        let line = mix(Palette.secondaryLabelLight, ground, Palette.separatorLightOpacity)
        #expect(contrast(line, ground) > 1.3)
    }

    @Test(arguments: ColorFamily.allCases)
    func lightGlyphsReachNonTextContrastOnWhiteAndTheGround(_ family: ColorFamily) {
        for ground in Self.lightGrounds {
            #expect(contrast(family.glyphLightRGB, ground) >= 3, "\(family) glyph")
            #expect(contrast(family.offGlyphRGB(.light), ground) >= 3, "\(family) off glyph")
        }
    }

    @Test(arguments: ColorFamily.allCases)
    func darkGlyphsKeepNonTextContrastOnTheDarkCell(_ family: ColorFamily) {
        #expect(contrast(family.glyphRGB(.dark), Palette.sheetCell) >= 3, "\(family) glyph")
        #expect(family.glyphRGB(.dark) == family.spec.glyph)
        #expect(family.offGlyphRGB(.dark) == ColorFamily.mix(family.spec.glyph, 0x8E8E93, 0.72))
    }

    @Test(arguments: ColorFamily.allCases)
    func lightGlyphKeepsTheFamilyHue(_ family: ColorFamily) {
        // Darkened, not recoloured: each channel is at or below the dark glyph's, give or take rounding.
        func channels(_ rgb: UInt32) -> [Int] { [Int((rgb >> 16) & 0xFF), Int((rgb >> 8) & 0xFF), Int(rgb & 0xFF)] }
        guard family != .neutral else { return }
        let light = channels(family.glyphLightRGB), dark = channels(family.spec.glyph)
        #expect(zip(light, dark).allSatisfy { $0 <= $1 + 2 }, "\(family)")
    }

    @Test func errorTextAndGlyphReadOnAWhiteCellAndOnADarkOne() {
        #expect(contrast(TileAppearance.light.errorRGB, Palette.sheetCellLight) >= 4.5)
        #expect(contrast(TileAppearance.dark.errorRGB, Palette.sheetCell) >= 4.5)
    }

    /// Washes as light tiles draw them (their colour at 22% over the white cell): the secondary ink keeps 4.5:1.
    @Test(arguments: [0x1565C0, 0xC62828, 0x7B1FA2, 0x2A732E, 0xA8420E, 0x076C91] as [UInt32])
    func secondaryInkReadsUnderALightWash(_ color: UInt32) {
        let ground = mix(color, Palette.sheetCellLight, TileAppearance.light.washOpacity)
        // Under a wash the secondary ink is the label colour at 72% (`Ink.secondary`); the sheet's 76% grey is not enough.
        let ink = mix(0x000000, ground, 0.72)
        #expect(contrast(ink, ground) >= 4.5)
        #expect(contrast(0x000000, ground) >= 4.5, "title")
    }

    @Test func alarmTriggeredWashLeavesSheetInkReadable() {
        // The Security sheet's triggered card: the alarm fill at 16% over a white cell.
        let ground = mix(0xD70015, Palette.sheetCellLight, 0.16)
        let ink = mix(0x000000, ground, 0.72)
        #expect(contrast(ink, ground) >= 4.5)
    }

    @Test func fixedFillsAndTheLitTileKeepTheirInksOnALightCell() {
        // The filled family tiles and the lit tile do not follow the appearance: same fills, same ink.
        for family in ColorFamily.allCases {
            guard let fill = family.spec.fill else { continue }
            let ink: UInt32 = family.spec.darkInk ? 0x1C1C1E : 0xFFFFFF
            #expect(contrast(ink, fill) >= 4.5, "\(family)")
        }
        #expect(contrast(0x1C1C1E, 0xEADBC4) >= 4.5, "lit tile ink on its base")
    }

    @Test func successIsOnlyReadableOnLightWithTheDeeperGreen() {
        #expect(contrast(0x30D158, Palette.sheetCellLight) < 3)
        #expect(contrast(Palette.successLight, Palette.sheetCellLight) >= 4.5)
        #expect(contrast(Palette.success, Palette.sheetCell) >= 4.5)
    }

    // MARK: Tile appearance

    @Test func onlyASheetUnderTheLightSchemeDrawsALightTile() {
        #expect(TileAppearance.resolve(surface: .sheet, scheme: .light) == .light)
        #expect(TileAppearance.resolve(surface: .sheet, scheme: .dark) == .dark)
        // A page is always dark, whatever the scheme the environment reports.
        #expect(TileAppearance.resolve(surface: .page, scheme: .light) == .dark)
        #expect(TileAppearance.resolve(surface: .page, scheme: .dark) == .dark)
    }

    @Test func tileAppearanceColoursMatchTheTokens() {
        #expect(TileAppearance.light.scheme == .light)
        #expect(TileAppearance.dark.scheme == .dark)
        #expect(TileAppearance.light.errorRGB == Palette.redLight)
        #expect(TileAppearance.dark.errorRGB == Palette.red)
        #expect(TileAppearance.dark.washOpacity == 0.6)
        #expect(TileAppearance.light.washOpacity < TileAppearance.dark.washOpacity)
    }

    @Test(arguments: [[0.0, 0.8, 0.8], [1.0, 0.85, 0.0], [0.45, 0.78, 1.0], [0.26, 0.63, 0.28]])
    func aTintBecomesAGlyphThatReachesThreeToOneOnTheSheetGround(_ tint: [Double]) {
        let shaded = TileFaceStyle.lightGlyph(forTint: (tint[0], tint[1], tint[2]))
        func byte(_ v: Double) -> UInt32 { UInt32((v * 255).rounded()) }
        let rgb = byte(shaded.red) << 16 | byte(shaded.green) << 8 | byte(shaded.blue)
        #expect(contrast(rgb, Palette.sheetGroundLight) >= 3)
        #expect(contrast(rgb, Palette.sheetCellLight) >= 3)
    }

    @Test func aTintThatAlreadyReadsIsLeftAlone() {
        let tint = (red: 0.0, green: 0.2, blue: 0.5)
        let shaded = TileFaceStyle.lightGlyph(forTint: tint)
        #expect(shaded.red == tint.red && shaded.green == tint.green && shaded.blue == tint.blue)
    }

    // MARK: System appearance

    @Test func theLaunchOverrideWinsThenTheSystemThenDark() {
        #expect(SystemAppearance.resolve(override: "light", system: .dark) == .light)
        #expect(SystemAppearance.resolve(override: "Dark", system: .light) == .dark)
        #expect(SystemAppearance.resolve(override: nil, system: .light) == .light)
        #expect(SystemAppearance.resolve(override: "", system: .dark) == .dark)
        #expect(SystemAppearance.resolve(override: "sepia", system: .light) == .light)
        // Before a scene exists the shell's own scheme.
        #expect(SystemAppearance.resolve(override: nil, system: nil) == .dark)
    }
}
