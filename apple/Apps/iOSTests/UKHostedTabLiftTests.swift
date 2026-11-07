import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

private enum LiftSection: String, CaseIterable, Identifiable {
    case one, two, three, four
    var id: String { rawValue }
}

/// The selected-tab lift of the badged tab bar (Your Summary) stays on its segment, inside the bar, whatever width the bar is
/// laid out at, so it never spills past the bar after the app returns from the background.
@MainActor
final class UKHostedTabLiftTests: XCTestCase {
    private func makeBar(selection: LiftSection) -> UKBadgedTabSegments<LiftSection> {
        let segments = LiftSection.allCases.map { ModalTabSegment(item: $0, title: $0.rawValue, symbol: "house", badge: 2) }
        return UKBadgedTabSegments(segments: segments, showsTitles: false, selection: selection, identifier: "lift", label: "Sections")
    }

    private func lift(of bar: UIView) -> UIView? {
        bar.subviews.first { !($0 is UIStackView) }
    }

    private func layout(_ bar: UIView, width: CGFloat) {
        bar.frame = CGRect(x: 0, y: 100, width: width, height: 52)
        bar.setNeedsLayout()
        bar.layoutIfNeeded()
    }

    private func assertLiftFits(_ bar: UIView, index: Int, file: StaticString = #filePath, line: UInt = #line) {
        guard let row = bar.subviews.compactMap({ $0 as? UIStackView }).first, let lift = lift(of: bar) else { return XCTFail("no lift", file: file, line: line) }
        let segment = row.arrangedSubviews[index]
        XCTAssertEqual(lift.frame, segment.frame, "the lift is on the selected segment", file: file, line: line)
        XCTAssertTrue(bar.bounds.contains(lift.frame), "the lift is inside the bar: \(lift.frame) in \(bar.bounds)", file: file, line: line)
    }

    func testTheLiftFollowsItsSegmentWhenTheBarNarrowsAndWidens() {
        for (selection, index) in [(LiftSection.four, 3), (.two, 1)] {
            let bar = makeBar(selection: selection)
            let host = UIViewController()
            let window = HostedPage.show(host)
            defer { window.isHidden = true }
            host.view.addSubview(bar)
            layout(bar, width: 600)
            assertLiftFits(bar, index: index)
            layout(bar, width: 320)
            assertLiftFits(bar, index: index)
            layout(bar, width: 500)
            assertLiftFits(bar, index: index)
        }
    }
}
