@testable import HassDesign
import SwiftUI
import Testing

@MainActor
struct ModuleTests {
    @Test func reduceTransparencyMakesTheTintOpaque() {
        for density in ModuleDensity.allCases {
            #expect(ModuleBackground.tint(density, reduceTransparency: false)
                != ModuleBackground.tint(density, reduceTransparency: true))
        }
        #expect(ModuleBackground.tint(.thin, reduceTransparency: false) == HassTokens.Surface.moduleThin)
        #expect(ModuleBackground.tint(.dense, reduceTransparency: false) == HassTokens.Surface.moduleDense)
    }

    @Test(arguments: ModuleDensity.allCases)
    func moduleRendersAtEveryDensity(_ density: ModuleDensity) {
        let view = Text("Kitchen").frame(width: 200, height: 80).module(density)
        #expect(ImageRenderer(content: view).cgImage != nil)
        let tile = Text("Lamp").frame(width: 160, height: 100).module(density, cornerRadius: HassTokens.Radius.tile)
        #expect(ImageRenderer(content: tile).cgImage != nil)
    }
}
