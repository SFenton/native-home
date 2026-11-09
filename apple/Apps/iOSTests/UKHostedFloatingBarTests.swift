import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

/// The floating action bar: capsule and circle actions, the active state, and the search that opens in place.
@MainActor
final class UKHostedFloatingBarTests: XCTestCase {
    private func labels(_ bar: UIView) -> [String] {
        HostedPage.descendants(of: bar).compactMap { $0.accessibilityLabel }
    }

    func testActionsRunTheirClosureAndShowActiveState() {
        var fired: [String] = []
        let bar = UKFloatingActionBar(actions: [
            UKFloatingAction(id: "add", title: "Add Item", symbol: "plus") { fired.append("add") },
            UKFloatingAction(id: "filter", title: "Filter", symbol: "line.3.horizontal.decrease", showsTitle: false, isProminent: false) { fired.append("filter") },
        ])
        let host = UIViewController()
        let window = HostedPage.show(host)
        defer { window.isHidden = true }
        host.view.addSubview(bar)
        bar.frame = CGRect(x: 0, y: 700, width: 393, height: 80)
        bar.layoutIfNeeded()
        XCTAssertTrue(labels(bar).contains("Add Item"))
        XCTAssertTrue(labels(bar).contains("Filter"))
        let controls = HostedPage.descendants(of: bar).compactMap { $0 as? UKBarGlassControl }
        XCTAssertEqual(controls.count, 2)
        for control in controls { _ = control.accessibilityActivate() }
        XCTAssertEqual(Set(fired), ["add", "filter"])
        bar.setActive(true, forActionID: "filter")
        bar.setActive(false, forActionID: "filter")
        bar.setActive(true, forActionID: "missing")
        XCTAssertNotNil(UKFloatingActionBar.tint)
        XCTAssertNotNil(UKFloatingActionBar.activeTint)
        XCTAssertNotNil(UKFloatingActionBar.activeGlyph)
    }

    func testSearchCollapsesToAPromptThenOpensAndTypesIntoTheModel() {
        let search = UKFloatingSearch(prompt: "Search chores")
        let bar = UKFloatingActionBar(actions: [UKFloatingAction(id: "add", title: "Add", symbol: "plus") {}], search: search)
        let host = UIViewController()
        let window = HostedPage.show(host)
        defer { window.isHidden = true }
        host.view.addSubview(bar)
        bar.frame = CGRect(x: 0, y: 700, width: 393, height: 80)
        bar.layoutIfNeeded()
        XCTAssertNotNil(bar.search)
        let collapsed = HostedPage.descendants(of: bar).first { $0.accessibilityIdentifier == "fab.search" } as? UKBarSearchCollapsed
        XCTAssertEqual(collapsed?.accessibilityLabel, "Search chores")
        XCTAssertEqual(collapsed?.accessibilityValue, "")
        XCTAssertEqual(collapsed?.accessibilityTraits, .button)
        _ = collapsed?.accessibilityActivate()
        hostedSettle(0.5)
        XCTAssertTrue(search.isExpanded, "tapping the prompt opens the field")
        let field = HostedPage.descendants(of: bar).compactMap { $0 as? UITextField }.first
        XCTAssertNotNil(field)
        field?.text = "milk"
        field?.sendActions(for: .editingChanged)
        XCTAssertEqual(search.text, "milk")
        XCTAssertEqual(field?.returnKeyType, .search)
        XCTAssertEqual(field?.delegate?.textFieldShouldReturn?(field!), true)
        let close = HostedPage.descendants(of: bar).first { $0.accessibilityIdentifier == "fab.search.close" } as? UIButton
        close?.sendActions(for: .touchUpInside)
        hostedSettle(0.5)
        XCTAssertFalse(search.isExpanded)
        let again = HostedPage.descendants(of: bar).first { $0.accessibilityIdentifier == "fab.search" } as? UKBarSearchCollapsed
        XCTAssertEqual(search.text, "", "closing the search clears the query")
        XCTAssertEqual(again?.accessibilityValue, "")
        search.text = "tea"
        hostedSettle(0.4)
        XCTAssertEqual(again?.accessibilityValue, "tea", "a query typed elsewhere shows on the collapsed prompt")
        XCTAssertTrue(again?.accessibilityTraits.contains(.selected) ?? false)
    }

    func testSplitPlacementAndReplacingTheSearch() {
        let bar = UKFloatingActionBar(actions: [UKFloatingAction(id: "a", title: "A", symbol: "plus") {}])
        let host = UIViewController()
        let window = HostedPage.show(host)
        defer { window.isHidden = true }
        host.view.addSubview(bar)
        bar.frame = CGRect(x: 0, y: 700, width: 393, height: 80)
        bar.setSplit(leadingColumn: 180, expandsActions: true, animated: false)
        bar.layoutIfNeeded()
        XCTAssertEqual(bar.leadingColumn, 180)
        XCTAssertTrue(bar.expandsActions)
        bar.setSplit(leadingColumn: nil, expandsActions: false, animated: true)
        bar.setSearch(UKFloatingSearch(prompt: "Find", text: "x", isExpanded: true))
        bar.layoutIfNeeded()
        XCTAssertNotNil(bar.search)
        bar.setSearch(nil)
        XCTAssertNil(bar.search)
        bar.actions = []
        bar.layoutIfNeeded()
    }

    func testAccessibilityTextStacksTheCapsulesVertically() {
        let bar = UKFloatingActionBar(actions: [
            UKFloatingAction(id: "a", title: "Add Item", symbol: "plus") {},
            UKFloatingAction(id: "b", title: "Sort", symbol: "arrow.up.arrow.down", showsTitle: false) {},
        ], search: UKFloatingSearch(prompt: "Search"))
        let host = UIViewController()
        let window = HostedPage.show(host)
        defer { window.isHidden = true }
        host.view.addSubview(bar)
        bar.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        bar.frame = CGRect(x: 0, y: 500, width: 393, height: 300)
        let current = bar.actions; bar.actions = current
        bar.layoutIfNeeded()
        XCTAssertTrue(labels(bar).contains("Add Item"))
        XCTAssertTrue(labels(bar).contains("Search"))
    }
}
