import HassCore
import UIKit
import XCTest
@testable import HassUI

/// The buttons over the map (`sh.surface-controls@1`): where each corner group sits, what the fit rule shows, how More opens, and what
/// VoiceOver reads. Each case runs the card widths of the iPhone, Duo and iPad families, so the same file serves all three runs.
@MainActor
final class UKHostedMapControlsTests: XCTestCase {
    /// The map card's width on an iPhone (375 pt screen), a Duo (466 pt) and an iPad (834 pt), less the 16 pt page margins.
    private static let widths: [CGFloat] = [343, 434, 802]

    override func tearDown() async throws {
        HostedPage.hideTracked()
        try await super.tearDown()
    }

    private func items(_ count: Int, enabled: Bool = true, prefix: String = "b") -> [UKMapControlItem] {
        (0..<count).map {
            UKMapControlItem(id: "\(prefix)\($0)", symbol: "lightbulb", label: "Button \($0)", hint: "Does \($0).",
                             value: enabled ? nil : "Blocked", identifier: "map.control.\(prefix)\($0)", isEnabled: enabled)
        }
    }

    private func controls(_ groups: [UKMapControlGroup], width: CGFloat, height: CGFloat = 300,
                          pressed: ((String) -> Void)? = nil) -> (UKMapControlsView, UIWindow) {
        let host = UIViewController()
        let view = UKMapControlsView()
        view.frame = CGRect(x: 0, y: 0, width: width, height: height)
        view.onPress = pressed
        host.view.addSubview(view)
        let window = HostedPage.show(host, size: HostedPage.inScene(CGSize(width: width, height: height)))
        view.apply(groups)
        view.layoutIfNeeded()
        return (view, window)
    }

    private func group(_ corner: MapControlCorner, _ axis: MapControlAxis, _ items: [UKMapControlItem]) -> UKMapControlGroup {
        UKMapControlGroup(corner: corner, axis: axis, items: items)
    }

    // MARK: UX

    /// One button at top leading is the map as it has always been: a 44 pt circle 8 pt in from the corner.
    func testOneButtonIsTheDefaultCircleAtTopLeading() throws {
        for width in Self.widths {
            let locate = UKMapControlItem(id: "locate", symbol: "scope", label: "Locate", hint: "Asks the robot to play a sound.",
                                          value: nil, identifier: "vacuum.locate")
            let (view, window) = controls([group(.topLeading, .column, [locate])], width: width)
            defer { window.isHidden = true }
            let frame = try XCTUnwrap(view.frame(of: .topLeading), "width \(width)")
            XCTAssertEqual(frame, CGRect(x: 8, y: 8, width: 44, height: 44), "width \(width)")
            XCTAssertEqual(view.occupiedCorners, [.topLeading])
            XCTAssertNotNil(view.button(identifier: "vacuum.locate"))
        }
    }

    /// A row at top trailing and a column at bottom leading sit 8 pt in, in authored order.
    func testARowAndAColumnSitInTheirCornersInOrder() throws {
        for width in Self.widths {
            let (view, window) = controls([group(.topTrailing, .row, items(3, prefix: "r")), group(.bottomLeading, .column, items(2, prefix: "c"))],
                                          width: width)
            defer { window.isHidden = true }
            let row = try XCTUnwrap(view.frame(of: .topTrailing), "width \(width)")
            XCTAssertEqual(row, CGRect(x: width - 8 - 132, y: 8, width: 132, height: 44), "width \(width)")
            let column = try XCTUnwrap(view.frame(of: .bottomLeading), "width \(width)")
            XCTAssertEqual(column, CGRect(x: 8, y: 300 - 8 - 88, width: 44, height: 88), "width \(width)")
            let xs = ["r0", "r1", "r2"].compactMap { view.button(identifier: "map.control.\($0)") }.map { $0.convert($0.bounds, to: view).minX }
            XCTAssertEqual(xs, xs.sorted(), "authored order runs leading to trailing (width \(width))")
            let ys = ["c0", "c1"].compactMap { view.button(identifier: "map.control.\($0)") }.map { $0.convert($0.bounds, to: view).minY }
            XCTAssertEqual(ys, ys.sorted(), "authored order runs top to bottom (width \(width))")
        }
    }

    /// Eight buttons in a column on a short card overflow by the shared rule: k - 1 shown plus a More menu of the rest, in order.
    func testAnOverflowingColumnShowsKMinusOneAndAMoreMenu() throws {
        for width in Self.widths {
            let (view, window) = controls([group(.topLeading, .column, items(8))], width: width, height: 200)
            defer { window.isHidden = true }
            let expected = MapControlFit.fit(width: width, height: 200, groups: [.init(corner: .topLeading, axis: .column, count: 8)])[0]
            XCTAssertEqual(view.fit.first, expected, "width \(width)")
            XCTAssertTrue(expected.more, "eight buttons do not fit in a short column at width \(width) or the case proves nothing")
            let more = try XCTUnwrap(view.button(identifier: "map.controls.more.top-leading"), "width \(width)")
            XCTAssertTrue(more is UIButton)
            XCTAssertTrue((more as? UIButton)?.showsMenuAsPrimaryAction == true)
            let titles = (more as? UIButton)?.menu?.children.map(\.title)
            XCTAssertEqual(titles, (expected.shown..<8).map { "Button \($0)" }, "width \(width)")
            for index in 0..<expected.shown { XCTAssertNotNil(view.button(identifier: "map.control.b\(index)"), "width \(width)") }
            XCTAssertNil(view.button(identifier: "map.control.b\(expected.shown)"), "a hidden button is only in the menu (width \(width))")
        }
    }

