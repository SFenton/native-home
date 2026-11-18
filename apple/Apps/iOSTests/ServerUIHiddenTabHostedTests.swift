import Foundation
@testable import HassCore
import HassTelemetry
import UIKit
import XCTest
@testable import HassUI

// MARK: - A tab that is away does not evaluate

/// What a tab that is not on screen costs, and what it shows when it comes back (pattern: derived-value, "Resting while away";
/// budgets: `.agents/testing/apple/logic-evaluation.md`).
///
/// The nodes of a page that another tab covers are not evaluated for changes to what they read: they note the change once and wait.
/// When the tab is selected again each node that was changed runs once, inside `viewWillAppear`, which UIKit sends before the page's first
/// frame, so what is drawn first is already current: no blank, no re-fade, no reorder, no stale frame. Tab badges and tab rules belong to
/// the renderer, are on screen all the time, and keep running.
///
/// Every test here runs on iPhone, iPhone Duo and iPad (the hosted pass runs once per family) and needs no environment.
@MainActor
final class ServerUIHiddenTabHostedTests: XCTestCase {
    private var wasEnabled = false
    private var scene: LogicScene?

    /// Tab `a` is the one on screen; tab `b` reads w10 to w15 as text, w16 and w17 as visibility, and w20 as its badge.
    private static let first = 0, textNodes = 6, shownNodes = 2

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

    /// Two tabs over invented entities, `b` with a badge.
    private func makeScene() throws -> LogicScene {
        var document = LogicDocument()
        document.sources = (0..<4).map { ("a\($0)", LogicHouse.watched($0)) }
            + (0..<Self.textNodes).map { ("t\($0)", LogicHouse.watched(10 + $0)) }
            + (0..<Self.shownNodes).map { ("s\($0)", LogicHouse.watched(16 + $0)) }
            + [("badge", LogicHouse.watched(20))]
        let badge = LogicDocument.choose([(LogicDocument.isState("badge"), LogicDocument.literal("2"))], otherwise: LogicDocument.literal("1"))
        document.tabs = [
            .init(id: "a", nodes: (0..<4).map { LogicDocument.stateText("a\($0)", source: "a\($0)") }),
            .init(id: "b", nodes: (0..<Self.textNodes).map { LogicDocument.stateText("b\($0)", source: "t\($0)") }
                  + (0..<Self.shownNodes).map { LogicDocument.shownWhenOn("c\($0)", source: "s\($0)") }, badge: badge),
        ]
        let made = try LogicScene(document: document, house: LogicHouse.entities(watched: 21))
        scene = made
        return made
    }

    private func runs(_ scene: LogicScene) -> Int { scene.renderer.bindings.logicTally.runs }

    private func drain(_ scene: LogicScene) { LogicDriver(scenario: "hidden-tab").drain(tally: scene.renderer.bindings.logicTally) }

    /// What the text node `id` on `tab` shows.
    private func words(_ id: String, on tab: String, in scene: LogicScene) throws -> String? {
        try scene.view(id, on: tab).accessibilityLabel
    }

    private func select(_ tab: String, from page: UKServerUIPage, in scene: LogicScene) throws {
        try scene.renderer.perform(.selectTab(tabId: tab), from: page)
    }

    /// Flips w10 to w15 (the words of `b`) and w16, w17 (its visibility) to the other answer.
    private func flipTabB(_ scene: LogicScene, generation: Int) {
        let entities = (10..<18).map { EntityState(entityId: LogicHouse.watched($0), state: LogicHouse.state($0, generation: generation)) }
        _ = scene.store.apply(entities)
    }

    // MARK: Away

    func testATabThatWasNeverShownEvaluatesNothingForChangesToWhatItReads() throws {
        let scene = try makeScene()
        _ = try scene.page("b")
        drain(scene)
        let start = runs(scene)
        flipTabB(scene, generation: 1)
        drain(scene)
        XCTAssertEqual(runs(scene) - start, 0, "tab b is loaded and not on screen: its eight nodes ran nothing for eight changed entities")
        XCTAssertEqual(try words("b0", on: "b", in: scene), "Open", "and it still shows what it was last drawn with (w10 starts on)")
    }

    func testATabThatWasShownAndLeftEvaluatesNothingWhileItIsAway() throws {
        let scene = try makeScene()
        let home = try scene.page("a")
        try select("b", from: home, in: scene)
        drain(scene)
        let shownB = try scene.page("b")
        try select("a", from: shownB, in: scene)
        drain(scene)
        let start = runs(scene)
        flipTabB(scene, generation: 1)
        flipTabB(scene, generation: 2)
        flipTabB(scene, generation: 3)
        drain(scene)
        XCTAssertEqual(runs(scene) - start, 0, "three bursts over eight entities, no run: the tab is away")
    }

    func testTheOnScreenTabKeepsRunningWhileTheOtherIsAway() throws {
        let scene = try makeScene()
        _ = try scene.page("b")
        drain(scene)
        let start = runs(scene)
        _ = scene.store.apply((0..<4).map { EntityState(entityId: LogicHouse.watched($0), state: LogicHouse.state($0, generation: 1)) })
        drain(scene)
        XCTAssertEqual(runs(scene) - start, 4, "the page on screen runs one evaluation per changed node, as before")
    }

