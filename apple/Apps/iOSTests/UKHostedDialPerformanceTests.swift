import HassCore
import UIKit
import XCTest
@testable import HassUI

/// What a needle turn costs when a live update turns many compasses at once (`.agents/testing/apple/performance.md`, Dial needle).
///
/// Twenty weather compasses turn between two bearings, three times per iteration, with Reduce Motion off and on. Each turn is one box update
/// per dial, and each animated turn opens one `LayoutChange` interval (page `Dial`) that ends when the glide settles. Metrics: `XCTCPUMetric`
/// and `XCTOSSignpostMetric` on `LayoutChange`. Run it hosted by naming the class in `FENTON_HOSTED_FILTER`; the simulator's numbers are for
/// comparison, not for hitches.
@MainActor
final class UKHostedDialPerformanceTests: XCTestCase {
    private static let dialCount = 20
    private static let turnsPerIteration = 3

    override func tearDown() async throws {
        UKMotion.reduceMotionOverride = nil
        try await super.tearDown()
    }

    func testTwentyNeedlesTurningCost() {
        measureTurns(reduceMotion: false)
    }

    func testTwentyNeedlesTurningCostReduceMotion() {
        measureTurns(reduceMotion: true)
    }

    // MARK: Private

    private func measureTurns(reduceMotion: Bool) {
        UKMotion.reduceMotionOverride = reduceMotion
        let controller = UIViewController()
        let window = HostedPage.show(controller, size: CGSize(width: 393, height: 1200))
        defer { window.isHidden = true }
        let compasses = (0..<Self.dialCount).map { index -> UKWeatherCompassView in
            let compass = UKWeatherCompassView(sourceDegrees: 350)
            compass.frame = CGRect(x: 20, y: 4 + CGFloat(index) * 58, width: 52, height: 52)
            controller.view.addSubview(compass)
            return compass
        }
        controller.view.layoutIfNeeded()
        var east = false

        func turn() {
            east.toggle()
            for compass in compasses { compass.update(sourceDegrees: east ? 10 : 350) }
            // The 0.3 s glide and the interval's end land within this wait.
            RunLoop.main.run(until: Date().addingTimeInterval(reduceMotion ? 0.1 : 0.5))
        }

        turn(); turn() // warm up: the first turns build the transitions
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        let signpost = XCTOSSignpostMetric(subsystem: "com.sfenton.home", category: "Performance", name: "LayoutChange")
        measure(metrics: [XCTCPUMetric(), signpost], options: options) {
            for _ in 0..<Self.turnsPerIteration { turn() }
        }
        XCTAssertTrue(compasses.allSatisfy { $0.face.isNeedleShown }, "every compass still shows a needle")
    }
}