    /// A tap runs the button's id; a tap beside the groups falls through to the map.
    func testATapRunsItsButtonAndTheRestPassesThrough() throws {
        for width in Self.widths {
            var pressed: [String] = []
            let (view, window) = controls([group(.topLeading, .row, items(2))], width: width) { pressed.append($0) }
            defer { window.isHidden = true }
            let button = try XCTUnwrap(view.button(identifier: "map.control.b1"), "width \(width)")
            button.sendActions(for: .touchUpInside)
            XCTAssertEqual(pressed, ["b1"], "width \(width)")
            XCTAssertFalse(view.point(inside: CGPoint(x: width / 2, y: 150), with: nil), "the map takes taps in the middle (width \(width))")
            XCTAssertTrue(view.point(inside: CGPoint(x: 20, y: 20), with: nil))
        }
    }

    /// A button that goes away leaves its neighbours in place and the corner empty when none is left.
    func testAnEmptyGroupDrawsNothing() throws {
        for width in Self.widths {
            let (view, window) = controls([group(.topLeading, .row, items(2))], width: width)
            defer { window.isHidden = true }
            view.apply([group(.topLeading, .row, [])])
            view.layoutIfNeeded()
            XCTAssertNil(view.frame(of: .topLeading), "width \(width)")
            XCTAssertTrue(view.occupiedCorners.isEmpty)
        }
    }

    // MARK: Accessibility

    /// VoiceOver reads corner by corner, in authored order; a dimmed button says why as its value and is not enabled.
    func testVoiceOverReadsLabelsHintsAndTheReasonForADimmedButton() throws {
        for width in Self.widths {
            var list = items(2)
            list[1].isEnabled = false
            list[1].value = "The robot is already docked."
            let (view, window) = controls([group(.topLeading, .row, list), group(.bottomTrailing, .column, items(1, prefix: "z"))], width: width)
            defer { window.isHidden = true }
            let elements = controlsInOrder(view)
            XCTAssertEqual(elements.map(\.accessibilityLabel), ["Button 0", "Button 1", "Button 0"], "width \(width)")
            XCTAssertEqual(elements[0].accessibilityHint, "Does 0.")
            XCTAssertNil(elements[0].accessibilityValue)
            XCTAssertTrue(elements[1].accessibilityTraits.contains(.notEnabled))
            XCTAssertEqual(elements[1].accessibilityValue, "The robot is already docked.")
            XCTAssertTrue(elements.allSatisfy { $0.accessibilityTraits.contains(.button) })
            XCTAssertTrue(elements.allSatisfy { $0.bounds.width >= 44 && $0.bounds.height >= 44 }, "every target is at least 44 pt (width \(width))")
        }
    }

    /// The More button names itself and says what it holds; the menu rows keep each hidden button's words.
    func testMoreIsNamedForVoiceOver() throws {
        for width in Self.widths {
            let (view, window) = controls([group(.bottomTrailing, .column, items(8))], width: width, height: 200)
            defer { window.isHidden = true }
            let more = try XCTUnwrap(view.button(identifier: "map.controls.more.bottom-trailing"), "width \(width)")
            XCTAssertEqual(more.accessibilityLabel, "More Map Controls")
            XCTAssertNotNil(more.accessibilityHint)
            XCTAssertTrue(more.accessibilityTraits.contains(.button))
        }
    }

    /// Under a large Dynamic Type size the buttons keep their 44 pt target and the groups stay in their corners.
    func testLargeTextKeepsTheTargetsAndCorners() throws {
        for width in Self.widths {
            let (view, window) = controls([group(.topLeading, .row, items(3))], width: width)
            defer { window.isHidden = true }
            view.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
            view.layoutIfNeeded()
            XCTAssertEqual(view.frame(of: .topLeading), CGRect(x: 8, y: 8, width: 132, height: 44), "width \(width)")
        }
    }

    /// The buttons in the order VoiceOver reads them: top to bottom, then leading to trailing.
    private func controlsInOrder(_ view: UIView) -> [UIControl] {
        func all(_ v: UIView) -> [UIControl] { (v.isHidden ? [] : v.subviews.flatMap(all)) + ((v as? UIControl).map { [$0] } ?? []) }
        return all(view).filter(\.isAccessibilityElement).sorted {
            let a = $0.convert($0.bounds, to: view), b = $1.convert($1.bounds, to: view)
            return a.minY != b.minY ? a.minY < b.minY : a.minX < b.minX
        }
    }

    /// Walks the accessibility tree the way VoiceOver does: a container's `accessibilityElements`, else its subviews.
    private func readLabels(_ view: UIView) -> [String] {
        if view.isAccessibilityElement { return [view.accessibilityLabel ?? ""] }
        return view.subviews.filter { !$0.isHidden && $0.alpha > 0 }.flatMap(readLabels)
    }

    /// Each button is read once, in order: the group's glass and the icons add no second element.
    func testEachButtonIsReadOnce() throws {
        for width in Self.widths {
            let locate = UKMapControlItem(id: "locate", symbol: "scope", label: "Locate", hint: nil, value: nil, identifier: "vacuum.locate")
            let (view, window) = controls([group(.topLeading, .column, [locate]), group(.topTrailing, .row, items(2))], width: width)
            defer { window.isHidden = true }
            XCTAssertEqual(readLabels(window), ["Locate", "Button 0", "Button 1"], "width \(width)")
        }
    }
}
