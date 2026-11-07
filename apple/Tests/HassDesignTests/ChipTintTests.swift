import Foundation
@testable import HassDesign
import Testing

/// The computed chip tints keep white text at 4.5:1 and the glyph at 3:1, whatever colour Home Assistant supplies.
struct ChipTintTests {
    /// Every `0xRRGGBB` the web's temperature gradient draws, a degree at a time from below its first stop to past its last.
    private static let temperatureColours: [UInt32] = (40...95).map { degrees in
        func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
        let stops: [(Double, (Double, Double, Double))] = [
            (50, (0, 110, 255)), (60, (128, 0, 255)), (68, (0, 200, 120)),
            (74, (255, 215, 0)), (80, (255, 165, 0)), (85, (255, 0, 0)),
        ]
        let value = min(max(Double(degrees), 50), 85)
        let index = stops.indices.dropLast().first { value <= stops[$0 + 1].0 } ?? stops.count - 2
        let (a, b) = (stops[index], stops[index + 1])
        let t = (value - a.0) / (b.0 - a.0)
        let r = UInt32(lerp(a.1.0, b.1.0, t).rounded()), g = UInt32(lerp(a.1.1, b.1.1, t).rounded())
        let blue = UInt32(lerp(a.1.2, b.1.2, t).rounded())
        return r << 16 | g << 8 | blue
    }

    /// Colours an AQI helper might hold: the web teal, EPA-style bands, and extremes.
    private static let airColours: [UInt32] = [
        0x009688, 0x00E400, 0xFFFF00, 0xFF7E00, 0xFF0000, 0x8F3F97, 0x7E0023, 0xFFFFFF, 0x000000, 0x808080,
    ]

    private func assertReads(_ tint: ChipTint, _ label: String) {
        #expect(ChipTint.contrast(0xFFFFFF, tint.fill) >= 4.5, "\(label) text on the fill")
        #expect(ChipTint.contrast(0xFFFFFF, tint.liftedFill) >= 4.5, "\(label) text under the top highlight")
        #expect(ChipTint.contrast(tint.glyph, tint.fill) >= 3, "\(label) glyph on the fill")
        #expect(ChipTint.contrast(tint.glyph, tint.liftedFill) >= 3, "\(label) glyph under the highlight")
    }

    @Test func everyContactTintReads() {
        assertReads(.contactClosed, "closed")
        assertReads(.contactOpenHome, "open at home")
        assertReads(.contactOpenAway, "open away")
        assertReads(.contactOpenArmed, "open armed")
    }

    @Test func contactStatesAreVisiblyDifferent() {
        let fills = [ChipTint.contactClosed, .contactOpenHome, .contactOpenAway, .contactOpenArmed].map(\.fill)
        #expect(Set(fills).count == 4)
        #expect(ChipTint.contactClosed.fill == ColorFamily.contact.spec.fill, "All closed is the contact family's soft green")
        #expect(ChipTint.contactOpenArmed.fill == ColorFamily.securityTriggered.spec.fill, "Armed and open is the triggered red")
        #expect(ChipTint.contactOpenAway.fill == 0xB23A26, "Away and open is the web's window-open coral")
    }

    @Test func familyTintsMatchTheFamilyChipValues() {
        let climate = ChipTint(family: .climate)
        #expect(climate?.fill == 0x195482 && climate?.glyph == 0xFFCC00)
        #expect(ChipTint(family: .lights)?.fill == ColorFamily.lights.chipFillRGB)
        #expect(ChipTint(family: .neutral) == nil)
    }

    @Test(arguments: temperatureColours)
    func everyTemperatureColourReadsOnItsChip(_ colour: UInt32) {
        assertReads(ChipTint.fromWeb(colour, preferredGlyph: 0xFFCC00), "temperature \(String(colour, radix: 16))")
    }

    @Test(arguments: airColours)
    func everyAirColourReadsOnItsChip(_ colour: UInt32) {
        assertReads(ChipTint.fromWeb(colour), "air \(String(colour, radix: 16))")
    }

    @Test func tintsAreDeterministicAndFollowTheColour() {
        #expect(ChipTint.fromWeb(0xFFD700) == ChipTint.fromWeb(0xFFD700))
        // A colder house and a hotter one draw different chips.
        #expect(ChipTint.fromWeb(0x006EFF).fill != ChipTint.fromWeb(0xFF0000).fill)
    }

    @Test func theWebAirTealGivesTheAirFamilyFill() {
        let tint = ChipTint.fromWeb(0x009688)
        #expect(ChipTint.isClose(tint.fill, ColorFamily.air.spec.fill ?? 0), "0.73 of the web teal is #006E63, the Air family's #006E62")
    }

    @Test func darkColoursKeepTheirHueAtTheFirstScale() {
        // Dark enough already: only scaled, never lightened or tinted toward grey.
        let navy = ChipTint.fromWeb(0x195482)
        #expect(navy.fill == ColorFamily.mix(0x195482, 0x000000, ChipTint.fillScale))
    }

    @Test func thePreferredGlyphIsKeptOnlyWhereItReads() {
        // On a blue chip the climate yellow reads and stays; on its own yellow fill it falls back to a lighter tint.
        #expect(ChipTint.fromWeb(0x006EFF, preferredGlyph: 0xFFCC00).glyph == 0xFFCC00)
        let onYellow = ChipTint.fromWeb(0xFFD700, preferredGlyph: 0xFFCC00)
        #expect(ChipTint.contrast(onYellow.glyph, onYellow.liftedFill) >= 3)
    }

    @Test func contrastMatchesTheWCAGDefinition() {
        #expect(abs(ChipTint.contrast(0xFFFFFF, 0x000000) - 21) < 0.001)
        #expect(abs(ChipTint.contrast(0x777777, 0x777777) - 1) < 0.001)
        #expect(ChipTint.luminance(0x000000) == 0)
    }
}
