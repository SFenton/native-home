import CoreGraphics
@testable import HassDesign
import Testing

/// Short rows fill their section (duo-widths, `.agents/design/duo-widths.md`): the equal-share widths and the whole-track alternative.
struct DynamicGridFillTests {
    private static let gap: CGFloat = 12

    // MARK: Shared widths

    @Test func aLoneTileTakesTheWholeRow() {
        #expect(DynamicGridMetrics.sharedWidths(base: [150.25], available: 637, spacing: Self.gap) == [637])
    }

    @Test func threeTilesShareEqually() {
        let widths = DynamicGridMetrics.sharedWidths(base: [150.25, 150.25, 150.25], available: 637, spacing: Self.gap)
        for width in widths { #expect(abs(width - 204.33) < 0.01) }
    }

    @Test func aVentBesideAPurifierMakeTwoHalves() {
        let widths = DynamicGridMetrics.sharedWidths(base: [150.25, 312.5], available: 637, spacing: Self.gap)
        #expect(widths == [312.5, 312.5])
    }

    @Test func aWiderItemKeepsItsWidthAndTheRestShareWhatIsLeft() {
        let widths = DynamicGridMetrics.sharedWidths(base: [474, 150.25], available: 637, spacing: Self.gap)
        #expect(widths == [474, 151])
    }

    @Test func neverNarrowerThanBaseAndFillsTheRow() {
        let cases: [[CGFloat]] = [[150], [100, 300], [300, 100, 100], [150, 150, 312], [500, 400]]
        for base in cases {
            let widths = DynamicGridMetrics.sharedWidths(base: base, available: 637, spacing: Self.gap)
            for (width, floor) in zip(widths, base) { #expect(width >= floor) }
            let total = widths.reduce(0, +) + Self.gap * CGFloat(base.count - 1)
            if base.reduce(0, +) + Self.gap * CGFloat(base.count - 1) <= 637 { #expect(abs(total - 637) < 0.001) } else { #expect(widths == base) }
        }
    }

    @Test func aFullRowStaysAsItIs() {
        let base: [CGFloat] = [150.25, 150.25, 312.5]
        #expect(DynamicGridMetrics.sharedWidths(base: base, available: 637, spacing: Self.gap) == base)
    }

    @Test func degenerateInputsPassThrough() {
        #expect(DynamicGridMetrics.sharedWidths(base: [], available: 100, spacing: 12).isEmpty)
        #expect(DynamicGridMetrics.sharedWidths(base: [50], available: .infinity, spacing: 12) == [50])
    }

    // MARK: Whole tracks

    private func spans(_ metrics: DynamicGridMetrics, _ input: [Int]) -> [Int] { metrics.fillingPlacements(spans: input).map(\.span) }

    @Test func spareTracksGoToTheNarrowestItemTiesToTheLater() {
        let four = DynamicGridMetrics(width: 637, minCellWidth: 150, maxColumns: 4, spacing: Self.gap)
        #expect(spans(four, [1, 1, 1]) == [1, 1, 2])
        #expect(spans(four, [1]) == [4])
        #expect(spans(four, [1, 1]) == [2, 2])
        #expect(spans(four, [1, 1, 1, 1, 1]) == [1, 1, 1, 1, 4])
        #expect(spans(four, [1, 2, 2]) == [2, 2, 4])
        #expect(spans(four, [1, 2]) == [2, 2])
        let three = DynamicGridMetrics(width: 480, minCellWidth: 150, maxColumns: 4, spacing: Self.gap)
        #expect(three.columns == 3)
        #expect(spans(three, [1, 1, 1, 1, 1]) == [1, 1, 1, 1, 2])
        let placed = four.fillingPlacements(spans: [1, 1, 1, 1, 1])
        #expect(placed.map(\.row) == [0, 0, 0, 0, 1])
        #expect(placed.last?.column == 0)
    }

    @Test func columnsFollowTheNewSpans() {
        let four = DynamicGridMetrics(width: 637, minCellWidth: 150, maxColumns: 4, spacing: Self.gap)
        #expect(four.fillingPlacements(spans: [1, 1, 1]).map(\.column) == [0, 1, 2])
        #expect(four.fillingPlacements(spans: [1, 1]).map(\.column) == [0, 2])
    }

    @Test func aBandIsAWall() {
        // 800 wide with a 40 pt band in the middle: two tracks a side.
        let banded = DynamicGridMetrics(width: 800, minCellWidth: 150, maxColumns: 4, spacing: Self.gap, evenColumns: true, band: 380...420)
        #expect(banded.sideColumns == 2)
        for input in [[1], [1, 1, 1], [1, 1, 1, 1, 1], [2, 1]] {
            for place in banded.fillingPlacements(spans: input) {
                #expect(!(place.column < 2 && place.column + place.span > 2))
            }
        }
        // A lone tile fills only its side.
        #expect(spans(banded, [1]) == [2])
        let three = banded.fillingPlacements(spans: [1, 1, 1])
        #expect(three.map(\.span) == [1, 1, 2])
        #expect(three.map(\.column) == [0, 1, 2])
    }

    @Test func aRowWithAnItemOverTheBandIsLeftAsPlaced() {
        let banded = DynamicGridMetrics(width: 800, minCellWidth: 150, maxColumns: 4, spacing: Self.gap, evenColumns: true, band: 380...420)
        #expect(spans(banded, [3, 1]) == [3, 1])
        #expect(banded.fillSegments(of: [(0, 3), (3, 1)]) == nil)
    }
}