    func testTheTabBadgeKeepsRunningWhileItsTabIsAway() throws {
        let scene = try makeScene()
        _ = try scene.page("b")
        drain(scene)
        let nav = try XCTUnwrap(scene.renderer.stacks[.tab("b")])
        XCTAssertEqual(nav.tabBarItem.badgeValue, "2", "w20 starts on")
        let start = runs(scene)
        _ = scene.store.apply([EntityState(entityId: LogicHouse.watched(20), state: LogicHouse.state(20, generation: 1))])
        drain(scene)
        XCTAssertEqual(runs(scene) - start, 1, "the badge's one observation ran: it belongs to the renderer, and is on screen in the tab bar")
        XCTAssertEqual(nav.tabBarItem.badgeValue, "1", "and the bar item shows the new count with its tab away")
    }

    // MARK: Back

    func testTheFirstFrameOfATabThatComesBackAlreadyShowsTheChanges() throws {
        let scene = try makeScene()
        let home = try scene.page("a")
        try select("b", from: home, in: scene)
        drain(scene)
        let shownB = try scene.page("b")
        let before = try (0..<Self.textNodes).map { try words("b\($0)", on: "b", in: scene) }
        let hiddenBefore = try (0..<Self.shownNodes).map { try scene.view("c\($0)", on: "b").isHidden }
        try select("a", from: shownB, in: scene)
        drain(scene)

        flipTabB(scene, generation: 1)
        drain(scene)
        XCTAssertEqual(try (0..<Self.textNodes).map { try words("b\($0)", on: "b", in: scene) }, before, "away: nothing was redrawn")

        let start = runs(scene)
        try select("b", from: try scene.page("a"), in: scene)
        // No run-loop turn has happened since the selection: no frame has been drawn. The page's own `viewWillAppear` caught up.
        let after = try (0..<Self.textNodes).map { try words("b\($0)", on: "b", in: scene) }
        XCTAssertEqual(after, (0..<Self.textNodes).map { LogicHouse.state(10 + $0, generation: 1) == "on" ? "Open" : "Closed" },
                       "the first frame shows the new words")
        XCTAssertNotEqual(after, before)
        let hiddenAfter = try (0..<Self.shownNodes).map { try scene.view("c\($0)", on: "b").isHidden }
        XCTAssertEqual(hiddenAfter, (0..<Self.shownNodes).map { LogicHouse.state(16 + $0, generation: 1) != "on" }, "and the right nodes are shown")
        XCTAssertNotEqual(hiddenAfter, hiddenBefore)
        XCTAssertEqual(runs(scene) - start, Self.textNodes + Self.shownNodes, "each changed node ran once, in that one pass")
        drain(scene)
        XCTAssertEqual(runs(scene) - start, Self.textNodes + Self.shownNodes, "and nothing ran after it")
        XCTAssertTrue(shownB === (try scene.page("b")), "the same page and the same views: nothing was rebuilt")
    }

    func testATabThatWasNeverShownCatchesUpOnItsFirstAppearance() throws {
        let scene = try makeScene()
        _ = try scene.page("b")
        drain(scene)
        flipTabB(scene, generation: 1)
        drain(scene)
        let start = runs(scene)
        try select("b", from: try scene.page("a"), in: scene)
        // A tab's first appearance is sent with its first layout, which is before its first frame is committed: lay the window out, spin nothing.
        HostedPage.layoutTracked()
        XCTAssertEqual(try words("b0", on: "b", in: scene), LogicHouse.state(10, generation: 1) == "on" ? "Open" : "Closed")
        XCTAssertEqual(runs(scene) - start, Self.textNodes + Self.shownNodes)
    }

    func testAChangeThatIsUndoneWhileAwayWritesNothingOnReturn() throws {
        let scene = try makeScene()
        let home = try scene.page("a")
        try select("b", from: home, in: scene)
        drain(scene)
        let shownB = try scene.page("b")
        try select("a", from: shownB, in: scene)
        drain(scene)
        flipTabB(scene, generation: 1)
        flipTabB(scene, generation: 2)   // the parity of generation 0: back to what the page shows
        drain(scene)
        let tally = scene.renderer.bindings.logicTally
        let start = (tally.runs, tally.skippedEqual)
        try select("b", from: try scene.page("a"), in: scene)
        XCTAssertEqual(tally.runs - start.0, Self.textNodes + Self.shownNodes, "each node was changed, so each ran once on return")
        XCTAssertEqual(tally.skippedEqual - start.1, Self.shownNodes, "and the visibility ones found their answer unchanged and wrote no view")
    }

    func testAChangeAfterTheTabIsBackRunsAsBefore() throws {
        let scene = try makeScene()
        let home = try scene.page("a")
        try select("b", from: home, in: scene)
        drain(scene)
        let shownB = try scene.page("b")
        try select("a", from: shownB, in: scene)
        flipTabB(scene, generation: 1)
        drain(scene)
        try select("b", from: try scene.page("a"), in: scene)
        drain(scene)
        let start = runs(scene)
        flipTabB(scene, generation: 2)
        drain(scene)
        XCTAssertEqual(runs(scene) - start, Self.textNodes + Self.shownNodes, "back on screen, a change runs one evaluation per node that reads it")
    }
}
