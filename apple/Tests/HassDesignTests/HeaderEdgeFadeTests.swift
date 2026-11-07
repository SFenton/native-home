import CoreGraphics
@testable import HassDesign
import SwiftUI
import Testing

/// The header fade's geometry (pattern: `.agents/patterns/header-edge-fade.md`).
struct HeaderEdgeFadeTests {
    @Test func headerIsTheLargerReadingNeverTheirSum() {
        #expect(HeaderEdgeFade.headerHeight(safeAreaInset: 96, containerOffset: 0) == 96)
        #expect(HeaderEdgeFade.headerHeight(safeAreaInset: 56, containerOffset: 56) == 56)
        #expect(HeaderEdgeFade.headerHeight(safeAreaInset: 0, containerOffset: 120) == 120)
        #expect(HeaderEdgeFade.headerHeight(safeAreaInset: -4, containerOffset: -8) == 0)
        #expect(HeaderEdgeFade.headerHeight(safeAreaInset: .nan, containerOffset: 30) == 30)
        #expect(HeaderEdgeFade.headerHeight(safeAreaInset: .infinity, containerOffset: .nan) == 0)
    }

    @Test func theCapIsTheStatusRegionAloneWhenTheBarIsATrailingRail() {
        #expect(HeaderEdgeFade.edgeCap(statusTop: 62, barHeight: 44, barIsRail: false) == 106)
        #expect(HeaderEdgeFade.edgeCap(statusTop: 62, barHeight: 44, barIsRail: true) == 62)
        #expect(HeaderEdgeFade.edgeCap(statusTop: 0, barHeight: 44, barIsRail: false) == nil)
        #expect(HeaderEdgeFade.edgeCap(statusTop: 0, barHeight: 44, barIsRail: true) == nil)
    }

    @Test func clearBandStopsAtTheInlineBarSoLargeTitlesShow() {
        // Expanded large title: the inset (170) includes the title; the bar ends at 106.
        #expect(HeaderEdgeFade.clearHeight(header: 170, smallestInset: 170, cap: 106) == 106)
        // Once the title collapsed, the smallest inset is the bar itself.
        #expect(HeaderEdgeFade.clearHeight(header: 170, smallestInset: 104, cap: 110) == 104)
        // A sheet's inline bar sits below any window estimate.
        #expect(HeaderEdgeFade.clearHeight(header: 56, smallestInset: 56, cap: 106) == 56)
        #expect(HeaderEdgeFade.clearHeight(header: 80, smallestInset: nil, cap: nil) == 80)
        #expect(HeaderEdgeFade.clearHeight(header: 80, smallestInset: .nan, cap: -1) == 80)
    }

    @Test func fadeGrowsLinearlyOverTheFirstFortyPoints() {
        #expect(HeaderEdgeFade.rampHeight == 40)
        #expect(HeaderEdgeFade.progress(scrollOffset: 0) == 0)
        #expect(HeaderEdgeFade.progress(scrollOffset: -30) == 0)
        #expect(HeaderEdgeFade.progress(scrollOffset: 10) == 0.25)
        #expect(HeaderEdgeFade.progress(scrollOffset: 40) == 1)
        #expect(HeaderEdgeFade.progress(scrollOffset: 400) == 1)
        #expect(HeaderEdgeFade.progress(scrollOffset: .nan) == 0)
    }

    @Test func hardEdgeIsClearAsSoonAsContentScrolls() {
        #expect(HeaderEdgeFade.progress(scrollOffset: 0, rampHeight: 0) == 0)
        #expect(HeaderEdgeFade.progress(scrollOffset: 1, rampHeight: 0) == 1)
    }

    @Test func edgeIsOpaqueAtRestAndClearOnceScrolled() {
        #expect(HeaderEdgeFade.edgeOpacity(progress: 0) == 1)
        #expect(HeaderEdgeFade.edgeOpacity(progress: 0.25) == 0.75)
        #expect(HeaderEdgeFade.edgeOpacity(progress: 1) == 0)
        #expect(HeaderEdgeFade.edgeOpacity(progress: 3) == 0)
        #expect(HeaderEdgeFade.edgeOpacity(progress: .nan) == 1)
    }

    @Test func accessibilitySettingsAndMissingScrollTrackingGiveAHardEdge() {
        #expect(HeaderEdgeFade.ramp(reduceTransparency: false, increaseContrast: false, tracksScroll: true) == 40)
        #expect(HeaderEdgeFade.ramp(reduceTransparency: true, increaseContrast: false, tracksScroll: true) == 0)
        #expect(HeaderEdgeFade.ramp(reduceTransparency: false, increaseContrast: true, tracksScroll: true) == 0)
        #expect(HeaderEdgeFade.ramp(reduceTransparency: false, increaseContrast: false, tracksScroll: false) == 0)
    }
}
