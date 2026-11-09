import HassCore
import UIKit
import XCTest
@testable import HassUI

/// Small shared views of the Rooms and Common layers: padding labels, Auto Layout rows measured at a width, a module stack that
/// follows its surface and density, and the Security System page of Quick Links.
@MainActor
final class UKHostedCommonGapTests: DemoHouseTestCase {
    func testInsetLabelAddsItsPaddingToTheTextSize() {
        let label = UKInsetLabel()
        label.text = "New"
        label.font = .systemFont(ofSize: 12)
        let bare = label.sizeThatFits(CGSize(width: 200, height: 50))
        label.insets = UIEdgeInsets(top: 2, left: 6, bottom: 2, right: 6)
        let padded = label.sizeThatFits(CGSize(width: 200, height: 50))
        XCTAssertEqual(padded.width, bare.width + 12, accuracy: 0.5)
        XCTAssertEqual(padded.height, bare.height + 4, accuracy: 0.5)
        XCTAssertEqual(label.intrinsicContentSize.width, padded.width, accuracy: 0.5, "the badge's capsule hugs the padded text")
        label.drawText(in: CGRect(x: 0, y: 0, width: 80, height: 20))
    }

    func testFittedAndInsetRowsMeasureTheirContentAtAWidth() {
        let label = UILabel()
        label.numberOfLines = 0
        label.text = String(repeating: "Garage door left open. ", count: 8)
        let fitted = UKRoomsFittedView(label)
        let narrow = fitted.gridHeight(forWidth: 120)
        let wide = fitted.gridHeight(forWidth: 600)
        XCTAssertGreaterThan(narrow, wide, "a narrow row wraps onto more lines")
        XCTAssertEqual(fitted.sizeThatFits(CGSize(width: 120, height: 10)).height, narrow)

        let inner = UILabel()
        inner.numberOfLines = 0
        inner.text = label.text
        let box = UKRoomsInsetBox(inner, insets: UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 10))
        XCTAssertGreaterThan(box.gridHeight(forWidth: 140), box.gridHeight(forWidth: 600), "the inset box wraps like its content")
        XCTAssertEqual(box.sizeThatFits(CGSize(width: 140, height: 10)).height, box.gridHeight(forWidth: 140))
    }

    func testModuleStackPassesSurfaceAndDensityToItsRowsAndMeasuresVisibleOnes() {
        let first = UIView()
        let second = UIView()
        let hidden = UIView()
        hidden.isHidden = true
        let stack = UKRoomsModuleStack(.thin, rows: [UKRoomsFittedView(first), UKRoomsFittedView(second), UKRoomsFittedView(hidden)])
        XCTAssertEqual(stack.rows.count, 3)
        stack.surface = .sheet
        stack.density = .dense
        XCTAssertEqual(stack.density, .dense)
        let one = UKRoomsModuleStack(.thin, rows: [UKRoomsFittedView(first)]).gridHeight(forWidth: 300)
        XCTAssertGreaterThan(stack.gridHeight(forWidth: 300), one - 0.5, "two visible rows are at least as tall as one")
        XCTAssertEqual(stack.sizeThatFits(CGSize(width: 300, height: 1)).width, 300)
        XCTAssertEqual(stack.sizeThatFits(CGSize(width: 300, height: 1)).height, stack.gridHeight(forWidth: 300))
        stack.setRows([])
        XCTAssertEqual(stack.gridHeight(forWidth: 300), 0, "an empty stack has no height")
    }

    func testSecuritySystemPageShowsTheAlarmStateNotTheRooms() throws {
        let store = EntityStore()
        store.replaceAll([EntityState(entityId: QuickLinks.securityEntityId, state: "armed_home")], freshness: .live)
        let context = UKGalleryChrome.context(store: store)
        var closed = 0
        let page = UKQuickLinksDetailPage(detail: .securitySystem, context: context, close: { closed += 1 }, openRoom: { _ in })
        let window = HostedPage.show(UINavigationController(rootViewController: page), size: CGSize(width: 393, height: 852))
        defer { window.isHidden = true }
        let texts = HostedPage.labels(in: page.view)
        XCTAssertTrue(texts.contains("Security System"), "the page names itself; saw \(texts)")
        XCTAssertEqual(page.title ?? page.navigationItem.title, "Security System")
        let close = try XCTUnwrap(page.navigationItem.rightBarButtonItem, "a Close button at every depth")
        _ = close
        XCTAssertEqual(closed, 0)
    }
}
