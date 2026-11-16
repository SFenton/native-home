@testable import HassDesign
import SwiftUI
import Testing

/// The light and dark colour pair a server-composed page can author (`sh.solid-appearance@1`).
struct AppearanceFillTests {
    @Test func aPairGivesItsMemberForEachAppearance() {
        let fill = AppearanceFill(light: 0x9C6DC3, dark: 0xC88CFA)
        #expect(fill.rgb(isDark: false) == 0x9C6DC3 && fill.rgb(isDark: true) == 0xC88CFA)
        #expect(!fill.isFixed)
    }

    @Test func oneColourIsTheSameInBoth() {
        let fill = AppearanceFill(0x112233)
        #expect(fill.isFixed && fill.rgb(isDark: false) == fill.rgb(isDark: true))
        #expect(fill.token.isFixed)
    }

    @Test func theTokenResolvesDifferentlyForLightAndDark() {
        let token = AppearanceFill(light: 0x9C6DC3, dark: 0xC88CFA).token
        #expect(!token.isFixed)
        let light = token.components(isDark: false, increasedContrast: false)
        let dark = token.components(isDark: true, increasedContrast: false)
        #expect(light == HassRGB.Components(rgb: 0x9C6DC3) && dark == HassRGB.Components(rgb: 0xC88CFA))
        // Increase Contrast keeps the author's colours: a fixed pair is the author's value.
        #expect(token.components(isDark: false, increasedContrast: true) == light && token.components(isDark: true, increasedContrast: true) == dark)
    }
}
