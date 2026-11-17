import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

/// What a regroup costs when a live update moves many tiles between the state groups (`sh.grid-state-groups@1`; `.agents/design/motion.md`
/// section 6, the regroup exception; `.agents/testing/apple/performance.md`, Layout changes).
///
/// Twenty tiles flip between lit and idle, three times per iteration. Each flip is one box update per tile and one arrangement
/// (`regroupCount`), spanned by one `LayoutChange` interval (page `GridGroups`). The house changes the tiles in the first two tests, so nothing
/// animates (the second adds Reduce Motion); in the third a person's tap comes first, so the moved tiles slide. Metrics: `XCTCPUMetric` and
/// `XCTOSSignpostMetric` on `LayoutChange`. Run it hosted by naming the class in `FENTON_HOSTED_FILTER`; the simulator's numbers are for
/// comparison, not for hitches.
@MainActor
final class UKHostedGridGroupsPerformanceTests: XCTestCase {
    private static let tileCount = 20
    private static let flipsPerIteration = 3

    override func tearDown() async throws {
        UKMotion.reduceMotionOverride = nil
        try await super.tearDown()
    }

    func testTwentyTilesRegroupingCost() throws { try measureFlips(reduceMotion: false, tap: false) }

    func testTwentyTilesRegroupingCostReduceMotion() throws { try measureFlips(reduceMotion: true, tap: false) }

    func testAPersonsTapRegroupCost() throws { try measureFlips(reduceMotion: false, tap: true) }

    // MARK: Private

    private func model(_ index: Int, active: Bool) -> UKGlassTileModel {
        UKGlassTileModel(title: "Light \(index)", subtitle: active ? "On" : "Off", symbol: "lightbulb", family: .neutral, isActive: active, kind: .toggle,
                         identifier: "tile.\(index)")
    }

    private func measureFlips(reduceMotion: Bool, tap: Bool) throws {
        UKMotion.reduceMotionOverride = reduceMotion
        let host = UIViewController()
        let window = HostedPage.show(host, size: CGSize(width: 393, height: 900))
        defer { window.isHidden = true }
        let scroll = UIScrollView(frame: CGRect(x: 0, y: 40, width: 393, height: 800))
        host.view.addSubview(scroll)
        let grid = UKDynamicGridView()
        scroll.addSubview(grid)
        let tiles = (0..<Self.tileCount).map { UKGlassTileView(model: model($0, active: $0 % 2 == 0)) }
        let groups = ServerUIGridGroups(items: [.init(id: "on", title: "On", states: [.active]), .init(id: "off", title: "Off", states: [.idle]),
                                                .init(id: "gone", title: "Not Answering", states: [.unavailable])])
        let grouping = UKServerUIGridGrouping(groups, gridID: "grid", grid: grid, surface: .page)
        grid.regroupItems(grouping.items(tiles.map { ($0, 1) }))
        grid.frame = CGRect(x: 0, y: 0, width: 393, height: grid.sizeThatFits(CGSize(width: 393, height: CGFloat.greatestFiniteMagnitude)).height)
        scroll.contentSize = grid.frame.size
        grid.layoutIfNeeded()
        var even = true
        let press = NSSelectorFromString("pressed:")

        func flip() {
            even.toggle()
            if tap {
                grouping.perform(press, with: PressScript(.began))
                grouping.perform(press, with: PressScript(.ended))
            }
            for (index, tile) in tiles.enumerated() { tile.configure(model(index, active: (index % 2 == 0) == even), animated: false) }
            // The slide (0.3 s) and the interval's end land within this wait.
            RunLoop.main.run(until: Date().addingTimeInterval(tap ? 0.6 : 0.3))
        }

        flip(); flip() // warm up: the first arrangements build the headers
        let before = grouping.regroupCount
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        let signpost = XCTOSSignpostMetric(subsystem: "com.sfenton.home", category: "Performance", name: "LayoutChange")
        measure(metrics: [XCTCPUMetric(), signpost], options: options) {
            for _ in 0..<Self.flipsPerIteration { flip() }
        }
        let arrangements = grouping.regroupCount - before
        XCTAssertGreaterThanOrEqual(arrangements, Self.flipsPerIteration * 3, "each flip is arranged")
        XCTAssertLessThanOrEqual(arrangements, Self.flipsPerIteration * 3 + 3, "one arrangement per flip, never one per tile")
        XCTAssertEqual(grid.items.filter(\.isHeader).count, 2, "two groups hold tiles")
    }
}

/// A long press that reports the state it is made with.
private final class PressScript: UILongPressGestureRecognizer {
    private let scripted: UIGestureRecognizer.State
    init(_ state: UIGestureRecognizer.State) {
        scripted = state
        super.init(target: nil, action: nil)
    }
    override var state: UIGestureRecognizer.State {
        get { scripted }
        set {}
    }
}
