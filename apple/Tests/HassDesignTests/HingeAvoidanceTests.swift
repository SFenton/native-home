import CoreGraphics
@testable import HassDesign
import Testing

/// Hinge avoidance geometry (`.agents/patterns/hinge-avoidance.md`), on the measured unfolded Duo: 868 pt of content,
/// hinge band 455.3 to 495.7.
struct HingeAvoidanceTests {
    private let hinge = CGRect(x: 455.3, y: 0, width: 40.4, height: 669)
    private let content = CGRect(x: 0, y: 0, width: 868, height: 669)

    @Test func aVerticalHingeAcrossTheContainerIsABandInLocalOffsets() throws {
        let band = try #require(HingeAvoidance.band(in: content, hinge: hinge))
        #expect(abs(band.lowerBound - 455.3) < 0.001 && abs(band.upperBound - 495.7) < 0.001)
        // A container that starts later reads the same band from its own edge.
        let shifted = try #require(HingeAvoidance.band(in: CGRect(x: 100, y: 0, width: 700, height: 600), hinge: hinge))
        #expect(abs(shifted.lowerBound - 355.3) < 0.001)
    }

    @Test func noBandWithoutAVerticalHingeInsideTheContainer() {
        #expect(HingeAvoidance.band(in: content, hinge: nil) == nil)
        // Unfolded portrait: the hinge is horizontal.
        #expect(HingeAvoidance.band(in: content, hinge: CGRect(x: 0, y: 455.3, width: 951, height: 40.4)) == nil)
        // The hinge sits outside a pane that starts after it.
        #expect(HingeAvoidance.band(in: CGRect(x: 500, y: 0, width: 368, height: 669), hinge: hinge) == nil)
        #expect(HingeAvoidance.band(in: content, hinge: .zero) == nil)
    }

    @Test func aBandClipsToTheContainer() throws {
        let band = try #require(HingeAvoidance.band(in: CGRect(x: 470, y: 0, width: 300, height: 100), hinge: hinge))
        #expect(band.lowerBound == 0)
    }

    @Test func anObjectStaysCentredWhenTheBandMissesIt() {
        let clear = HingeAvoidance.placement(objectWidth: 868, containerWidth: 868, band: nil)
        #expect(clear.x == 0 && clear.width == 868)
        let beside = HingeAvoidance.placement(objectWidth: 300, containerWidth: 868, band: 700...740)
        #expect(beside.x == 284 && beside.width == 300)
    }

    @Test func anObjectTheBandCrossesMovesToTheLeadingRegionsCentre() {
        let band: ClosedRange<CGFloat> = 455.3...495.7
        let alarm = HingeAvoidance.placement(objectWidth: 560, containerWidth: 868, band: band)
        // 560 does not fit in the 455.3 pt leading region, so it is narrowed to it and sits at its start.
        #expect(alarm.width == 455.3 && alarm.x == 0)
        let form = HingeAvoidance.placement(objectWidth: 300, containerWidth: 868, band: band)
        #expect(form.width == 300 && abs(form.x - 77.65) < 0.001)
    }

    @Test func aClearRegionIsTheWiderSideOfTheBand() {
        let band: ClosedRange<CGFloat> = 455.3...495.7
        let region = HingeAvoidance.clearRegion(containerWidth: 868, band: band)
        #expect(region.x == 0 && region.width == 455.3)
        let sheet = HingeAvoidance.clearRegion(containerWidth: 540, band: 100...140)
        #expect(sheet.x == 140 && sheet.width == 400)
        #expect(HingeAvoidance.clearRegion(containerWidth: 540, band: nil) == (0, 540))
        #expect(HingeAvoidance.clearRegion(containerWidth: 200, band: 100...100).x == 0)
    }
}

/// ``DynamicGridMetrics`` with a hinge band: no track starts under the fold.
struct DynamicGridBandTests {
    private let band: ClosedRange<CGFloat> = 455.3...495.7

