@testable import HassDesign
import SwiftUI
import Testing

struct TileFaceStyleTests {
    @Test func offUnavailableAndErrorWinOverFamily() {
        #expect(TileFaceStyle.resolve(family: .air, isActive: false, isError: false, isUnavailable: false) == .off)
        #expect(TileFaceStyle.resolve(family: .air, isActive: true, isError: false, isUnavailable: true) == .off)
        #expect(TileFaceStyle.resolve(family: .air, isActive: true, isError: true, isUnavailable: false) == .error)
        #expect(TileFaceStyle.resolve(family: nil, isActive: false, isError: true, isUnavailable: false) == .error)
    }

    @Test func onTilesFillWithTheirFamily() {
        #expect(TileFaceStyle.resolve(family: .lights, isActive: true, isError: false, isUnavailable: false) == .lit)
        #expect(TileFaceStyle.resolve(family: .media, isActive: true, isError: false, isUnavailable: false) == .filled(.media))
        #expect(TileFaceStyle.resolve(family: .power, isActive: true, isError: false, isUnavailable: false) == .filled(.power))
        // No family yet, or one that is never filled: the caller's tint.
        #expect(TileFaceStyle.resolve(family: nil, isActive: true, isError: false, isUnavailable: false) == .tinted)
        #expect(TileFaceStyle.resolve(family: .neutral, isActive: true, isError: false, isUnavailable: false) == .tinted)
    }

    @Test func darkInkOnLitAndPowerOnly() {
        #expect(TileFaceStyle.lit.hasDarkInk)
        #expect(TileFaceStyle.filled(.power).hasDarkInk)
        #expect(!TileFaceStyle.filled(.air).hasDarkInk)
        #expect(!TileFaceStyle.off.hasDarkInk)
        #expect(!TileFaceStyle.error.hasDarkInk)
    }
}
