import Foundation
@testable import HassCore
import HassTelemetry
import UIKit
import XCTest
@testable import HassUI

// MARK: - A page rests only when it is away

/// When a page rests and when it never does (pattern: derived-value, "Resting while away"): a page under a pushed page rests and catches up on
/// pop; a page that is in a window is never rested, even when its appearance calls say it left; two pages side by side in split columns are both
/// in a window, so neither rests; and the catch-up of a tab switch is one turn that is measured here.
///
/// Every test runs on iPhone, iPhone Duo and iPad (the hosted pass runs once per family) and needs no environment.
@MainActor
final class ServerUIPageRestHostedTests: XCTestCase {
    private var wasEnabled = false
    private var scene: LogicScene?
    private static let textNodes = 6, shownNodes = 2, pageA = 4

    override func setUp() async throws {
        try await super.setUp()
        wasEnabled = Telemetry.isEnabled
        Telemetry.isEnabled = true
    }

    override func tearDown() async throws {
        scene?.close()
        scene = nil
        Telemetry.isEnabled = wasEnabled
        HostedPage.hideTracked()
        HostedPage.resetGlobals()
        try await super.tearDown()
    }

    /// Two tabs over invented entities: `a` reads w0 to w3 as text, `b` reads w10 to w15 as text and w16, w17 as visibility.
    private func makeScene(textNodes: Int = ServerUIPageRestHostedTests.textNodes) throws -> LogicScene {
        var document = LogicDocument()
        document.sources = (0..<Self.pageA).map { ("a\($0)", LogicHouse.watched($0)) }
            + (0..<textNodes).map { ("t\($0)", LogicHouse.watched(10 + $0)) }
            + (0..<Self.shownNodes).map { ("s\($0)", LogicHouse.watched(10 + textNodes + $0)) }
        document.tabs = [
            .init(id: "a", nodes: (0..<Self.pageA).map { LogicDocument.stateText("a\($0)", source: "a\($0)") }),
            .init(id: "b", nodes: (0..<textNodes).map { LogicDocument.stateText("b\($0)", source: "t\($0)") }
                  + (0..<Self.shownNodes).map { LogicDocument.shownWhenOn("c\($0)", source: "s\($0)") }),
        ]
        let made = try LogicScene(document: document, house: LogicHouse.entities(watched: 10 + textNodes + Self.shownNodes))
        scene = made
        return made
    }

    private func runs(_ scene: LogicScene) -> Int { scene.renderer.bindings.logicTally.runs }

    private func drain(_ scene: LogicScene) { LogicDriver(scenario: "page-rest").drain(tally: scene.renderer.bindings.logicTally) }

    private func flip(_ ids: Range<Int>, in scene: LogicScene, generation: Int) {
        _ = scene.store.apply(ids.map { EntityState(entityId: LogicHouse.watched($0), state: LogicHouse.state($0, generation: generation)) })
    }

    private func words(_ id: String, on tab: String, in scene: LogicScene) throws -> String? {
        try scene.view(id, on: tab).accessibilityLabel
    }

    // MARK: Push and pop

    /// Pushes one of the fixture's own pages over the page of tab `a`, through the renderer's own action, and lets the transition finish: UIKit
    /// has then sent the page below `viewDidDisappear`, with its view out of the window.
    private func pushOver(_ page: UKServerUIPage, in scene: LogicScene) throws -> UINavigationController {
        let target = "page-echo"   // a page the fixture's own document keeps, which no tab opens
        XCTAssertTrue(scene.renderer.publication.document.pages.contains { $0.id == target })
        try scene.renderer.perform(.push(.init(pageId: target, arguments: .init(), origin: .sender, duplicate: .reuseNearest)), from: page)
        let nav = try XCTUnwrap(scene.renderer.stacks[.tab("a")])
        HostedPage.until { nav.viewControllers.count == 2 && page.view.window == nil }
        XCTAssertEqual(nav.viewControllers.count, 2, "the page is pushed")
        XCTAssertNil(page.view.window, "and the page below it is out of the window")
        return nav
    }

