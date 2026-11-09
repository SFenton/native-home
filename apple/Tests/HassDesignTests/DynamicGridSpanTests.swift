import CoreGraphics
@testable import HassDesign
import SwiftUI
import Testing

/// Content-aware spans: the pure rule and how the grid applies it (`.agents/patterns/dynamic-grid.md`).
struct DynamicGridSpanTests {
    /// An iPhone: 402 pt wide with 16 pt margins, two tracks of 179 pt and a 12 pt gutter.
    static let phone = DynamicGridMetrics(width: 370, minCellWidth: 150, maxColumns: 6, spacing: 12)

    // MARK: The pure rule

    @Test func eachTileTakesTheCeilingOfItsMinimumOverTheTrack() {
        let spans = DynamicGridMetrics.spans(minimums: [0, 100, 179, 180, 340, 361], trackWidth: 100, columns: 6)
        #expect(spans.map(\.span) == [1, 1, 2, 2, 4, 4])
        #expect(spans.allSatisfy { !$0.isCapped })
    }

    @Test func guttersCountTowardASpansWidth() {
        // Two tracks of 179 and a 12 gutter are 370 wide: a 360 pt minimum still fits two tracks, 371 does not fit.
        let fits = DynamicGridMetrics.spans(minimums: [172, 228, 370, 371], trackWidth: 179, columns: 2, spacing: 12)
        #expect(fits.map(\.span) == [1, 2, 2, 2])
        #expect(fits.map(\.isCapped) == [false, false, false, true])
    }

    @Test func aCarriedGlyphTileWithOneDiscFitsAHalfTrackAndTwoDiscsTakeTheRow() {
        let one = TileMinimumWidth.width(text: 10, glyphColumn: 0, chevron: 0, strip: 44 + 8)
        let two = TileMinimumWidth.width(text: 10, glyphColumn: 0, chevron: 0, strip: 100 + 8)
        #expect(one == 172 && two == 228)
        let spans = DynamicGridMetrics.spans(minimums: [one, two], trackWidth: 179, columns: 2, spacing: 12)
        #expect(spans.map(\.span) == [1, 2])
        #expect(spans.map(\.isCapped) == [false, false])
    }

    @Test func aMinimumWiderThanTheWholeRowIsCappedAtTheRow() {
        let spans = DynamicGridMetrics.spans(minimums: [500], trackWidth: 100, columns: 3, spacing: 0)
        #expect(spans == [.init(span: 3, isCapped: true)])
        // Exactly the row is not capped.
        #expect(DynamicGridMetrics.spans(minimums: [300], trackWidth: 100, columns: 3).first == .init(span: 3, isCapped: false))
    }

    @Test func aDegenerateTrackCapsInsteadOfTrapping() {
        #expect(DynamicGridMetrics.spans(minimums: [100], trackWidth: 0, columns: 4).first == .init(span: 4, isCapped: true))
        #expect(DynamicGridMetrics.spans(minimums: [100], trackWidth: .nan, columns: 4).first == .init(span: 4, isCapped: true))
        #expect(DynamicGridMetrics.spans(minimums: [], trackWidth: 100, columns: 4).isEmpty)
    }

    // MARK: The hinge band

    @Test func inASplitLayoutTheCapIsOneSide() {
        // An unfolded Duo: 700 wide with a 60 pt band in the middle, two tracks a side.
        let metrics = DynamicGridMetrics(width: 700, minCellWidth: 150, maxColumns: 6, spacing: 12, evenColumns: true, band: 320...380)
        #expect(metrics.sideColumns == 2 && metrics.columns == 4 && metrics.spanCap == 2)
        let spans = metrics.spans(minimums: [100, 400, 2_000], spacing: 12)
        #expect(spans.map(\.span) == [1, 2, 2], "never more than a side, so never across the band")
        #expect(spans.map(\.isCapped) == [false, true, true], "a side is 308 wide: 400 does not fit it")
    }

    @Test func aSizedTileNeverStraddlesTheBand() {
        let metrics = DynamicGridMetrics(width: 700, minCellWidth: 90, maxColumns: 6, spacing: 12, evenColumns: true, band: 320...380)
        #expect(metrics.sideColumns == 3)
        // Two-track tiles: the first two fill tracks 0-1, the next would start at 2 and cross to 3, so it starts after the band.
        let placed = metrics.placements(spans: [2, 2, 2], sized: [true, true, true])
        #expect(placed.map(\.column) == [0, 3, 0])
        #expect(placed.map(\.row) == [0, 0, 1])
    }

    @Test func anExplicitSpanStillCrossesTheBandAsBefore() {
        let metrics = DynamicGridMetrics(width: 700, minCellWidth: 90, maxColumns: 6, spacing: 12, evenColumns: true, band: 320...380)
        let placed = metrics.placements(spans: [2, 2, 2])
        #expect(placed.map(\.column) == [0, 2, 4], "unsized items place exactly as before")
    }

    // MARK: Explicit floor and row filling

    @Test func anExplicitSpanIsAFloorUnderTheContentSpan() {
        let metrics = Self.phone
        #expect(metrics.columns == 2)
        let spans = DynamicGridLayout.spans(explicit: [1, 2, 1, 1], minimums: [100, 100, 300, 0], metrics: metrics, spacing: 12)
        #expect(spans == [1, 2, 2, 1], "explicit 2 stays 2 for a small tile; a wide tile raises 1 to 2; no minimum keeps its span")
    }

