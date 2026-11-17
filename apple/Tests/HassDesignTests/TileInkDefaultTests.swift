@testable import HassDesign
import Foundation
import Testing

/// The default tile ink (`sh.tile-ink-default@1`, owner pick A, `.agents/patterns/tile-swipe.md`, "Tile ink"): every face by appearance by
/// flag, with and without a family, a tint and an unavailable tile.
struct TileInkDefaultTests {
    private func rgb(_ token: HassRGB, _ appearance: TileAppearance = .dark) -> UInt32 {
        let c = token.components(isDark: appearance == .dark, increasedContrast: false)
        func byte(_ v: Double) -> UInt32 { UInt32((v * 255).rounded()) }
        return byte(c.red) << 16 | byte(c.green) << 8 | byte(c.blue)
    }

    private func glyph(_ style: TileFaceStyle, _ appearance: TileAppearance, family: ColorFamily? = nil, enabled: Bool = true, ink: TileInkDefault,
                       ownTint: Bool = false) -> HassRGB {
        TileFaceInk.glyphToken(style: style, appearance: appearance, finish: .tintedGlass, isEnabled: enabled, family: family, tintGlyph: HassRGB(rgb: 0x30D158),
                               inkDefault: ink, hasOwnTint: ownTint)
    }

    private func state(_ style: TileFaceStyle, _ appearance: TileAppearance, enabled: Bool = true, ink: TileInkDefault) -> HassRGB {
        TileFaceInk.secondaryToken(style: style, appearance: appearance, finish: .tintedGlass, surface: appearance == .light ? .sheet : .page,
                                   hasWash: false, inkDefault: ink, isEnabled: enabled)
    }

    // MARK: A document that does not declare it

