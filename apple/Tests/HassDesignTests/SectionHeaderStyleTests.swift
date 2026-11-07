import SwiftUI
import Testing
@testable import HassDesign

/// One section-header weight, set in one place (`HassTokens.Typography.sectionTitle`).
@MainActor
struct SectionHeaderStyleTests {
    @Test func boldTitle3IsTheSectionHeaderFont() {
        #expect(HassTokens.Typography.sectionTitle == Font.title3.bold())
        #expect(HassTokens.Typography.sectionTitle != Font.title3.weight(.semibold))
    }

}
