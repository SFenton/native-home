import CoreGraphics
@testable import HassDesign
import SwiftUI
import Testing

struct DynamicGridMetricsTests {
    @Test func columnsGrowWithWidthUpToMax() {
        #expect(DynamicGridMetrics(width: 343, minCellWidth: 160, maxColumns: 4, spacing: 12).columns == 2)
        #expect(DynamicGridMetrics(width: 1000, minCellWidth: 160, maxColumns: 4, spacing: 12).columns == 4)
        #expect(DynamicGridMetrics(width: 100, minCellWidth: 160, maxColumns: 4, spacing: 12).columns == 1)
    }

    @Test func leftoverWidthIsSharedEqually() {
        let metrics = DynamicGridMetrics(width: 343, minCellWidth: 160, maxColumns: 4, spacing: 12)
        #expect(metrics.cellWidth == 165.5)
        #expect(metrics.width(span: 2, spacing: 12) == 343)
    }

    @Test func spansWrapAndClamp() {
        let metrics = DynamicGridMetrics(width: 343, minCellWidth: 160, maxColumns: 4, spacing: 12)
        let placements = metrics.placements(spans: [1, 2, 5, 1])
        #expect(placements.map(\.row) == [0, 1, 2, 3])
        #expect(placements.map(\.span) == [1, 2, 2, 1])
        #expect(placements.map(\.column) == [0, 0, 0, 0])
    }

    @Test func incompleteRowStaysLeading() {
        let metrics = DynamicGridMetrics(width: 520, minCellWidth: 160, maxColumns: 4, spacing: 12)
        let placements = metrics.placements(spans: [1, 1, 1, 1])
        #expect(metrics.columns == 3)
        #expect(placements.last?.row == 1)
        #expect(placements.last?.column == 0)
    }

    /// An unbounded size probe (`.infinity`) must not trap converting the column count to `Int`.
    @Test func unboundedWidthUsesEveryColumnAtMinimumWidth() {
        for width in [CGFloat.infinity, .nan] {
            let metrics = DynamicGridMetrics(width: width, minCellWidth: 160, maxColumns: 4, spacing: 12)
            #expect(metrics.columns == 4)
            #expect(metrics.cellWidth == 160)
        }
    }

    // MARK: Even columns across a hinge

    @Test func evenRoundingDropsOddCountsToTheEvenBelow() {
        #expect([1, 2, 3, 4, 5, 6, 7].map(DynamicGridMetrics.evenRounded) == [1, 2, 2, 4, 4, 6, 6])
        #expect(DynamicGridMetrics.evenRounded(0) == 1)
    }

    @Test func hingeGridsRoundOddFitsDownAndShareTheLeftoverWidth() {
        // 3 fit at 802 pt (200 min, 12 spacing); across a hinge that becomes 2 wider tracks.
        let plain = DynamicGridMetrics(width: 802, minCellWidth: 200, maxColumns: 6, spacing: 12)
        let hinge = DynamicGridMetrics(width: 802, minCellWidth: 200, maxColumns: 6, spacing: 12, evenColumns: true)
        #expect(plain.columns == 3)
        #expect(hinge.columns == 2)
        #expect(hinge.cellWidth == 395)
        // Tiles (a 150 pt minimum) never pass four a row (owner, 2026-10-30), so five fitting is four, even or not.
        #expect(DynamicGridMetrics(width: 802, minCellWidth: 150, maxColumns: 6, spacing: 12).columns == 4)
    }

    @Test func hingeGridsLeaveEvenAndSingleCountsAlone() {
        #expect(DynamicGridMetrics(width: 520, minCellWidth: 160, maxColumns: 4, spacing: 12, evenColumns: true).columns == 2)
        #expect(DynamicGridMetrics(width: 1000, minCellWidth: 160, maxColumns: 4, spacing: 12, evenColumns: true).columns == 4)
        #expect(DynamicGridMetrics(width: 100, minCellWidth: 160, maxColumns: 4, spacing: 12, evenColumns: true).columns == 1)
        // The cap counts first: three allowed columns across a hinge is two.
        #expect(DynamicGridMetrics(width: 1000, minCellWidth: 160, maxColumns: 3, spacing: 12, evenColumns: true).columns == 2)
    }

    /// A tile floor of four columns at iPad Pro 11 portrait (content about 802 pt) for the standard 150 pt tile.
    @Test func standardTilesReachFourColumnsAtIPadPortrait() {
        for width in [CGFloat(802), 744] {
            #expect(DynamicGridMetrics(width: width, minCellWidth: 150, maxColumns: 6, spacing: HassTokensForTests.m).columns >= 4)
        }
        // And still two on a phone.
        #expect(DynamicGridMetrics(width: 358, minCellWidth: 150, maxColumns: 6, spacing: HassTokensForTests.m).columns == 2)
    }

    @MainActor @Test func unboundedWidthDoesNotTrapInLayout() {
        #expect(DynamicGridMetrics(width: .infinity, minCellWidth: 150, maxColumns: 4, spacing: 12).columns == 4)
        let grid = DynamicGridLayout { ForEach(0..<5, id: \.self) { Text("Tile \($0)") } }
        let probed = HStack { grid.frame(maxWidth: .infinity) }.fixedSize(horizontal: true, vertical: false)
        #expect(ImageRenderer(content: probed).cgImage != nil)
    }
}

private enum HassTokensForTests { static let m: CGFloat = 12 }

/// The layout reads the window's hinge from the environment.
@MainActor
struct DynamicGridHingeTests {
    private func height(hinge: CGRect?) -> CGFloat {
        let grid = DynamicGridLayout(minCellWidth: 200, maxColumns: 6, spacing: 12) {
            ForEach(0..<3, id: \.self) { _ in Color.red.frame(height: 40) }
        }
        return UIHostingSizing.measure(grid.environment(\.windowHinge, hinge), width: 802)
    }

    /// Three 200 pt cells fit one row at 802 pt; across a hinge the grid takes two tracks, so the third wraps.
    @Test func gridWrapsToEvenColumnsOnlyWithAHinge() {
        #expect(abs(height(hinge: nil) - 40) < 0.5)
        #expect(abs(height(hinge: CGRect(x: 455, y: 0, width: 41, height: 669)) - (40 + 12 + 40)) < 0.5)
    }
}

/// Equal row heights (Lights sheet, room details): every tile row takes the tallest tile's height; headings keep theirs.
@MainActor
struct DynamicGridEqualHeightTests {
    @Test func equalizedRaisesTileRowsAndKeepsHeadings() {
        #expect(DynamicGridLayout.equalized([20, 88, 120, 20, 96], headerRows: [0, 3]) == [20, 120, 120, 20, 120])
        #expect(DynamicGridLayout.equalized([88, 104], headerRows: []) == [104, 104])
        #expect(DynamicGridLayout.equalized([30], headerRows: [0]) == [30])
        #expect(DynamicGridLayout.equalized([], headerRows: []) == [])
    }

}

/// Measures a view's height at a width.
@MainActor
enum UIHostingSizing {
    static func measure(_ view: some View, width: CGFloat) -> CGFloat {
        #if canImport(UIKit)
        let controller = UIHostingController(rootView: view)
        return controller.sizeThatFits(in: CGSize(width: width, height: .infinity)).height
        #else
        let controller = NSHostingController(rootView: view)
        return controller.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height
        #endif
    }
}
