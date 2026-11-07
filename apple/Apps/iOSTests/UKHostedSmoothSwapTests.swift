import UIKit
import XCTest
@testable import HassUI

/// A panel that swaps its content: with Reduce Motion on the new content is there at once, with no fade.
@MainActor
final class UKHostedSmoothSwapTests: XCTestCase {
    func testReduceMotionSwapsContentAtOnceAndAnUnchangedKeyDoesNothing() {
        UKMotion.reduceMotionOverride = true
        defer { UKMotion.reduceMotionOverride = nil }
        var swaps: [Int] = []
        let swap = UKSmoothContentSwapView<Int>(initial: 0) { key in
            let label = UILabel()
            label.text = "Panel \(key)"
            return label
        }
        swap.didSwap = { swaps.append($0) }
        let window = HostedPage.show(UIViewController(), size: CGSize(width: 300, height: 200))
        defer { window.isHidden = true }
        window.rootViewController?.view.addSubview(swap)
        swap.frame = CGRect(x: 0, y: 0, width: 300, height: 100)

        swap.show(2)
        XCTAssertEqual(swap.displayed, 2, "no fade: the new content is up straight away")
        XCTAssertEqual(swaps, [2])
        XCTAssertTrue(HostedPage.labels(in: swap).contains("Panel 2"))
        swap.show(2)
        XCTAssertEqual(swaps, [2], "asking for what is shown swaps nothing")
        swap.show(0)
        XCTAssertEqual(swaps, [2, 0])
        XCTAssertTrue(HostedPage.labels(in: swap).contains("Panel 0"))
    }
}
