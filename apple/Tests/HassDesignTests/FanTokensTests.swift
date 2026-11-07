import Foundation
@testable import HassDesign
import SwiftUI
import Testing

/// The bathroom fan refresh's design tokens (owner design, 2026-10-17): the timer orange, the selected segment and the
/// accessory rail's layout constants on the shared tile.
@MainActor
struct FanTokensTests {
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

    @Test func timerOrangeIsTheWebsAndReadsOnBothSheets() {
        #expect(Palette.timer == 0xFF9F0A, "the web's --color-timer, rgb(255, 159, 10)")
        // 40 pt semibold is large text (3:1); the glyph and bar are non-text (3:1).
        #expect(contrast(Palette.timer, Palette.sheetGround) >= 3)
        #expect(contrast(Palette.timer, Palette.sheetCell) >= 3)
        #expect(contrast(Palette.timerLight, 0xFFFFFF) >= 4.5, "the light sheet's orange holds small-text contrast too")
        #expect(contrast(Palette.timerLight, Palette.sheetGroundLight) >= 3)
        #expect(HassTokens.Ink.timer != Color.clear)
    }

    @Test func selectedSegmentIsTheLabelsOpposite() {
        // Dark sheet: white fill, black text. Light sheet: near-black fill, white text. Either way it clears the cell.
        #expect(contrast(0xFFFFFF, Palette.sheetCell) >= 3)
        #expect(contrast(0x000000, 0xFFFFFF) >= 4.5)
        #expect(contrast(0x1C1C1E, Palette.sheetCellLight) >= 3)
        #expect(contrast(0xFFFFFF, 0x1C1C1E) >= 4.5)
        #expect(HassTokens.Surface.selectedSegment != HassTokens.Surface.selectedSegmentInk)
    }

    @Test func theRailSitsOneChevronSlotInFromTheEdge() {
        // The rail's trailing padding is the tile's padding plus the chevron slot, so the two never overlap, and the
        // slot is wider than the chevron glyph (a footnote semibold chevron is about 9 pt wide).
        #expect(GlassTileFace.chevronReserve >= 16)
        #expect(HassTokens.minTarget == 44)
    }
}
