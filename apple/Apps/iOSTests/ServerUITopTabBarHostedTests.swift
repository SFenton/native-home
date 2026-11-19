import HassCore
import UIKit
import XCTest
@testable import HassUI

// MARK: - The iPad's top tab bar

/// Hosted UX, journey, accessibility and cost checks for the system tab bar at the top of a regular-width window with no hinge (global
/// chrome pick 3, 2026-11-18; `.agents/design/apple/ipados.md`, Navigation).
///
/// The renderer decides by the window's size class and hinge, never by device, so each test sets the size class on the renderer itself:
/// the same code runs on the iPhone, Duo and iPad simulators and checks both sides of the rule. Every id is the frozen fixture's own.
@MainActor
final class ServerUITopTabBarHostedTests: XCTestCase {
    private static let menuIdentifier = "chrome-menu"

    override func tearDown() async throws {
        HostedPage.hideTracked()
        HostedPage.resetGlobals()
        try await super.tearDown()
    }

    // MARK: Fixtures

    /// A renderer in a window of `size` whose horizontal size class is `sizeClass`, settled.
    private func host(_ sizeClass: UIUserInterfaceSizeClass, badge: String? = nil,
                      size: CGSize = CGSize(width: 744, height: 1133)) throws -> (UKServerUIRenderer, UIWindow) {
        var json = try ServerUIRendererFixture.json()
        if let badge {
            json = try ServerUIRendererFixture.changing(json, path: "document/navigation/tabs/0/badge",
                                                        to: .object(["type": .string("value"), "value": .object(["type": .string("literal"), "value": .string(badge)])]))
            let capabilities = ServerUICompositionPublication.firstSliceCapabilities + ["sh.badges@1", "sh.operands@1"]
            json = try ServerUIRendererFixture.changing(json, path: "capabilities", to: .array(Set(capabilities).sorted().map(JSONValue.string)))
        }
        let (renderer, window, _) = try ServerUIRendererFixture.host(publication: ServerUIRendererFixture.publication(json), size: size)
        renderer.traitOverrides.horizontalSizeClass = sizeClass
        HostedPage.layoutTracked()
        let expected: ShellNavigationStyle = sizeClass == .regular ? .topTabBar : .tabBar
        XCTAssertTrue(HostedPage.until { renderer.environment.style == expected }, "The style never became \(expected)")
        return (renderer, window)
    }

    /// Pushes the fixture's own navigation tile's page (`page-echo`) from `page`, the way a tap on the tile does.
    private func push(in renderer: UKServerUIRenderer, from page: UKServerUIPage) throws {
        guard case .grid(let grid) = page.definition.components[0], case .navigationTile(let tile) = grid.children[1] else {
            return XCTFail("Fixture navigation tile")
        }
        try renderer.perform(tile.action, from: page)
    }

    private func menu(on page: UKServerUIPage) -> UIBarButtonItem? {
        ServerUIRendererFixture.barItems(page).first { $0.accessibilityIdentifier == Self.menuIdentifier }
    }

    // MARK: UX