    @Test(arguments: [TileAppearance.dark, .light])
    func muteIsTodaysInkForEveryFace(appearance: TileAppearance) {
        #expect(glyph(.tinted, appearance, ink: .muted) == HassRGB(rgb: 0x30D158))
        #expect(glyph(.off, appearance, ink: .muted) == TileFaceInk.mutedToken(appearance: appearance))
        #expect(state(.off, appearance, ink: .muted) == TileFaceInk.secondaryToken(style: .off, appearance: appearance, finish: .tintedGlass,
                                                                                    surface: appearance == .light ? .sheet : .page, hasWash: false))
    }

    // MARK: Primary

    @Test(arguments: [TileAppearance.dark, .light])
    func anIdleIconWithNoFamilyDrawsThePrimaryInk(appearance: TileAppearance) {
        let primary = TileFaceInk.primaryToken(style: .off, appearance: appearance)
        #expect(glyph(.off, appearance, ink: .primary) == primary)
        #expect(glyph(.off, appearance, family: .neutral, ink: .primary) == primary)
        #expect(rgb(primary, appearance) == (appearance == .light ? 0x000000 : 0xFFFFFF), "white on a page and in a dark sheet, black in a light sheet")
    }

    @Test(arguments: [TileAppearance.dark, .light])
    func anIdleIconWithAFamilyKeepsItsTint(appearance: TileAppearance) {
        for family in ColorFamily.allCases where family != .neutral {
            #expect(glyph(.off, appearance, family: family, ink: .primary) == glyph(.off, appearance, family: family, ink: .muted), "\(family)")
        }
    }

    @Test(arguments: [TileAppearance.dark, .light])
    func aTintedFaceWithNoColourOfItsOwnDrawsThePrimaryInk(appearance: TileAppearance) {
        let primary = TileFaceInk.primaryToken(style: .tinted, appearance: appearance)
        #expect(glyph(.tinted, appearance, family: .neutral, ink: .primary) == primary)
        #expect(glyph(.tinted, appearance, ink: .primary) == primary)
        #expect(glyph(.tinted, appearance, family: .neutral, ink: .primary, ownTint: true) == HassRGB(rgb: 0x30D158), "a tint the caller chose still wins")
        #expect(glyph(.tinted, appearance, family: .neutral, ink: .muted) == HassRGB(rgb: 0x30D158))
    }

    @Test(arguments: [TileAppearance.dark, .light])
    func filledAndLitFacesAndTheErrorAndWarningFacesKeepTheirInk(appearance: TileAppearance) {
        let styles: [TileFaceStyle] = [.lit, .filled(.power), .colored(0x336699), .error, .warning]
        for style in styles {
            #expect(glyph(style, appearance, ink: .primary) == glyph(style, appearance, ink: .muted), "\(style) glyph")
        }
        for style in styles where style != .warning {
            #expect(state(style, appearance, ink: .primary) == state(style, appearance, ink: .muted), "\(style) state line")
        }
    }

    @Test(arguments: [TileAppearance.dark, .light])
    func theWarningStateLineDrawsThePrimaryInkAndItsGlyphKeepsTheAmber(appearance: TileAppearance) {
        #expect(state(.warning, appearance, ink: .primary) == TileFaceInk.primaryToken(style: .warning, appearance: appearance))
        #expect(state(.warning, appearance, ink: .muted) == HassRGB(rgb: appearance.warningRGB), "a document without the id draws today's amber")
        #expect(glyph(.warning, appearance, ink: .primary) == HassRGB(rgb: appearance.warningRGB))
    }

    @Test(arguments: [TileAppearance.dark, .light])
    func anUnavailableTileStaysGrey(appearance: TileAppearance) {
        #expect(glyph(.off, appearance, enabled: false, ink: .primary) == TileFaceInk.mutedToken(appearance: appearance))
        #expect(glyph(.tinted, appearance, enabled: false, ink: .primary) == TileFaceInk.mutedToken(appearance: appearance))
        #expect(state(.off, appearance, enabled: false, ink: .primary) == state(.off, appearance, enabled: false, ink: .muted))
    }

    @Test(arguments: [TileAppearance.dark, .light])
    func theStateLineOfAnIdleOrTintedFaceDrawsThePrimaryInk(appearance: TileAppearance) {
        for style in [TileFaceStyle.off, .tinted] {
            #expect(state(style, appearance, ink: .primary) == TileFaceInk.primaryToken(style: style, appearance: appearance))
        }
    }

    // MARK: Contrast

    private func linear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
    private func luminance(_ rgb: UInt32) -> Double {
        0.2126 * linear(Double((rgb >> 16) & 0xFF) / 255) + 0.7152 * linear(Double((rgb >> 8) & 0xFF) / 255) + 0.0722 * linear(Double(rgb & 0xFF) / 255)
    }
    private func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    @Test func thePrimaryStateLineKeepsFourAndAHalfToOneOnTheSheetCells() {
        #expect(contrast(rgb(state(.off, .dark, ink: .primary)), HassTokens.Palette.sheetCell) >= 4.5)
        #expect(contrast(rgb(state(.off, .light, ink: .primary), .light), 0xFFFFFF) >= 4.5)
        #expect(contrast(rgb(glyph(.off, .dark, ink: .primary)), HassTokens.Palette.sheetCell) >= 4.5)
        #expect(contrast(rgb(glyph(.off, .light, ink: .primary), .light), 0xFFFFFF) >= 4.5)
    }

    @Test func thePrimaryInkIsNeverLowerThanTheInkItReplaces() {
        #expect(contrast(rgb(state(.off, .dark, ink: .primary)), HassTokens.Palette.sheetCell)
                >= contrast(rgb(state(.off, .dark, ink: .muted)), HassTokens.Palette.sheetCell))
        #expect(contrast(rgb(glyph(.off, .dark, ink: .primary)), HassTokens.Palette.sheetCell)
                >= contrast(rgb(glyph(.off, .dark, ink: .muted)), HassTokens.Palette.sheetCell))
        #expect(contrast(rgb(glyph(.off, .light, ink: .primary), .light), 0xFFFFFF) >= contrast(rgb(glyph(.off, .light, ink: .muted), .light), 0xFFFFFF))
    }
}
