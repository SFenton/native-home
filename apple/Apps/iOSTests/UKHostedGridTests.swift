import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

/// The shared tile grid: columns from the width, spans, headings, equal rows, the hinge band and the collection layout.
@MainActor
final class UKHostedGridTests: XCTestCase {
    private func solve(width: CGFloat, spans: [Int], headers: [Bool]? = nil, minimums: [CGFloat] = [], config: UKGridConfiguration = UKGridConfiguration(),
                       heights: [CGFloat]? = nil) -> UKGridSolution {
        UKGridSolver.solve(width: width, configuration: config, spans: spans, headers: headers ?? spans.map { _ in false }, minimums: minimums) { i, _ in
            heights?[i] ?? 60
        }
    }

    func testWiderGridsFlowMoreTilesPerRow() {
        let narrow = solve(width: 320, spans: Array(repeating: 1, count: 6))
        let wide = solve(width: 1000, spans: Array(repeating: 1, count: 6))
        XCTAssertGreaterThan(narrow.rowHeights.count, wide.rowHeights.count)
        XCTAssertEqual(narrow.frames.count, 6)
        XCTAssertLessThan(narrow.frames[0].width, 320)
    }

    func testHeadingsTakeAWholeRowAndEqualRowsMatchTheTallestTile() {
        var config = UKGridConfiguration()
        config.equalRowHeights = true
        let solution = solve(width: 700, spans: [Int.max, 1, 1, 1, 1], headers: [true, false, false, false, false], config: config,
                             heights: [30, 50, 90, 50, 70])
        XCTAssertEqual(solution.frames[0].width, 700, accuracy: 1)
        let tiles = Set(solution.rowHeights.dropFirst())
        XCTAssertEqual(tiles.count, 1, "every tile row is as tall as the tallest tile")
        XCTAssertEqual(solution.rowHeights[0], 30, "the heading keeps its height")
    }

    func testATileThatDeclaresAMinimumWidthTakesMoreTracks() {
        let plain = solve(width: 700, spans: [1, 1, 1])
        let wide = solve(width: 700, spans: [1, 1, 1], minimums: [0, 360, 0])
        XCTAssertGreaterThan(wide.frames[1].width, plain.frames[1].width)
    }

    func testAHingeBandKeepsTilesOffTheFold() {
        var config = UKGridConfiguration()
        config.evenColumns = true
        config.hingeBand = 340...360
        let solution = solve(width: 700, spans: Array(repeating: 1, count: 4), config: config)
        for frame in solution.frames { XCTAssertFalse(frame.minX < 360 && frame.maxX > 340, "\(frame) crosses the hinge band") }
    }

    func testTheViewGridPlacesItemsAndReportsItsHeight() {
        let grid = UKDynamicGridView()
        let host = UIViewController()
        let window = HostedPage.show(host)
        defer { window.isHidden = true }
        host.view.addSubview(grid)
        grid.frame = CGRect(x: 0, y: 60, width: 393, height: 10)
        let views = (0..<5).map { _ -> UIView in UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 10)) }
        let title = UILabel(); title.text = "Lights"
        grid.setItems([UKGridItem(title, isHeader: true)] + views.map { UKGridItem($0) })
        grid.layoutIfNeeded()
        XCTAssertEqual(grid.items.count, 6)
        XCTAssertEqual(title.frame.width, 393, accuracy: 1, "the heading spans the row")
        let height = grid.gridHeight(forWidth: 393)
        XCTAssertGreaterThan(height, 0)
        XCTAssertEqual(grid.sizeThatFits(CGSize(width: 393, height: 0)).height, height, accuracy: 0.5)
        let narrowHeight = grid.gridHeight(forWidth: 200)
        XCTAssertGreaterThanOrEqual(narrowHeight, height)
        XCTAssertGreaterThan(grid.intrinsicContentSize.height, 0)

        grid.configuration.equalRowHeights = true
        grid.hinge = CGRect(x: 190, y: 0, width: 12, height: 852)
        grid.invalidateLayout(); grid.invalidateMeasure(); grid.invalidateMeasurements()
        grid.layoutIfNeeded()
        grid.followsFold = true
        grid.hinge = nil
        grid.followsFold = false
        grid.setItems([])
        grid.layoutIfNeeded()
        XCTAssertEqual(grid.items.count, 0)
    }

    func testTheCollectionLayoutFlowsSectionsAsOneGrid() {
        final class Source: NSObject, UICollectionViewDataSource, UKDynamicGridLayoutDelegate {
            func numberOfSections(in collectionView: UICollectionView) -> Int { 2 }
            func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { section == 0 ? 1 : 5 }
            func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: UKTileCell.reuseIdentifier, for: indexPath) as! UKTileCell
                cell.host(UIView())
                cell.host(UIView())
                return cell
            }
            func gridLayout(_ layout: UKDynamicGridLayout, isHeaderAt indexPath: IndexPath) -> Bool { indexPath.section == 0 }
            func gridLayout(_ layout: UKDynamicGridLayout, spanAt indexPath: IndexPath) -> Int { indexPath.section == 0 ? Int.max : 1 }
            func gridLayout(_ layout: UKDynamicGridLayout, heightAt indexPath: IndexPath, width: CGFloat) -> CGFloat { 50 }
        }
        let source = Source()
        let layout = UKDynamicGridLayout()
        layout.delegate = source
        layout.contentInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        let view = UICollectionView(frame: CGRect(x: 0, y: 0, width: 393, height: 600), collectionViewLayout: layout)
        view.register(UKTileCell.self, forCellWithReuseIdentifier: UKTileCell.reuseIdentifier)
        view.dataSource = source
        let host = UIViewController()
        let window = HostedPage.show(host)
        defer { window.isHidden = true }
        host.view.addSubview(view)
        view.layoutIfNeeded()
        let heading = layout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))
        XCTAssertEqual(heading?.frame.width ?? 0, 393 - 32, accuracy: 1)
        XCTAssertEqual(heading?.frame.minX, 16)
        let visible = layout.layoutAttributesForElements(in: CGRect(x: 0, y: 0, width: 393, height: 600)) ?? []
        XCTAssertEqual(visible.count, 6)
        XCTAssertEqual(layout.layoutAttributesForElements(in: CGRect(x: 0, y: 5000, width: 393, height: 10))?.count, 0)
        XCTAssertNil(layout.layoutAttributesForItem(at: IndexPath(item: 9, section: 1)))
        XCTAssertGreaterThan(layout.collectionViewContentSize.height, 100)
        XCTAssertTrue(layout.shouldInvalidateLayout(forBoundsChange: CGRect(x: 0, y: 0, width: 500, height: 600)))
        XCTAssertFalse(layout.shouldInvalidateLayout(forBoundsChange: CGRect(x: 0, y: 40, width: 393, height: 600)))
        layout.hinge = CGRect(x: 190, y: 0, width: 12, height: 852)
        layout.configuration.evenColumns = true
        view.layoutIfNeeded()
        view.reloadData()
        view.layoutIfNeeded()
        let cell = view.cellForItem(at: IndexPath(item: 0, section: 1)) as? UKTileCell
        cell?.prepareForReuse()
        XCTAssertNotNil(cell?.hosted)
    }
}
