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

    /// A badged bar built the way a sheet builds it (`UKModalTabBar(...).inset()`), laid out once in a window, before any tap.
    private func showPublicBar(selection: LiftSection) -> (UKModalTabBar<LiftSection>, UIWindow) {
        let bar = UKModalTabBar(tabs: LiftSection.allCases, label: "Sections", title: { $0.rawValue }, symbol: { _ in "house" },
                                badge: { _ in 2 }, selection: selection, identifier: "pub.tabs") { _ in }
        let wrapper = bar.inset()
        let host = UIViewController()
        host.view.addSubview(wrapper)
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            wrapper.leadingAnchor.constraint(equalTo: host.view.leadingAnchor), wrapper.trailingAnchor.constraint(equalTo: host.view.trailingAnchor),
            wrapper.topAnchor.constraint(equalTo: host.view.topAnchor),
        ])
        let window = HostedPage.show(host, size: CGSize(width: 393, height: 200))
        host.view.layoutIfNeeded()
        return (bar, window)
    }

    func testThePublicBarShowsAVisibleCapsuleOnItsSelectedSegmentAndFollowsASelection() throws {
        let (bar, window) = showPublicBar(selection: .one)
        defer { window.isHidden = true }
        let lift = try XCTUnwrap(FeatureHost.view("pub.tabs.lift", in: bar), "the capsule exists")
        XCTAssertFalse(lift.isHidden)
        XCTAssertGreaterThan(lift.frame.width, 20, "the capsule has a size before any tap")
        XCTAssertGreaterThanOrEqual(lift.frame.height, 43)
        XCTAssertEqual(lift.layer.cornerRadius, lift.bounds.height / 2, accuracy: 0.5, "a capsule")
        XCTAssertEqual(lift.frame, try XCTUnwrap(FeatureHost.view("pub.tabs.one", in: bar)).frame)
        bar.selection = .three
        let settled = HostedPage.until {
            guard let target = FeatureHost.view("pub.tabs.three", in: bar) else { return false }
            return lift.frame == target.frame
        }
        XCTAssertTrue(settled, "the capsule follows the selection to the third segment")
        XCTAssertEqual(lift.layer.cornerRadius, lift.bounds.height / 2, accuracy: 0.5)
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
