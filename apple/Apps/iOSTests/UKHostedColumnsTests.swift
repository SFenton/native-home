import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

/// A column page that can hold itself open.
@MainActor
final class HostedGuardedPage: UIViewController, UKColumnPopGuarding {
    var columnPopDecision: UKColumnPopDecision = .allow
}

/// An owner that records the column group the columns send to the bar.
@MainActor
final class HostedColumnOwner: UIViewController, UKColumnBarHosting {
    var bars: [UKColumnBar?] = []
    func setColumnBar(_ bar: UKColumnBar?) { bars.append(bar) }
    var last: UKColumnBar? { bars.last ?? nil }
}

@MainActor
final class UKHostedColumnsTests: XCTestCase {
    private func make(wide: Bool = true, shell: UKShellEnvironment? = nil)
        -> (HostedColumnOwner, UKColumnsViewController, UIWindow) {
        let owner = HostedColumnOwner()
        let root = UIViewController()
        root.title = "Root"
        let columns = UKColumnsViewController(rootController: root, shell: shell) {
            UKPanePlaceholderViewController(symbol: "gearshape", text: "Select a setting", identifier: "pane.empty")
        }
        owner.addChild(columns)
        owner.view.addSubview(columns.view)
        columns.view.frame = owner.view.bounds
        columns.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        columns.didMove(toParent: owner)
        let window = HostedPage.show(owner, size: CGSize(width: 1024, height: 768))
        columns.setWide(wide)
        owner.view.layoutIfNeeded()
        return (owner, columns, window)
    }

    private func page(_ title: String) -> UIViewController {
        let page = UIViewController()
        page.title = title
        return page
    }

    private func settle(_ seconds: TimeInterval = 0.5) { HostedPage.wait(seconds) }

    func testWideColumnsShowTheEmptyStateUntilAPageOpensThenSlideItIn() {
        let (owner, columns, window) = make()
        defer { window.isHidden = true }
        XCTAssertTrue(columns.isWide)
        XCTAssertTrue(HostedPage.labels(in: columns.view).contains("Select a setting"), "the right column starts empty")
        XCTAssertEqual(owner.last?.kind, UKColumnBar.Kind.none, "nothing open: the item is hidden")
        let first = page("First")
        columns.open(first, tag: "a")
        settle()
        HostedPage.until { !HostedPage.labels(in: columns.view).contains("Select a setting") }
        XCTAssertEqual(columns.entries.count, 1)
        XCTAssertEqual(owner.last?.kind, .close, "the first page offers Close")
        XCTAssertFalse(HostedPage.labels(in: columns.view).contains("Select a setting"), "the empty state is gone")
        XCTAssertTrue(columns.takesEdgePan)
        XCTAssertEqual(first.view.superview?.accessibilityIdentifier, "split.trailing")
        // Drilling from the right column appends; the first page moves to the left column.
        let second = page("Second")
        columns.open(second, tag: "b", atDepth: columns.depth(of: first))
        settle()
        XCTAssertEqual(columns.entries.count, 2)
        XCTAssertEqual(owner.last?.kind, .back, "a drilled page offers Back")
        XCTAssertEqual(columns.depth(of: second), 2)
        XCTAssertEqual(columns.depth(of: UIView()), 0)
        // A tap in the left column replaces what is on the right.
        let replacement = page("Replacement")
        columns.show(replacement, sender: first)
        settle()
        XCTAssertEqual(columns.entries.map(\.controller), [first, replacement])
        // Back returns one page, Close all.
        var popped: [Int] = []
        columns.onUserPop = { popped.append($0) }
        columns.popTop()
        settle()
        XCTAssertEqual(columns.entries.map(\.controller), [first])
        XCTAssertEqual(popped, [1], "the owner is told how many tagged pages remain")
        columns.closeAll()
        settle()
        XCTAssertTrue(columns.entries.isEmpty)
        XCTAssertEqual(popped, [1, 0])
        XCTAssertTrue(HostedPage.labels(in: columns.view).contains("Select a setting"), "the empty state returns")
        columns.popTop()
        columns.closeAll()
    }