    @Test func rowsAreFilledExceptTheLast() {
        // Three tracks: a 2-wide tile then a 2-wide tile leave a spare track in the first row, which the first row's sized tile takes.
        let metrics = DynamicGridMetrics(width: 520, minCellWidth: 160, maxColumns: 4, spacing: 12)
        #expect(metrics.columns == 3)
        let placed = metrics.placements(spans: [2, 2, 1], sized: [true, true, true])
        #expect(placed.map(\.span) == [3, 2, 1], "the spare track goes to the first row's tile; the last row is not filled")
        #expect(placed.map(\.row) == [0, 1, 1])
    }

    @Test func tilesWithNoMinimumAreNeverStretched() {
        let metrics = DynamicGridMetrics(width: 520, minCellWidth: 160, maxColumns: 4, spacing: 12)
        let placed = metrics.placements(spans: [2, 2], sized: [false, false])
        #expect(placed.map(\.span) == [2, 2])
        let withHeader = metrics.placements(spans: [1, .max, 1], sized: [true, false, true])
        #expect(withHeader.map(\.span) == [3, 3, 1], "a heading takes its row; the tile before it fills its row")
    }

    // MARK: Stability

    @MainActor
    @Test func aLiveStateChangeDoesNotChangeTheMinimumOrSpans() {
        let states = ["Off", "On", "Playing · Some Long Station Name", "Unavailable"]
        func minimum(shown: String?) -> CGFloat {
            TileMinimumWidth.width(title: "Living Room TV", shown: shown, states: states, typeSize: .large, glyphColumn: 0, chevron: 20, strip: 52)
        }
        let longer = "Playing · A Station Name Longer Than Every Candidate In The List"
        let widths = Set(states.map { minimum(shown: $0) } + [minimum(shown: nil), minimum(shown: longer)])
        #expect(widths.count == 1, "the longest candidate decides, whatever is shown, even a live text longer than all of them")
        let none = TileMinimumWidth.width(title: "Fan", shown: longer, states: [], typeSize: .large, glyphColumn: 0, chevron: 0, strip: 0)
        #expect(none > TileMinimumWidth.width(title: "Fan", shown: nil, states: [], typeSize: .large, glyphColumn: 0, chevron: 0, strip: 0),
                "with no candidates the static subtitle is measured")
        let spans = states.map { DynamicGridMetrics.spans(minimums: [minimum(shown: $0)], trackWidth: 179, columns: 2, spacing: 12) }
        #expect(Set(spans.map(\.first)).count == 1)
    }

    @MainActor
    @Test func theLongestCandidateWidensTheMinimum() {
        let short = TileMinimumWidth.width(title: "Fan", shown: nil, states: ["On", "Off"], typeSize: .large, glyphColumn: 0, chevron: 0, strip: 0)
        let long = TileMinimumWidth.width(title: "Fan", shown: nil, states: ["On", "Off", "Off in 00:00:00 and locked until further notice"],
                                          typeSize: .large, glyphColumn: 0, chevron: 0, strip: 0)
        #expect(short == TileMinimumWidth.textFloor + 24, "short text is held to the floor")
        #expect(long > short)
    }

    @MainActor
    @Test func textSizeWidensTheMinimum() {
        func minimum(_ size: DynamicTypeSize) -> CGFloat {
            TileMinimumWidth.width(title: "Garage Door Opener", shown: nil, states: ["Opening"], typeSize: size, glyphColumn: 42, chevron: 0, strip: 0)
        }
        #expect(minimum(.accessibility3) > minimum(.large))
        #expect(minimum(.large) > minimum(.xSmall))
    }

    @Test func theTrailingFloorIsTheStripPlusTheTextFloor() {
        // One disc, carried glyph: 24 + 96 + 52 = 172. A navigation tile adds its glyph column and the chevron reserve.
        #expect(TileMinimumWidth.width(text: TileMinimumWidth.textFloor, glyphColumn: 0, chevron: 0, strip: 52) == 172)
        #expect(TileMinimumWidth.width(text: TileMinimumWidth.textFloor, glyphColumn: 42, chevron: 20, strip: 52) == 234)
        // A long title raises the natural minimum but never the floor.
        #expect(TileMinimumWidth.width(text: 300, glyphColumn: 0, chevron: 0, strip: 52) > 172)
    }

    @Test func theMinimumIsAddedFromItsParts() {
        #expect(TileMinimumWidth.width(text: 150, glyphColumn: 42, chevron: 20, strip: 52) == CGFloat(288))
        #expect(TileMinimumWidth.width(text: 10, glyphColumn: 0, chevron: 0, strip: 0) == 24 + TileMinimumWidth.textFloor)
    }

    @Test func aTileIsCappedWhenItsResolvedWidthIsNarrowerThanItsMinimum() {
        #expect(TileMinimumWidth.isCapped(resolved: 179, minimum: 228))
        #expect(!TileMinimumWidth.isCapped(resolved: 228, minimum: 228))
        #expect(!TileMinimumWidth.isCapped(resolved: 227.7, minimum: 228), "half a point of rounding is not a cap")
    }

    @Test func theCacheKeyMovesWithTheMinimumsButNotWithNoise() {
        let base = DynamicGridLayout.minimumsHash([172, 228, 0])
        #expect(base == DynamicGridLayout.minimumsHash([172.01, 228, 0]))
        #expect(base != DynamicGridLayout.minimumsHash([172, 260, 0]), "a text-size or action-count change")
        #expect(base != DynamicGridLayout.minimumsHash([172, 228]))
        let a = DynamicGridLayout.Cache.Key(width: 370, bandLower: nil, bandUpper: nil, minimums: base)
        let b = DynamicGridLayout.Cache.Key(width: 370, bandLower: nil, bandUpper: nil, minimums: DynamicGridLayout.minimumsHash([172, 260, 0]))
        #expect(a != b)
    }
}
