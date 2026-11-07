import Foundation
@testable import HassDesign
import SwiftUI
import Testing

struct ColorFamilyTests {
    /// WCAG relative luminance of `0xRRGGBB`.
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

    @Test(arguments: ColorFamily.allCases)
    func inkOnFillPassesBodyContrast(_ family: ColorFamily) {
        guard let fill = family.spec.fill else { return }
        let ink: UInt32 = family.spec.darkInk ? 0x1C1C1E : 0xFFFFFF
        // Supporting text is white at 92% (or dark olive at 82%) over the fill.
        let secondary = family.spec.darkInk
            ? ColorFamily.mix(0x282000, fill, 0.82)
            : ColorFamily.mix(0xFFFFFF, fill, 0.92)
        #expect(contrast(ink, fill) >= 4.5, "\(family) title")
        #expect(contrast(secondary, fill) >= 4.5, "\(family) subtitle")
    }

    @Test(arguments: ColorFamily.allCases)
    func inkStillPassesOnTheProgressBand(_ family: ColorFamily) {
        guard let fill = family.spec.fill else { return }
        if family.spec.darkInk {
            let band = ColorFamily.mix(0xFFFFFF, fill, TileFaceStyle.progressLighten)
            #expect(contrast(0x1C1C1E, band) >= 4.5, "\(family) title on the band")
        } else {
            let shaded = ColorFamily.mix(0x000000, fill, TileFaceStyle.progressShade)
            #expect(contrast(ColorFamily.mix(0xFFFFFF, shaded, 0.92), shaded) >= 4.5, "\(family) state past the band")
            // The band itself is the plain fill, which inkOnFillPassesBodyContrast covers.
        }
    }

    @Test(arguments: ColorFamily.allCases)
    func glyphIsVisibleOnASheetTile(_ family: ColorFamily) {
        // Non-text contrast (WCAG 1.4.11) against the sheet's tile colour, #2C2C2E.
        #expect(contrast(family.spec.glyph, 0x2C2C2E) >= 3, "\(family)")
    }

    @Test(arguments: [0x0000FF, 0xFF0000, 0x00FF00, 0x8000FF, 0xFF00FF] as [UInt32])
    func litTileStatusReadsUnderAnyBulbColour(_ bulb: UInt32) {
        // The band's darker end, tinted by a saturated bulb, under the status text ("41%").
        let band = ColorFamily.mix(bulb, 0xFFE2B2, LitTile.bulbTint)
        let status = ColorFamily.mix(0x1C1C1E, band, LitTile.secondaryInkOpacity)
        #expect(contrast(status, band) >= 4.5, "bulb \(String(bulb, radix: 16))")
    }

    @Test func onlyLightsAndNeutralAreNeverFilled() {
        let unfilled = ColorFamily.allCases.filter { $0.spec.fill == nil }
        #expect(Set(unfilled) == [.lights, .neutral])
    }

    @Test(arguments: ColorFamily.allCases)
    func chipTextAndGlyphReadOnTheChipFill(_ family: ColorFamily) {
        guard let fill = family.chipFillRGB else { return }
        // Power's chip would need dark ink; no status chip uses it.
        guard family != .power else { return }
        // Text can sit under the chip's 12% white top highlight (`StatusChipStyle`), so measure against that too.
        let lifted = ColorFamily.mix(0xFFFFFF, fill, 0.12)
        for ground in [fill, lifted] {
            #expect(contrast(0xFFFFFF, ground) >= 4.5, "\(family) title and state")
        }
        #expect(contrast(family.chipGlyphRGB, fill) >= 3, "\(family) glyph")
    }

    /// OKLab coordinates of `0xRRGGBB`, for perceptual distance.
    private func oklab(_ rgb: UInt32) -> (Double, Double, Double) {
        func linear(_ shift: UInt32) -> Double {
            let c = Double((rgb >> shift) & 0xFF) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        let (r, g, b) = (linear(16), linear(8), linear(0))
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        return (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
    }

    private func oklabDistance(_ a: UInt32, _ b: UInt32) -> Double {
        let (x, y) = (oklab(a), oklab(b))
        return ((x.0 - y.0) * (x.0 - y.0) + (x.1 - y.1) * (x.1 - y.1) + (x.2 - y.2) * (x.2 - y.2)).squareRoot()
    }

    /// Owner, 2026-10-16: the Chores quick-link tiles use colours no device family, security mode, Food tile or room
    /// reuses. The floor is an OKLab distance of 0.05 between fills, the one the room palette keeps (the closest existing
    /// pair, heating and cooking, is 0.002 apart).
    @Test(arguments: ColorFamily.choreFamilies)
    func choreTilesUseColoursNothingElseDoes(_ family: ColorFamily) throws {
        let fill = try #require(family.spec.fill)
        for other in ColorFamily.allCases where other != family {
            guard let otherFill = other.spec.fill else { continue }
            #expect(oklabDistance(fill, otherFill) >= 0.05, "\(family) vs \(other)")
        }
        for (room, roomFill) in RoomPalette.fills.enumerated() {
            #expect(oklabDistance(fill, roomFill) >= 0.05, "\(family) vs \(room)")
        }
    }

    /// Distance between two `0xRRGGBB` colours in sRGB.
    private func distance(_ a: UInt32, _ b: UInt32) -> Double {
        func channel(_ rgb: UInt32, _ shift: UInt32) -> Double { Double((rgb >> shift) & 0xFF) }
        return [16, 8, 0].map { pow(channel(a, $0) - channel(b, $0), 2) }.reduce(0, +).squareRoot()
    }

    @Test func foodTilesAreFilledAndTellTheSpacesApart() throws {
        // Owner, 2026-10-16: Food Spaces and All Food take the web's colours. Each is a filled family; All Recipes shares the
        // Fridge's blue, as on the web, and nothing else repeats.
        let spaces: [ColorFamily] = [.pantry, .fridge, .freezer, .spiceRack, .cabinet, .food]
        for family in spaces + [.recipes] {
            let fill = try #require(family.spec.fill, "\(family)")
            #expect(!family.spec.darkInk, "\(family) takes white ink")
            #expect(family.chipFillRGB == fill)
        }
        #expect(ColorFamily.recipes.spec == ColorFamily.fridge.spec)
        for (index, first) in spaces.enumerated() {
            for second in spaces[(index + 1)...] {
                let a = try #require(first.spec.fill), b = try #require(second.spec.fill)
                #expect(distance(a, b) >= 30, "\(first) and \(second)")
            }
        }
    }

    @Test func alarmStatesPickTheirSecurityFamily() {
        #expect(ColorFamily.security(alarmState: "armed_home") == .securityHome)
        #expect(ColorFamily.security(alarmState: "armed_away") == .securityAway)
        #expect(ColorFamily.security(alarmState: "armed_night") == .securityNight)
        #expect(ColorFamily.security(alarmState: "disarmed") == .securityDisarmed)
        #expect(ColorFamily.security(alarmState: "triggered") == .securityTriggered)
        #expect(ColorFamily.security(alarmState: "arming") == nil)
        #expect(ColorFamily.security(alarmState: nil) == nil)
    }

    @Test func mixBlendsEachChannel() {
        #expect(ColorFamily.mix(0xFFFFFF, 0x000000, 1) == 0xFFFFFF)
        #expect(ColorFamily.mix(0xFFFFFF, 0x000000, 0) == 0x000000)
        #expect(ColorFamily.mix(0xFF0000, 0x0000FF, 0.5) == 0x800080)
    }
}