    func testNarrowColumnsPushOnTheNavigationStackAndHandPagesOverWhenTheWindowStopsSplitting() {
        let navigation = UINavigationController()
        let columns = UKColumnsViewController(rootView: UIView(), shell: nil) { UIViewController() }
        navigation.viewControllers = [columns]
        let window = HostedPage.show(navigation)
        defer { window.isHidden = true }
        XCTAssertFalse(columns.isWide)
        let narrow = page("Narrow")
        columns.open(narrow, tag: nil, animated: false)
        XCTAssertTrue(navigation.topViewController === narrow, "narrow, a shown page is a push")
        navigation.popToRootViewController(animated: false)
        columns.open(page("Skipped"), tag: nil, animated: false, pushesWhenNarrow: false)
        XCTAssertTrue(navigation.topViewController === columns)
        columns.setDetail(page("Ignored"))
        columns.reconcile(tags: ["x"], make: { _ in UIViewController() }, animated: false)
        columns.adopt([page("Adopted")])
        XCTAssertTrue(columns.entries.isEmpty, "no column is kept while narrow")
        // Wide, then narrow again: a local page goes to the stack, a routed one is the owner's.
        columns.setWide(true)
        let local = page("Local")
        columns.open(local, tag: nil, animated: false)
        columns.open(page("Routed"), tag: "route", atDepth: 1, animated: false)
        columns.setWide(false)
        settle(0.3)
        XCTAssertTrue(navigation.topViewController === local, "pages open when the window stopped splitting keep their place")
    }

    func testReconcileKeepsTheCommonPrefixAndLocalPagesAboveIt() {
        let (_, columns, window) = make()
        defer { window.isHidden = true }
        var made: [String] = []
        let make: (AnyHashable) -> UIViewController = { tag in made.append(tag as! String); return self.page(tag as! String) }
        columns.reconcile(tags: ["a", "b"], make: make, animated: false)
        XCTAssertEqual(columns.entries.compactMap { $0.tag as? String }, ["a", "b"])
        columns.reconcile(tags: ["a", "c"], make: make, animated: false)
        XCTAssertEqual(columns.entries.compactMap { $0.tag as? String }, ["a", "c"])
        XCTAssertEqual(made, ["a", "b", "c"], "the common prefix is not rebuilt")
        columns.reconcile(tags: ["a", "c"], make: make, animated: false)
        XCTAssertEqual(made.count, 3)
        columns.setDetail(page("Detail"), tag: "d", hairline: true, animated: false)
        XCTAssertEqual(columns.entries.count, 1)
        columns.setDetail(nil, animated: false)
        XCTAssertTrue(columns.entries.isEmpty)
        columns.setDetail(nil)
        let kept = page("Kept")
        columns.adopt([kept])
        XCTAssertEqual(columns.entries.last?.controller, kept)
        columns.remove(page("Other"), animated: false)
        XCTAssertEqual(columns.entries.count, 1, "removing a page that is not open on the right does nothing")
        columns.remove(kept, animated: false)
        XCTAssertTrue(columns.entries.isEmpty)
    }

    func testBackAndCloseAreRefusedWhileSavingAndAskBeforeDiscarding() {
        let (owner, columns, window) = make()
        defer { window.isHidden = true }
        let form = HostedGuardedPage()
        columns.open(form, tag: nil, animated: false)
        form.columnPopDecision = .block
        columns.pageStateChanged()
        XCTAssertEqual(owner.last?.isEnabled, false, "the bar item dims while a save is in flight")
        columns.popTop(animated: false)
        columns.closeAll(animated: false)
        XCTAssertEqual(columns.entries.count, 1, "a save in flight keeps the page")
        form.columnPopDecision = .confirmDiscard
        columns.popTop(animated: false)
        settle(0.6)
        XCTAssertNotNil(owner.presentedViewController ?? form.presentedViewController ?? window.rootViewController?.presentedViewController,
                        "edits to lose ask first")
        XCTAssertEqual(columns.entries.count, 1)
    }