    /// Regular width, no hinge: the tab bar stays, in `.tabBar` mode; there is no menu button and no edge swipe; the title leads.
    func testRegularWidthKeepsTheTabBarAndDropsTheMenuAndTheEdgeSwipe() throws {
        let (renderer, window) = try host(.regular)
        defer { window.isHidden = true }
        let root = try ServerUIRendererFixture.root(renderer)
        XCTAssertEqual(renderer.environment.chrome, ShellChrome.resolve(style: .topTabBar))
        if #available(iOS 18.0, *) {
            XCTAssertFalse(renderer.tabController.isTabBarHidden, "The tab bar is never hidden for style")
            XCTAssertEqual(renderer.tabController.mode, .tabBar, "Never the sidebar")
        }
        XCTAssertFalse(renderer.tabController.tabBar.isHidden)
        XCTAssertNil(menu(on: root), "A second navigator in the row would repeat the first")
        XCTAssertFalse(renderer.gestureRecognizerShouldBegin(UIPanGestureRecognizer()), "No flyout edge swipe")
        XCTAssertTrue(HostedPage.until { root.navigationItem.style == .browser }, "The collapsed title leads the row")
        XCTAssertEqual(root.navigationItem.largeTitleDisplayMode, .automatic, "The large title below the bar is unchanged")
    }

    /// A compact window (an iPhone, a Duo folded or a narrow iPad window) keeps the menu button and the edge swipe, as before.
    func testCompactWidthKeepsTheMenuButtonAndTheEdgeSwipe() throws {
        let (renderer, window) = try host(.compact, size: CGSize(width: 390, height: 844))
        defer { window.isHidden = true }
        let root = try ServerUIRendererFixture.root(renderer)
        // The folded Duo simulator's scene draws a vertical bar, which has no menu button; every other window has it.
        let vertical = renderer.environment.inVerticalBar
        XCTAssertEqual(renderer.environment.chrome, ShellChrome.resolve(style: .tabBar, inVerticalBar: vertical))
        XCTAssertTrue(HostedPage.until { (self.menu(on: root) != nil) == !vertical }, "The menu button shows on a section root, except in a vertical bar")
        XCTAssertEqual(renderer.gestureRecognizerShouldBegin(UIPanGestureRecognizer()), !vertical)
        if #available(iOS 18.0, *) { XCTAssertFalse(renderer.tabController.isTabBarHidden) }
    }

    /// Narrowing a regular window to a compact one brings the menu button back on the same pages, and widening takes it away again.
    func testResizingSwapsTheMenuWithoutRebuildingThePages() throws {
        let (renderer, window) = try host(.regular)
        defer { window.isHidden = true }
        let root = try ServerUIRendererFixture.root(renderer)
        renderer.traitOverrides.horizontalSizeClass = .compact
        let vertical = renderer.environment.inVerticalBar
        XCTAssertTrue(HostedPage.until { (self.menu(on: root) != nil) == !vertical }, "Compact brings the menu button back (not in a vertical bar)")
        renderer.traitOverrides.horizontalSizeClass = .regular
        XCTAssertTrue(HostedPage.until { self.menu(on: root) == nil }, "Regular takes it away")
        XCTAssertTrue(try ServerUIRendererFixture.root(renderer) === root, "A resize never rebuilds a page")
    }

    /// With no way to open the flyout, its off-screen rows and Close target are out of the accessibility tree; a window with the menu
    /// button keeps it, and a resize back to regular hides it again.
    func testTheFlyoutLeavesTheAccessibilityTreeOnlyWithTheTopTabBar() throws {
        let (renderer, window) = try host(.regular)
        defer { window.isHidden = true }
        func flyouts() -> [UKNavigationFlyoutView] { HostedPage.descendants(of: renderer.view).compactMap { $0 as? UKNavigationFlyoutView } }
        XCTAssertFalse(flyouts().isEmpty, "The flyout view is still built")
        XCTAssertTrue(flyouts().allSatisfy(\.isHidden), "Hidden, so VoiceOver cannot reach it")
        renderer.traitOverrides.horizontalSizeClass = .compact
        XCTAssertTrue(HostedPage.until { flyouts().allSatisfy { !$0.isHidden } }, "The menu button's flyout is untouched")
        renderer.traitOverrides.horizontalSizeClass = .regular
        XCTAssertTrue(HostedPage.until { flyouts().allSatisfy(\.isHidden) })
    }

    // MARK: Journey

    /// Through the top bar: a tab switch is a cut (no transition), and the tab it left keeps its pushed page.
    func testSwitchingTabsIsACutAndKeepsEachStack() throws {
        let (renderer, window) = try host(.regular)
        defer { window.isHidden = true }
        let alpha = try ServerUIRendererFixture.root(renderer)
        try push(in: renderer, from: alpha)
        XCTAssertTrue(HostedPage.until { renderer.navigation.snapshot.stacks[.tab("tab-alpha")] == ["page-orbit", "page-echo"] })
        let beta = try ServerUIRendererFixture.root(renderer, "tab-beta")
        try renderer.perform(.selectTab(tabId: "tab-beta"), from: alpha)
        // Right after the intent, before any wait: a cut has no transition in flight.
        XCTAssertEqual(renderer.navigation.snapshot.selection, .tab("tab-beta"))
        XCTAssertTrue(renderer.tabController.selectedViewController === renderer.stacks[.tab("tab-beta")])
        XCTAssertNil(renderer.tabController.transitionCoordinator, "A tab switch never animates")
        XCTAssertNil(beta.transitionCoordinator)
        XCTAssertEqual(renderer.navigation.snapshot.stacks[.tab("tab-alpha")], ["page-orbit", "page-echo"])
    }

    /// Selecting the selected tab pops its stack to the root; with the stack at the root it only scrolls to the top.
    func testReselectingTheTabPopsToItsRoot() throws {
        let (renderer, window) = try host(.regular)
        defer { window.isHidden = true }
        let root = try ServerUIRendererFixture.root(renderer)
        try push(in: renderer, from: root)
        let nav = try XCTUnwrap(renderer.stacks[.tab("tab-alpha")])
        XCTAssertTrue(HostedPage.until { nav.viewControllers.count == 2 && nav.transitionCoordinator == nil })
        let pushed = try XCTUnwrap(nav.topViewController as? UKServerUIPage)
        try renderer.perform(.selectTab(tabId: "tab-alpha"), from: pushed)
        XCTAssertTrue(HostedPage.until { nav.viewControllers.count == 1 && nav.transitionCoordinator == nil })
        XCTAssertEqual(renderer.navigation.snapshot.stacks[.tab("tab-alpha")], ["page-orbit"])
        XCTAssertTrue(nav.topViewController === root)
    }

    // MARK: Accessibility

    /// The bar's items are the sections in the document's order, each with its name; Chores' badge is spoken with it.
    func testTheTopBarItemsAreNamedInOrderAndTheBadgeIsSpoken() throws {
        let (renderer, window) = try host(.regular, badge: "8")
        defer { window.isHidden = true }
        let tabs = renderer.publication.document.navigation.tabs
        XCTAssertEqual(renderer.tabController.viewControllers?.compactMap(\.tabBarItem.title), tabs.map(\.label))
        let first = try XCTUnwrap(renderer.stacks[.tab(tabs[0].id)]?.tabBarItem)
        XCTAssertTrue(HostedPage.until { first.badgeValue == "8" }, "The badge reaches the item")
        XCTAssertEqual(first.accessibilityValue, "8", "VoiceOver reads the name, then the badge")
        XCTAssertEqual(UKServerUIRenderer.spokenTabLabel(tabs[0].label, badge: "8"), "\(tabs[0].label), 8")
    }

    /// On a pushed page Back is the system chevron and the title leads, with no menu button before it. The fixture's bar carries no
    /// header buttons, so the order of Quick Links and Profile is the Verifier's tree check, not this test's.
    func testAPushedPageHasBackAndALeadingTitleAndNoMenu() throws {
        let (renderer, window) = try host(.regular)
        defer { window.isHidden = true }
        let root = try ServerUIRendererFixture.root(renderer)
        try push(in: renderer, from: root)
        let nav = try XCTUnwrap(renderer.stacks[.tab("tab-alpha")])
        XCTAssertTrue(HostedPage.until { nav.viewControllers.count == 2 && nav.transitionCoordinator == nil })
        let page = try XCTUnwrap(nav.topViewController as? UKServerUIPage)
        XCTAssertNil(menu(on: page))
        XCTAssertEqual(page.navigationItem.backButtonDisplayMode, .minimal, "Back is the chevron, named Back by the system")
        XCTAssertFalse(page.navigationItem.hidesBackButton)
        XCTAssertEqual(page.navigationItem.style, .browser, "The title leads, after Back and before the tabs")
    }

    // MARK: Cost

    /// Revisiting a tab, cycling every tab and the first visit of each, measured as clock time (recorded, not budgeted).
    func testTabRevisitCycleAndFirstVisitAreMeasuredAtRegularWidth() throws {
        let (renderer, window) = try host(.regular)
        defer { window.isHidden = true }
        let ids = renderer.publication.document.navigation.tabs.map(\.id)
        var current = try ServerUIRendererFixture.root(renderer, ids[0])
        let first = try measureOnce { for id in ids.dropFirst() { current = try self.select(id, from: current, in: renderer) } }
        XCTAssertEqual(renderer.navigation.snapshot.selection, .tab(ids.last ?? ""), "Every tab was visited once")
        let revisit = try measureOnce { current = try self.select(ids[0], from: current, in: renderer) }
        let cycle = try measureOnce {
            for _ in 0..<3 { for id in ids { current = try self.select(id, from: current, in: renderer) } }
        }
        let note = XCTAttachment(string: "first visit \(first) ms, revisit \(revisit) ms, cycle x3 \(cycle) ms")
        note.lifetime = .keepAlways
        add(note)
    }

    private func select(_ id: String, from page: UKServerUIPage, in renderer: UKServerUIRenderer) throws -> UKServerUIPage {
        if renderer.navigation.snapshot.selection != .tab(id) { try renderer.perform(.selectTab(tabId: id), from: page) }
        HostedPage.layoutTracked()
        return try ServerUIRendererFixture.root(renderer, id)
    }

    private func measureOnce(_ work: () throws -> Void) rethrows -> Int {
        let start = ContinuousClock.now
        try work()
        let elapsed = ContinuousClock.now - start
        return Int(elapsed.components.seconds * 1000) + Int(elapsed.components.attoseconds / 1_000_000_000_000_000)
    }
}
