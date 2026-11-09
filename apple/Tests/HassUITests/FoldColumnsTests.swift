import CoreGraphics
import Testing
@testable import HassUI

/// The pure geometry behind a page whose sections stay on one side of the hinge band while the Duo is partly folded
/// (`.agents/design/section-sides.md`).
struct FoldColumnsTests {
    /// Partly folded Duo landscape as measured: band 455.3 to 495.7 pt, content 868 pt wide (leading 455.3, trailing 372.3).
    let hinge = CGRect(x: 455.3, y: 0, width: 40.4, height: 669)
    let content = CGRect(x: 0, y: 0, width: 868, height: 669)

    private func geometry() throws -> SplitGeometry {
        try #require(FoldColumns.resolve(container: content, isRegularWidth: true, hinge: hinge))
    }

    // MARK: Geometry

    @Test func resolvesTheMeasuredColumnsPartlyFolded() throws {
        let columns = try geometry()
        #expect(abs(columns.leadingWidth - 455.3) < 0.01)
        #expect(abs(columns.bandWidth - 40.4) < 0.01)
        #expect(abs(columns.trailingWidth - 372.3) < 0.01)
    }

    @Test func staysOneColumnEverywhereElse() {
        #expect(FoldColumns.resolve(container: content, isRegularWidth: true, hinge: nil) == nil, "flat or no hinge")
        #expect(FoldColumns.resolve(container: CGRect(x: 0, y: 0, width: 1194, height: 834), isRegularWidth: true, hinge: nil) == nil, "iPad")
        #expect(FoldColumns.resolve(container: CGRect(x: 0, y: 0, width: 669, height: 951), isRegularWidth: true,
                                    hinge: CGRect(x: 0, y: 455, width: 669, height: 40)) == nil, "portrait")
        #expect(FoldColumns.resolve(container: CGRect(x: 0, y: 0, width: 800, height: 600), isRegularWidth: true, hinge: hinge) == nil, "under 360 pt")
    }

    // MARK: Sides

    @Test func configuredSidesAlternateByIndexAndHonourAnOverride() {
        #expect([0, 1, 2, 3].map { FoldColumns.side(forConfiguredIndex: $0) } == [.leading, .trailing, .leading, .trailing])
        #expect(FoldColumns.side(forConfiguredIndex: 0, override: .trailing) == .trailing)
        #expect(FoldColumns.side(forConfiguredIndex: 1, override: .top) == .trailing, "top is not a section side")
    }

    // MARK: Layout

    private func heights(_ values: [CGFloat]) -> (Int, CGFloat) -> CGFloat { { index, _ in values[index] } }

    @Test func oneColumnStacksVisibleSectionsAndSkipsHiddenOnes() {
        let entries = [FoldColumns.Entry(side: .top), FoldColumns.Entry(side: .leading, flatGapAbove: 8),
                       FoldColumns.Entry(side: .leading, isHidden: true), FoldColumns.Entry(side: .trailing)]
        let layout = FoldColumns.layout(entries: entries, width: 400, geometry: nil, spacing: 20, rightToLeft: false,
                                        height: heights([50, 100, 70, 30]))
        #expect(layout.frames[0] == CGRect(x: 0, y: 0, width: 400, height: 50))
        #expect(layout.frames[1].minY == 58, "the flat gap overrides the spacing")
        #expect(layout.frames[3].minY == 178)
        #expect(layout.height == 208)
        #expect(layout.topHeight == 0)
    }

    @Test func splitPlacesEverySectionWhollyOnOneSideOfTheBand() throws {
        let columns = try geometry()
        let entries = [FoldColumns.Entry(side: .top), FoldColumns.Entry(side: .leading), FoldColumns.Entry(side: .leading),
                       FoldColumns.Entry(side: .trailing), FoldColumns.Entry(side: .trailing)]
        let layout = FoldColumns.layout(entries: entries, width: content.width, geometry: columns, spacing: 20, rightToLeft: false,
                                        height: heights([40, 100, 80, 60, 90]))
        let band = hinge.minX...hinge.maxX
        for frame in layout.frames.dropFirst() {
            #expect(frame.maxX <= band.lowerBound + 0.01 || frame.minX >= band.upperBound - 0.01)
        }
        #expect(layout.frames[0].width == content.width, "the top strip spans the page")
        #expect(layout.frames[1].minY == 60 && layout.frames[3].minY == 60, "the columns start together under the strip")
        #expect(layout.frames[2].minY == 180)
        #expect(layout.frames[4].minY == 140)
        #expect(layout.height == CGFloat(260), "the taller side sets the height")
    }

    @Test func splitRankPutsCamerasBeforeGuestsWithoutChangingTheFlatOrder() throws {
        let columns = try geometry()
        // Flat order: guests, cameras. Cameras rank first on the trailing side.
        let entries = [FoldColumns.Entry(side: .leading), FoldColumns.Entry(side: .trailing, splitRank: 1), FoldColumns.Entry(side: .trailing, splitRank: 0)]
        let flat = FoldColumns.layout(entries: entries, width: 400, geometry: nil, spacing: 10, rightToLeft: false, height: heights([50, 20, 30]))
        #expect(flat.frames[1].minY < flat.frames[2].minY)
        let split = FoldColumns.layout(entries: entries, width: content.width, geometry: columns, spacing: 10, rightToLeft: false,
                                       height: heights([50, 20, 30]))
        #expect(split.frames[2].minY == split.frames[0].minY, "cameras are level with the leading column's top")
        #expect(split.frames[1].minY == 40)
        #expect(FoldColumns.readingOrder(entries: entries) == [0, 2, 1])
    }

    @Test func aWrappedRailLeadsTheLeadingColumnAndTheTrailingColumnStartsAtTheTop() throws {
        let columns = try geometry()
        let entries = [FoldColumns.Entry(side: .leading, splitRank: -1), FoldColumns.Entry(side: .leading), FoldColumns.Entry(side: .trailing)]
        let layout = FoldColumns.layout(entries: entries, width: content.width, geometry: columns, spacing: 10, rightToLeft: false,
                                        height: heights([200, 80, 60]))
        #expect(layout.topHeight == 0)
        #expect(layout.frames[0].minY == 0 && layout.frames[2].minY == 0)
        #expect(layout.frames[1].minY == 210)
    }

    @Test func aTrailingBlockCanStartLevelWithTheFirstBlockUnderTheHeader() throws {
        let columns = try geometry()
        let entries = [FoldColumns.Entry(side: .leading), FoldColumns.Entry(side: .leading), FoldColumns.Entry(side: .trailing, levelWith: 1)]
        let layout = FoldColumns.layout(entries: entries, width: content.width, geometry: columns, spacing: 10, rightToLeft: false,
                                        height: heights([30, 100, 50]))
        #expect(layout.frames[2].minY == layout.frames[1].minY)
    }

    @Test func poseOnlySectionsTakeRoomOnlyInTheirPose() throws {
        let columns = try geometry()
        let entries = [FoldColumns.Entry(side: .leading, visibility: .flatOnly), FoldColumns.Entry(side: .leading, visibility: .splitOnly)]
        let flat = FoldColumns.layout(entries: entries, width: 400, geometry: nil, spacing: 10, rightToLeft: false, height: heights([100, 70]))
        #expect(flat.height == 100)
        let split = FoldColumns.layout(entries: entries, width: content.width, geometry: columns, spacing: 10, rightToLeft: false, height: heights([100, 70]))
        #expect(split.height == 70)
        #expect(FoldColumns.readingOrder(entries: entries) == [1])
    }

    @Test func rightToLeftMirrorsTheColumnsAndSideInsetsNarrowThem() throws {
        let columns = try geometry()
        let entries = [FoldColumns.Entry(side: .leading), FoldColumns.Entry(side: .trailing), FoldColumns.Entry(side: .top, fullBleed: true)]
        let layout = FoldColumns.layout(entries: entries, width: content.width, geometry: columns, spacing: 10, rightToLeft: true, sideInset: 16,
                                        height: heights([10, 10, 10]))
        #expect(layout.frames[0].minX > layout.frames[1].minX, "the leading column is on the right")
        #expect(abs(layout.frames[0].width - (columns.leadingWidth - 32)) < 0.01)
        #expect(layout.frames[2].width == content.width, "a full-bleed section ignores the inset")
    }

    @Test func theSingleColumnCentresAtItsCapAndKeepsTheSideInsets() {
        let entries = [FoldColumns.Entry(side: .leading)]
        let layout = FoldColumns.layout(entries: entries, width: 1200, geometry: nil, spacing: 10, rightToLeft: false, sideInset: 16,
                                        flatMaxWidth: 960, height: heights([10]))
        #expect(layout.frames[0].width == 960 && layout.frames[0].minX == 120)
        let narrow = FoldColumns.layout(entries: entries, width: 400, geometry: nil, spacing: 10, rightToLeft: false, sideInset: 16,
                                        flatMaxWidth: 960, height: heights([10]))
        #expect(narrow.frames[0].minX == 16 && narrow.frames[0].width == 368)
    }

    // MARK: Full-bleed and top sections

    @Test func aFullBleedSectionIgnoresTheSideInsetInBothPoses() throws {
        let columns = try geometry()
        let entries = [FoldColumns.Entry(side: .top, fullBleed: true), FoldColumns.Entry(side: .leading), FoldColumns.Entry(side: .trailing)]
        let flat = FoldColumns.layout(entries: entries, width: 400, geometry: nil, spacing: 10, rightToLeft: false, sideInset: 16, height: heights([40, 50, 50]))
        #expect(flat.frames[0] == CGRect(x: 0, y: 0, width: 400, height: 40), "the rail runs to the page's edges")
        #expect(flat.frames[1].minX == 16 && flat.frames[1].width == 368)
        let split = FoldColumns.layout(entries: entries, width: content.width, geometry: columns, spacing: 10, rightToLeft: false, sideInset: 16,
                                       height: heights([40, 50, 50]))
        #expect(split.frames[0].minX == 0 && split.frames[0].width == content.width)
        #expect(split.frames[1].minX == 16 && split.frames[1].maxX <= columns.leadingWidth - 16 + 0.01, "sections keep the inset")
        #expect(split.frames[2].minX >= columns.leadingWidth + columns.bandWidth)
    }

    @Test func aTopSectionThatSpansOnlyTheLeadingRegionStopsAtTheBand() throws {
        let columns = try geometry()
        let entries = [FoldColumns.Entry(side: .top, topSpansLeadingOnly: true), FoldColumns.Entry(side: .top), FoldColumns.Entry(side: .leading)]
        let layout = FoldColumns.layout(entries: entries, width: content.width, geometry: columns, spacing: 10, rightToLeft: false,
                                        height: heights([40, 30, 50]))
        #expect(abs(layout.frames[0].width - columns.leadingWidth) < 0.01, "the banner spans only the leading region")
        #expect(layout.frames[1].width == content.width && layout.frames[1].minY == 50, "the next top section stacks under it and spans the page")
        #expect(layout.topHeight == 80)
        #expect(layout.frames[2].minY >= 80)
    }

    @Test func aLevelEntryThatIsHiddenFallsBackToTheTopOfTheColumn() throws {
        let columns = try geometry()
        let entries = [FoldColumns.Entry(side: .leading), FoldColumns.Entry(side: .leading, isHidden: true), FoldColumns.Entry(side: .trailing, levelWith: 1)]
        let layout = FoldColumns.layout(entries: entries, width: content.width, geometry: columns, spacing: 10, rightToLeft: false, height: heights([30, 100, 50]))
        #expect(layout.frames[2].minY == 0)
    }
}
