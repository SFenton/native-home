import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

/// What the state-styled tile's motion costs when a live update flips many tiles at once: the colour cross-fade, the disc and arc cross-fade and
/// the warning pulse (`.agents/testing/apple/performance.md`, State-styled tile motion; `.agents/patterns/motion.md`).
///
/// Twenty tiles flip between resting and warning, three times per iteration, with Reduce Motion off and on. Each flip is one box update per
/// tile (`configure`), and each animated change opens one `LayoutChange` interval (page `StateTile`) that ends when its fade settles.
/// Metrics: `XCTCPUMetric` and `XCTOSSignpostMetric` on `LayoutChange`. Run it hosted by naming the class in `FENTON_HOSTED_FILTER`; the
/// simulator's numbers are for comparison, not for hitches.
@MainActor
final class UKHostedStateTilePerformanceTests: XCTestCase {
    private static let tileCount = 20
    private static let flipsPerIteration = 3

    override func tearDown() async throws {
        UKMotion.reduceMotionOverride = nil
        try await super.tearDown()
    }

    func testTwentyTilesFlippingStateCost() {
        measureFlips(reduceMotion: false)
    }

    func testTwentyTilesFlippingStateCostReduceMotion() {
        measureFlips(reduceMotion: true)
    }

    // MARK: Private

    private func model(_ warning: Bool, index: Int) -> UKGlassTileModel {
        let words = warning ? "Open" : "Closed"
        var model = UKGlassTileModel(title: "Door \(index)", subtitle: words, symbol: "door.garage.closed", family: .contact, isActive: warning,
                                     behavior: .navigate, identifier: "tile.\(index)")
        model.look = StateTileLook(icon: "door.garage.closed", colour: .init(warning ? .warning : .resting, active: warning),
                                   indicator: warning ? .pulse : .none, text: words, hasAction: false)
        return model
    }

    private func measureFlips(reduceMotion: Bool) {
        UKMotion.reduceMotionOverride = reduceMotion
        let controller = UIViewController()
        let window = HostedPage.show(controller, size: CGSize(width: 393, height: 900))
        defer { window.isHidden = true }
        let tiles = (0..<Self.tileCount).map { index -> UKGlassTileView in
            let tile = UKGlassTileView(model: model(false, index: index))
            tile.frame = CGRect(x: 20, y: 4 + CGFloat(index) * 44, width: 353, height: 40)
            controller.view.addSubview(tile)
            return tile
        }
        controller.view.layoutIfNeeded()
        var warning = false

        func flip() {
            warning.toggle()
            for (index, tile) in tiles.enumerated() { tile.configure(model(warning, index: index), animated: true) }
            // The colour fade (0.6 s, 0.2 s under Reduce Motion) and the interval's end land within this wait.
            RunLoop.main.run(until: Date().addingTimeInterval(reduceMotion ? 0.4 : 0.9))
        }

        flip(); flip() // warm up: the first flips build the transitions and layers
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        let signpost = XCTOSSignpostMetric(subsystem: "com.sfenton.home", category: "Performance", name: "LayoutChange")
        measure(metrics: [XCTCPUMetric(), signpost], options: options) {
            for _ in 0..<Self.flipsPerIteration { flip() }
        }
        let expected = warning ? "Open" : "Closed"
        XCTAssertTrue(tiles.allSatisfy { $0.model.look?.text == expected }, "every tile ends on the last state it was given")
    }
}
