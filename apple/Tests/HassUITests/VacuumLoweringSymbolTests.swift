import HassDesign
import Testing
@testable import HassCore

// MARK: - The lowering's colours

/// `HassCore` sits below `HassDesign`, so the vacuum lowering mirrors the two colours of the cleaning family it draws.
/// This keeps each mirror equal to `ColorFamily.cleaning`.
@Suite struct VacuumLoweringSymbolTests {
    @Test func theRobotPurpleIsTheCleaningFamilysFill() {
        #expect(ServerUIVacuumLowering.Reads.robotPurple == ColorFamily.cleaning.spec.fill)
    }

    @Test func theAutoCleanGlyphIsTheCleaningFamilysDarkGlyph() {
        let glyph = ServerUIVacuumLowering.Reads.cleaningGlyph
        #expect(UInt32(glyph.red) << 16 | UInt32(glyph.green) << 8 | UInt32(glyph.blue) == ColorFamily.cleaning.spec.glyph)
    }

    @Test func theAutoCleanGlyphLightIsTheCleaningFamilysLightGlyph() {
        let glyph = ServerUIVacuumLowering.Reads.cleaningGlyphLight
        #expect(UInt32(glyph.red) << 16 | UInt32(glyph.green) << 8 | UInt32(glyph.blue) == ColorFamily.cleaning.glyphLightRGB)
    }
}