    @Test func eachSideGetsItsOwnTracksAndTheGapIsTheBand() {
        let metrics = DynamicGridMetrics(width: 868, minCellWidth: 150, maxColumns: 6, spacing: 12, evenColumns: true, band: band)
        // Leading 455.3 fits 2 tracks of 150 (12 spacing); trailing 372.3 fits 2: two a side.
        #expect(metrics.columns == 4)
        #expect(metrics.tracks.count == 4)
        let (a, b, c, d) = (metrics.tracks[0], metrics.tracks[1], metrics.tracks[2], metrics.tracks[3])
        #expect(a.x == 0 && abs(b.x + b.width - 455.3) < 0.001)
        #expect(abs(c.x - 495.7) < 0.001 && abs(d.x + d.width - 868) < 0.001)
        #expect(abs(a.width - (455.3 - 12) / 2) < 0.001)
        #expect(abs(c.width - (372.3 - 12) / 2) < 0.001)
        // Nothing overlaps the band.
        #expect(metrics.tracks.allSatisfy { $0.x + $0.width <= band.lowerBound + 0.001 || $0.x >= band.upperBound - 0.001 })
    }

    @Test func aWideGridUsesMoreTracksPerSideUpToHalfTheMaximum() {
        // A grid of small controls (under 100 pt a cell) keeps its own cap of six; tiles stop at four a row, two a side.
        let metrics = DynamicGridMetrics(width: 1600, minCellWidth: 90, maxColumns: 6, spacing: 12, evenColumns: true, band: 780...820)
        #expect(metrics.columns == 6)
        #expect(DynamicGridMetrics(width: 1600, minCellWidth: 150, maxColumns: 6, spacing: 12, evenColumns: true, band: 780...820).columns == 4)
        #expect(metrics.frame(column: 2, span: 1).x + metrics.tracks[2].width <= 780.001)
    }

    @Test func aSpanAcrossTheBandTakesTheBandToo() {
        let metrics = DynamicGridMetrics(width: 868, minCellWidth: 150, maxColumns: 6, spacing: 12, evenColumns: true, band: band)
        let full = metrics.frame(column: 0, span: 4)
        #expect(full.x == 0 && abs(full.width - 868) < 0.001)
        // Clamped to the grid.
        #expect(abs(metrics.frame(column: 3, span: 9).width - metrics.tracks[3].width) < 0.001)
        #expect(abs(metrics.width(span: 2, spacing: 12) - 455.3) < 0.001)
    }

    @Test func aBandIsIgnoredWhenASideCannotHoldATrack() {
        let narrow = DynamicGridMetrics(width: 868, minCellWidth: 300, maxColumns: 6, spacing: 12, evenColumns: true, band: 200...240)
        let plain = DynamicGridMetrics(width: 868, minCellWidth: 300, maxColumns: 6, spacing: 12, evenColumns: true)
        #expect(narrow == plain)
        #expect(DynamicGridMetrics(width: 868, minCellWidth: 150, maxColumns: 1, spacing: 12, evenColumns: true, band: band).columns == 1)
        // Without evenColumns (no hinge on the device) a band changes nothing.
        let off = DynamicGridMetrics(width: 868, minCellWidth: 150, maxColumns: 6, spacing: 12, evenColumns: false, band: band)
        #expect(off == DynamicGridMetrics(width: 868, minCellWidth: 150, maxColumns: 6, spacing: 12))
        // A band at the edge is not across the grid.
        let edge = DynamicGridMetrics(width: 868, minCellWidth: 150, maxColumns: 6, spacing: 12, evenColumns: true, band: 0...40)
        #expect(edge == DynamicGridMetrics(width: 868, minCellWidth: 150, maxColumns: 6, spacing: 12, evenColumns: true))
    }

    @Test func plainTracksMatchTheOldColumnMath() {
        let metrics = DynamicGridMetrics(width: 343, minCellWidth: 160, maxColumns: 4, spacing: 12)
        #expect(metrics.tracks.map(\.x) == [0, 177.5])
        #expect(metrics.tracks.allSatisfy { $0.width == 165.5 })
        let unbounded = DynamicGridMetrics(width: .infinity, minCellWidth: 160, maxColumns: 4, spacing: 12)
        #expect(unbounded.tracks.count == 4)
    }
}