    func testAPageUnderAPushedPageRestsAndHasCaughtUpWhenItsViewWillAppearReturns() throws {
        let scene = try makeScene()
        let page = try scene.page("a")
        drain(scene)
        let before = try (0..<Self.pageA).map { try words("a\($0)", on: "a", in: scene) }
        _ = try pushOver(page, in: scene)
        drain(scene)

        let start = runs(scene)
        flip(0..<Self.pageA, in: scene, generation: 1)
        drain(scene)
        XCTAssertEqual(runs(scene) - start, 0, "covered by a pushed page, the four nodes ran nothing for four changed entities")
        XCTAssertEqual(try (0..<Self.pageA).map { try words("a\($0)", on: "a", in: scene) }, before, "and show what they were last drawn with")

        // The back action pops through UIKit. The transition coordinator's alongside block runs when the transition starts, after the page
        // below got `viewWillAppear` and before the first frame of the animation: what the page has then is what its first frame shows.
        final class Seen: @unchecked Sendable { var runs = 0, words: [String?] = [], done = false }
        let seen = Seen()
        try scene.renderer.perform(.back, from: try XCTUnwrap(scene.renderer.stacks[.tab("a")]?.topViewController as? UKServerUIPage))
        let nav = try XCTUnwrap(scene.renderer.stacks[.tab("a")])
        let immediate = runs(scene) - start
        let coordinator = try XCTUnwrap(nav.transitionCoordinator, "an animated pop in a window has a coordinator")
        let animating = coordinator.animate(alongsideTransition: { _ in
            MainActor.assumeIsolated {
                seen.runs = self.runs(scene) - start
                seen.words = (0..<Self.pageA).map { (try? self.words("a\($0)", on: "a", in: scene)) ?? nil }
                seen.done = true
            }
        }, completion: nil)
        XCTAssertTrue(animating)
        HostedPage.until { seen.done }
        XCTAssertTrue(seen.done, "the transition started")
        let atStart = seen
        XCTAssertEqual(max(immediate, atStart.runs), Self.pageA, "each changed node ran once by the time the transition started: before the first frame")
        XCTAssertNotEqual(atStart.words, before, "so the page's first frame shows the changed values")
        HostedPage.until { nav.viewControllers.count == 1 }
        drain(scene)
        XCTAssertEqual(runs(scene) - start, Self.pageA, "and nothing ran after it")
        XCTAssertTrue(page === (try scene.page("a")), "the same page: nothing was rebuilt")
    }

    /// An interactive pop that is let go before the half: UIKit sends the page below `viewWillAppear`, then `viewWillDisappear` and
    /// `viewDidDisappear` when the pop cancels. The page catches up at the first, and rests again at the last.
    func testACancelledInteractivePopCatchesUpAtTheStartAndRestsAgainAtTheCancel() throws {
        let scene = try makeScene()
        let page = try scene.page("a")
        drain(scene)
        _ = try pushOver(page, in: scene)
        drain(scene)
        let start = runs(scene)
        flip(0..<Self.pageA, in: scene, generation: 1)
        drain(scene)
        XCTAssertEqual(runs(scene) - start, 0)

        page.viewWillAppear(true)   // the drag begins
        XCTAssertEqual(runs(scene) - start, Self.pageA, "the page is about to be seen: it caught up in viewWillAppear")
        page.viewWillDisappear(true)   // the drag is let go before the half
        page.viewDidDisappear(true)
        let afterCancel = runs(scene)
        flip(0..<Self.pageA, in: scene, generation: 2)
        drain(scene)
        XCTAssertEqual(runs(scene) - afterCancel, 0, "the pop was cancelled: the page is covered again and rests again")

        page.viewWillAppear(true)   // the pop is done for real
        XCTAssertEqual(runs(scene) - afterCancel, Self.pageA, "and it catches up again when it is shown")
    }

    // MARK: Never in a window

    func testAPageInAWindowIsNeverRestedEvenWhenItsAppearanceCallsSayItLeft() throws {
        let scene = try makeScene()
        let page = try scene.page("a")
        drain(scene)
        XCTAssertNotNil(page.view.window, "tab a is on screen")
        page.viewDidDisappear(false)   // a container that forwarded the call wrongly
        let start = runs(scene)
        flip(0..<Self.pageA, in: scene, generation: 1)
        drain(scene)
        XCTAssertEqual(runs(scene) - start, Self.pageA, "it is in a window, so it keeps running: a container's mistake must not freeze what it shows")
    }

