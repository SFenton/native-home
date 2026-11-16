import CoreGraphics
@testable import HassDesign
import Testing

/// A tile grid's least columns (`sh.grid-min-columns@1`): the floor on the cell minimum. The floor sets the track count only; it never caps a tile's span.
struct DynamicGridMinimumColumnsTests {
    private let spacing: CGFloat = 12

    private func columns(width: CGFloat, minimum: CGFloat = 150, maxColumns: Int = 4, least: Int?) -> Int {
        let cell = DynamicGridMetrics.floorMinimum(width: width, minCellWidth: minimum, minimumColumns: least, spacing: spacing)
        return DynamicGridMetrics(width: width, minCellWidth: cell, maxColumns: maxColumns, spacing: spacing).columns
    }

    @Test func aNarrowWidthHoldsTwoColumnsOnlyWithTheFloor() {
        // An iPhone's 343 pt of content: 150 pt cells fit twice already; a 300 pt cell minimum would give one.
        #expect(columns(width: 343, minimum: 300, least: nil) == 1)
        #expect(columns(width: 343, minimum: 300, least: 2) == 2)
        #expect(columns(width: 343, least: 2) == 2)
    }

    @Test func theFloorNeverRaisesTheMinimumOrTheColumnCount() {
        #expect(DynamicGridMetrics.floorMinimum(width: 1000, minCellWidth: 150, minimumColumns: 2, spacing: spacing) == 150)
        #expect(columns(width: 1000, least: 2) == 4, "a wide grid still grows past the floor, up to its most")
        #expect(columns(width: 1000, maxColumns: 2, least: 2) == 2)
    }

    @Test func theFloorLeavesTheMinimumAloneWithoutAMeasuredWidthOrAFloor() {
        #expect(DynamicGridMetrics.floorMinimum(width: 343, minCellWidth: 150, minimumColumns: nil, spacing: spacing) == 150)
        #expect(DynamicGridMetrics.floorMinimum(width: 343, minCellWidth: 150, minimumColumns: 1, spacing: spacing) == 150)
        #expect(DynamicGridMetrics.floorMinimum(width: .infinity, minCellWidth: 150, minimumColumns: 2, spacing: spacing) == 150)
        #expect(DynamicGridMetrics.floorMinimum(width: 0, minCellWidth: 150, minimumColumns: 2, spacing: spacing) == 150)
        #expect(DynamicGridMetrics.floorMinimum(width: 10, minCellWidth: 150, minimumColumns: 4, spacing: spacing) == 150, "no room for the gutters")
    }

    @Test func theFloorIsTheCellWidthTheLeastColumnsShare() {
        // 343 pt in two columns: (343 - 12) / 2 = 165.5; in three: (343 - 24) / 3.
        #expect(DynamicGridMetrics.floorMinimum(width: 343, minCellWidth: 400, minimumColumns: 2, spacing: spacing) == 165.5)
        #expect(DynamicGridMetrics.floorMinimum(width: 343, minCellWidth: 400, minimumColumns: 3, spacing: spacing) == 319.0 / 3)
        #expect(columns(width: 343, minimum: 400, least: 3) == 3)
    }
}
