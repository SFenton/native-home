@testable import HassDesign
import SwiftUI
import Testing

struct FloatingActionBarTests {
    /// The prominent capsule's white label and an active circle's black glyph need 4.5:1 on their fills (WCAG 1.4.3):
    /// G's `#0071E3` and `#F2F2F7`.
    @Test func tintsKeepTextReadable() {
        func luminance(_ r: Double, _ g: Double, _ b: Double) -> Double {
            func channel(_ value: Double) -> Double {
                let c = value / 255
                return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
        }
        func contrastWithWhite(_ r: Double, _ g: Double, _ b: Double) -> Double { 1.05 / (luminance(r, g, b) + 0.05) }
        func contrastWithBlack(_ r: Double, _ g: Double, _ b: Double) -> Double { (luminance(r, g, b) + 0.05) / 0.05 }
        #expect(HassTokens.Palette.tintFill == 0x0071E3)
        #expect(contrastWithWhite(0x00, 0x71, 0xE3) >= 4.5)
        #expect(contrastWithBlack(0xF2, 0xF2, 0xF7) >= 4.5)
        #expect(FloatingActionBar.size >= HassTokens.minTarget)
    }

}