    func testAPageThatRestedAndIsThenPutInAWindowWakesAtItsNextLayout() throws {
        let scene = try makeScene()
        let page = try scene.page("b")   // loaded and away: it rests
        drain(scene)
        let start = runs(scene)
        flip(10..<(10 + Self.textNodes + Self.shownNodes), in: scene, generation: 1)
        drain(scene)
        XCTAssertEqual(runs(scene) - start, 0)
        // A container that never sent an appearance call puts the page's view in a window.
        page.view.frame = scene.window.bounds
        scene.window.addSubview(page.view)
        defer { page.view.removeFromSuperview() }
        scene.window.layoutIfNeeded()
        XCTAssertEqual(runs(scene) - start, Self.textNodes + Self.shownNodes, "the layout pass woke it: each changed node ran once, here")
    }

    // MARK: Split columns

    func testBothPagesOfASplitAreInAWindowSoNeitherRests() throws {
        let scene = try makeScene()
        let pageID = try scene.page("b").surfaceID
        let surface = try XCTUnwrap(scene.renderer.publication.document.pages.first { $0.id == pageID }).surface
        func make(depth: Int) -> UKServerUIPage {
            UKServerUIPage(surface: surface, context: scene.renderer.pageContext.with { $0.surface = .page }, root: .tab("b"), presentationID: nil,
                           depth: depth, inheritedGroups: [], close: nil, renderer: scene.renderer)
        }
        let leading = make(depth: 0), trailing = make(depth: 1)
        let owner = HostedColumnOwner()
        let columns = UKColumnsViewController(rootController: leading, shell: nil) {
            UKPanePlaceholderViewController(symbol: "lightbulb", text: "Select", identifier: "pane.empty")
        }
        owner.addChild(columns)
        owner.view.addSubview(columns.view)
        columns.view.frame = owner.view.bounds
        columns.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        columns.didMove(toParent: owner)
        let window = HostedPage.show(owner, size: LogicFamily.current.windowSize, inScene: true)
        defer { window.isHidden = true }
        columns.setWide(true)
        owner.view.layoutIfNeeded()
        columns.open(trailing, tag: "second")
        HostedPage.wait(0.3)
        HostedPage.until { leading.view.window != nil && trailing.view.window != nil }
        XCTAssertNotNil(leading.view.window)
        XCTAssertNotNil(trailing.view.window)
        drain(scene)
        leading.viewDidDisappear(false)
        trailing.viewDidDisappear(false)
        let start = runs(scene)
        flip(10..<(10 + Self.textNodes + Self.shownNodes), in: scene, generation: 1)
        drain(scene)
        XCTAssertEqual(runs(scene) - start, 2 * (Self.textNodes + Self.shownNodes), "both columns are in a window: each ran its eight nodes, neither rested")
    }

    // MARK: The catch-up turn

    /// What the first turn of a tab switch costs after a burst while the tab was away. The figure is printed (`CATCHUP`) for the evidence; the
    /// assertion only keeps it from being a whole frame.
    func testTheCatchUpOfATabSwitchIsOneSmallTurn() throws {
        let nodes = 60
        let scene = try makeScene(textNodes: nodes)
        let home = try scene.page("a")
        try scene.renderer.perform(.selectTab(tabId: "b"), from: home)
        drain(scene)
        try scene.renderer.perform(.selectTab(tabId: "a"), from: try scene.page("b"))
        drain(scene)
        flip(10..<(10 + nodes + Self.shownNodes), in: scene, generation: 1)
        drain(scene)
        let start = runs(scene)
        let meter = MainThreadCostMeter()
        meter.begin()
        try scene.renderer.perform(.selectTab(tabId: "b"), from: try scene.page("a"))
        HostedPage.wait(0.1)
        let report = meter.finish()
        print("CATCHUP\t\(LogicFamily.current.rawValue)\tnodes=\(nodes + Self.shownNodes)\tworst_ms=\(String(format: "%.2f", report.worstTurnMs))\tturns=\(report.turns)\tover16=\(report.turnsOver16)")
        XCTAssertEqual(runs(scene) - start, nodes + Self.shownNodes, "every changed node ran once, in the switch")
        XCTAssertLessThan(report.worstTurnMs, 100, "the switch is one turn, not a stall")
    }
}