    func testUserCloseCallbackRunsWhenThePersonClosesButNotWhenTheOwnerRemoves() {
        let (_, columns, window) = make()
        defer { window.isHidden = true }
        var closed = 0
        let page = page("Closable")
        columns.open(page, tag: nil, animated: false, onUserClose: { closed += 1 })
        columns.remove(page, animated: false)
        XCTAssertEqual(closed, 0)
        columns.open(page, tag: nil, animated: false, onUserClose: { closed += 1 })
        columns.closeAll(animated: false)
        XCTAssertEqual(closed, 1)
    }

    func testTheOpenPagesOwnBarItemsRideInTheColumnGroup() {
        let (owner, columns, window) = make()
        defer { window.isHidden = true }
        let page = page("With items")
        let refresh = UIBarButtonItem(title: "Refresh", primaryAction: UIAction { _ in })
        page.navigationItem.rightBarButtonItems = [refresh]
        columns.open(page, tag: nil, animated: false)
        XCTAssertEqual(owner.last?.items, [refresh])
        let save = UIBarButtonItem(title: "Save", primaryAction: UIAction { _ in })
        page.navigationItem.rightBarButtonItems = [save]
        settle(0.2)
        XCTAssertEqual(owner.last?.items, [save], "the group follows the page's own items")
        owner.last?.perform()
        settle(0.4)
        XCTAssertTrue(columns.entries.isEmpty, "the Close item closes the page")
        let nav = UINavigationController(rootViewController: UIViewController())
        columns.open(nav, tag: nil, animated: false)
        XCTAssertTrue(owner.last?.items.isEmpty == true, "a navigation controller brings its own bar")
    }

    func testReduceMotionCrossFadesInsteadOfSliding() {
        let (_, columns, window) = make()
        defer { window.isHidden = true }
        let first = page("One")
        columns.open(first, tag: nil, animated: false)
        let second = page("Two")
        columns.open(second, tag: nil, atDepth: 1, animated: true)
        settle(0.6)
        XCTAssertEqual(columns.entries.last?.controller, second)
        columns.popTop(animated: true)
        settle(0.6)
        XCTAssertEqual(columns.entries.count, 1)
    }

    func testTheHingeSplitsTheColumnsAtTheBand() {
        let shell = UKShellEnvironment()
        shell.windowHinge = CGRect(x: 500, y: 0, width: 24, height: 768)
        let (_, columns, window) = make(shell: shell)
        defer { window.isHidden = true }
        columns.open(page("A"), tag: nil, animated: false)
        settle(0.3)
        columns.view.layoutIfNeeded()
        let host = columns.entries.first!.host
        XCTAssertGreaterThanOrEqual(host.frame.minX, 500, "the open page keeps to the far side of the hinge")
        shell.windowHinge = nil
        settle(0.3)
    }

    func testEdgePanDragsTheOpenPageBackAndCompletesPastHalfway() {
        let (_, columns, window) = make()
        defer { window.isHidden = true }
        columns.open(page("A"), tag: "a", animated: false)
        settle(0.3)
        let pan = columns.view.gestureRecognizers?.compactMap { $0 as? UIScreenEdgePanGestureRecognizer }.first
        XCTAssertNotNil(pan)
        XCTAssertEqual(pan?.isEnabled, true, "with a page open the edge pan is on")
        XCTAssertEqual(pan?.edges, .left)
        XCTAssertEqual(columns.trailingIdentifier, "split.trailing")
    }

    func testPlaceholderAndEmptyHostedAreCoveredByTheEmptyState() {
        let (_, columns, window) = make(wide: false)
        defer { window.isHidden = true }
        XCTAssertFalse(columns.isWide)
        XCTAssertFalse(columns.takesEdgePan)
        columns.setWide(true)
        settle(0.2)
        XCTAssertTrue(HostedPage.labels(in: columns.view).contains("Select a setting"))
        var changes: [Bool] = []
        columns.onWideChange = { changes.append($0) }
        columns.setWide(false)
        XCTAssertEqual(changes, [false])
        XCTAssertFalse(HostedPage.labels(in: columns.view).contains("Select a setting"), "narrow, the empty state is removed")
    }
}
