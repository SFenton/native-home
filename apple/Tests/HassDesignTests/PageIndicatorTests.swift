import SwiftUI
import Testing
@testable import HassDesign

/// The shared page indicator's rules (`.agents/patterns/page-indicator.md`).
@MainActor
struct PageIndicatorTests {
    @Test func dotsUpToTenPagesThenACount() {
        #expect(!PageIndicator.showsCount(pageCount: 1))
        #expect(!PageIndicator.showsCount(pageCount: 10))
        #expect(PageIndicator.showsCount(pageCount: 11))
        #expect(PageIndicator.showsCount(pageCount: 12))
    }

    @Test func countAndValueReadOneBased() {
        #expect(PageIndicator.countLabel(page: 3, pageCount: 12) == "4 of 12")
        #expect(PageIndicator.valueDescription(page: 3, pageCount: 12) == "Page 4 of 12")
        #expect(PageIndicator.countLabel(page: 40, pageCount: 3) == "3 of 3", "clamped to the last page")
        #expect(PageIndicator.countLabel(page: -2, pageCount: 0) == "1 of 1")
    }

    @Test func tapsMoveOnePageAndStopAtTheEnds() {
        #expect(PageIndicator.target(from: 2, forward: true, pageCount: 5) == 3)
        #expect(PageIndicator.target(from: 2, forward: false, pageCount: 5) == 1)
        #expect(PageIndicator.target(from: 4, forward: true, pageCount: 5) == nil)
        #expect(PageIndicator.target(from: 0, forward: false, pageCount: 5) == nil)
        #expect(PageIndicator.target(from: 0, forward: true, pageCount: 1) == nil)
    }
}
