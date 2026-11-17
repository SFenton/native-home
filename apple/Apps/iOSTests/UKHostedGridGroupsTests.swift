import HassCore
import UIKit
import XCTest
@testable import HassUI

/// A long press that reports the state the test says.
private final class ScriptedPress: UILongPressGestureRecognizer {
    var scriptedState: UIGestureRecognizer.State = .possible
    override var state: UIGestureRecognizer.State {
        get { scriptedState }
        set {}
    }
}

/// A scroll view whose drag and deceleration flags the test sets, as a finger and a fling would.
private final class ScriptedScroll: UIScrollView {
    var scriptedDragging = false
    var scriptedDecelerating = false
    override var isDragging: Bool { scriptedDragging }
    override var isDecelerating: Bool { scriptedDecelerating }
}

// MARK: - Grid groups, UX and accessibility

/// Hosted UX and accessibility checks for `tile-grid` groups by state (`sh.grid-state-groups@1`): the headings, the dropped empty group, the move
/// of a tile whose face changed, and the motion rules of `.agents/design/motion.md` section 6 (a person's tap slides, the house's change does not,
/// Reduce Motion fades). Each runs at the page widths of the three families: the folded iPhone Duo, the iPhone and the iPad.
@MainActor
final class UKHostedGridGroupsTests: XCTestCase {
    private static let widths: [CGFloat] = [364, 393, 834]
    private let groups = ServerUIGridGroups(items: [
        .init(id: "on", title: "On", states: [.active]),
        .init(id: "off", title: "Off", states: [.idle]),
        .init(id: "gone", title: "Not Answering", states: [.unavailable]),
    ])

    override func tearDown() async throws {
        UKMotion.reduceMotionOverride = nil
        HostedPage.hideTracked()
        HostedPage.resetGlobals()
        try await super.tearDown()
    }

    private struct Fixture {
        let window: UIWindow
        let grid: UKDynamicGridView
        let grouping: UKServerUIGridGrouping
        let tiles: [UKGlassTileView]
        let scroll: ScriptedScroll
    }

    private func model(_ title: String, active: Bool = false, unavailable: Bool = false) -> UKGlassTileModel {
        UKGlassTileModel(title: title, subtitle: active ? "On" : "Off", symbol: "lightbulb", family: .neutral, isActive: active,
                         isUnavailable: unavailable, kind: .toggle)
    }

    private func fixture(width: CGFloat, faces: [(active: Bool, unavailable: Bool)], category: UIContentSizeCategory? = nil) -> Fixture {
        let host = UIViewController()
        if let category { host.traitOverrides.preferredContentSizeCategory = category }
        let window = HostedPage.show(host)
        let scroll = ScriptedScroll(frame: CGRect(x: 0, y: 80, width: width, height: 600))
        host.view.addSubview(scroll)
        let grid = UKDynamicGridView()
        scroll.addSubview(grid)
        let tiles = faces.enumerated().map { index, face in
            UKGlassTileView(model: model("Tile \(index)", active: face.active, unavailable: face.unavailable), environment: UKTileEnvironment())
        }
        let grouping = UKServerUIGridGrouping(groups, gridID: "grid", grid: grid, surface: .page)
        grid.regroupItems(grouping.items(tiles.map { ($0, 1) }))
        grid.frame = CGRect(x: 0, y: 0, width: width, height: grid.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height)
        grid.layoutIfNeeded()
        scroll.contentSize = CGSize(width: width, height: 4000)
        return Fixture(window: window, grid: grid, grouping: grouping, tiles: tiles, scroll: scroll)
    }

    private func order(_ f: Fixture) -> [String] {
        f.grid.items.map { item in
            (item.view as? UKPageSectionHeaderView).map { "#" + ($0.accessibilityIdentifier ?? "") } ?? (item.view as? UKGlassTileView)?.model.title ?? "?"
        }
    }

    private func press(_ grouping: UKServerUIGridGrouping, _ states: [UIGestureRecognizer.State]) {
        let scripted = ScriptedPress()
        for state in states {
            scripted.scriptedState = state
            grouping.perform(NSSelectorFromString("pressed:"), with: scripted)
        }
    }

    // MARK: Headings

    func testEachGroupHasAHeaderTheTilesSitUnderAndAnEmptyGroupIsDropped() throws {
        for width in Self.widths {
            let f = fixture(width: width, faces: [(false, false), (true, false), (false, false)])
            defer { f.window.isHidden = true }
            XCTAssertEqual(order(f), ["#grid.group.on", "Tile 1", "#grid.group.off", "Tile 0", "Tile 2"],
                           "lit first, idle after, the group with no tile has no heading (width \(width))")
            let headers = f.grid.items.compactMap { $0.view as? UKPageSectionHeaderView }
            XCTAssertEqual(headers.count, 2)
            for header in headers {
                XCTAssertTrue(HostedPage.descendants(of: header).contains { $0.accessibilityTraits.contains(.header) },
                              "a heading VoiceOver can jump by (width \(width))")
                XCTAssertEqual(header.frame.width, f.grid.bounds.width, accuracy: 0.5, "a heading takes the whole row")
            }
            XCTAssertLessThan(f.tiles[1].frame.maxY, f.tiles[0].frame.minY, "the lit tile is above the idle ones")
        }
    }

    func testColumnsAreSolvedOnceSoTilesLineUpAcrossGroups() throws {
        let f = fixture(width: 834, faces: [(true, false), (true, false), (false, false), (false, false)])
        defer { f.window.isHidden = true }
        XCTAssertEqual(f.tiles[0].frame.width, f.tiles[2].frame.width, accuracy: 0.5)
        XCTAssertEqual(f.tiles[0].frame.minX, f.tiles[2].frame.minX, accuracy: 0.5, "the first column of both groups is the same column")
    }

    func testAllThreeGroupsShowWhenEachStateHasATile() throws {
        let f = fixture(width: 393, faces: [(true, false), (false, false), (false, true)])
        defer { f.window.isHidden = true }
        XCTAssertEqual(f.grid.items.filter(\.isHeader).count, 3)
        XCTAssertEqual(order(f).last, "Tile 2")
    }

    // MARK: Moving

    func testAHouseChangeMovesTheSameTileWithNoAnimationAndNoRebuild() throws {
        for width in Self.widths {
            let f = fixture(width: width, faces: [(false, false), (true, false)])
            defer { f.window.isHidden = true }
            f.tiles[0].configure(model("Tile 0", active: true), animated: false)
            HostedPage.wait(0.3)
            XCTAssertEqual(order(f), ["#grid.group.on", "Tile 0", "Tile 1"], "both lit now; the idle group is dropped (width \(width))")
            XCTAssertEqual(f.grouping.regroupCount, 1, "one arrangement for the change")
            XCTAssertTrue(f.tiles[0].superview === f.grid, "the same view moved: not rebuilt")
            XCTAssertNil(f.tiles[0].layer.animationKeys(), "a change the house made does not animate")
            XCTAssertEqual(f.tiles[0].alpha, 1)
        }
    }

    func testAPersonsTapSlidesTheTileAndReduceMotionFadesItInstead() throws {
        let f = fixture(width: 393, faces: [(false, false), (true, false)])
        defer { f.window.isHidden = true }
        press(f.grouping, [.began, .ended])
        f.tiles[0].configure(model("Tile 0", active: true), animated: false)
        HostedPage.wait(0.1)
        XCTAssertEqual(f.grouping.regroupCount, 1)
        XCTAssertEqual(order(f), ["#grid.group.on", "Tile 0", "Tile 1"])

        UKMotion.reduceMotionOverride = true
        let g = fixture(width: 393, faces: [(false, false), (true, false)])
        defer { g.window.isHidden = true }
        press(g.grouping, [.began, .ended])
        g.tiles[0].configure(model("Tile 0", active: true), animated: false)
        HostedPage.wait(0.05)
        XCTAssertEqual(g.grouping.regroupCount, 1)
        let keys = g.tiles[0].layer.animationKeys() ?? []
        XCTAssertTrue(keys.contains("opacity"), "Reduce Motion: the moved tile fades in (\(keys))")
        XCTAssertFalse(keys.contains("position"), "Reduce Motion: no slide")
    }

    func testAChangeWaitsWhileAFingerIsOnTheGridThenApplies() throws {
        let f = fixture(width: 393, faces: [(false, false), (true, false)])
        defer { f.window.isHidden = true }
        press(f.grouping, [.began])
        f.tiles[0].configure(model("Tile 0", active: true), animated: false)
        HostedPage.wait(0.2)
        XCTAssertEqual(f.grouping.regroupCount, 0, "nothing moves under the finger")
        XCTAssertEqual(order(f), ["#grid.group.on", "Tile 1", "#grid.group.off", "Tile 0"])
        press(f.grouping, [.ended])
        HostedPage.wait(0.2)
        XCTAssertEqual(f.grouping.regroupCount, 1)
        XCTAssertEqual(order(f), ["#grid.group.on", "Tile 0", "Tile 1"])
    }

    func testTwoChangesInOneTurnMakeOneArrangement() throws {
        let f = fixture(width: 393, faces: [(false, false), (false, false), (true, false)])
        defer { f.window.isHidden = true }
        f.tiles[0].configure(model("Tile 0", active: true), animated: false)
        f.tiles[1].configure(model("Tile 1", unavailable: true), animated: false)
        HostedPage.wait(0.3)
        XCTAssertEqual(f.grouping.regroupCount, 1)
    }

    // MARK: Reapply

    func testASnapshotOrReconnectReapplyNeverAnimatesEvenRightAfterATap() throws {
        for reduced in [false, true] {
            UKMotion.reduceMotionOverride = reduced
            let f = fixture(width: 393, faces: [(false, false), (true, false)])
            defer { f.window.isHidden = true }
            var generation = 0
            f.grouping.reapplyGeneration = { generation }
            press(f.grouping, [.began, .ended])
            generation += 1
            f.tiles[0].configure(model("Tile 0", active: true), animated: false)
            HostedPage.wait(0.1)
            XCTAssertEqual(f.grouping.regroupCount, 1)
            XCTAssertEqual(order(f), ["#grid.group.on", "Tile 0", "Tile 1"], "it still moves (reduce motion \(reduced))")
            XCTAssertNil(f.tiles[0].layer.animationKeys(), "a reapply never animates, whoever tapped last")
            XCTAssertEqual(f.tiles[0].alpha, 1, "and never fades")
        }
    }

    // MARK: Touches and scrolls

    func testOnlyARealTapCountsAndATouchThatEndedAScrollDoesNot() throws {
        let f = fixture(width: 393, faces: [(false, false), (true, false)])
        defer { f.window.isHidden = true }
        press(f.grouping, [.began])
        f.scroll.contentOffset = CGPoint(x: 0, y: 160)
        press(f.grouping, [.ended])
        XCTAssertNil(f.grouping.lastTap, "the finger scrolled the page: not a tap")
        f.tiles[0].configure(model("Tile 0", active: true), animated: false)
        HostedPage.wait(0.1)
        XCTAssertEqual(f.grouping.regroupCount, 1)
        XCTAssertNil(f.tiles[0].layer.animationKeys(), "a house change right after a scroll does not slide")
        press(f.grouping, [.began, .ended])
        XCTAssertNotNil(f.grouping.lastTap, "a touch that moved nothing is a tap")
    }

    func testAChangeHeldByAScrollAppliesWhenTheDecelerationEndsWithNoNewTouch() throws {
        for width in Self.widths {
            let f = fixture(width: width, faces: [(false, false), (true, false)])
            defer { f.window.isHidden = true }
            f.scroll.scriptedDragging = true
            f.tiles[0].configure(model("Tile 0", active: true), animated: false)
            HostedPage.wait(0.2)
            XCTAssertEqual(f.grouping.regroupCount, 0, "nothing moves under a dragging scroll (width \(width))")
            // The finger lifts into a fling: the offset keeps changing while it decelerates.
            f.scroll.scriptedDragging = false
            f.scroll.scriptedDecelerating = true
            f.scroll.contentOffset = CGPoint(x: 0, y: 40)
            HostedPage.wait(0.2)
            f.scroll.contentOffset = CGPoint(x: 0, y: 55)
            XCTAssertEqual(f.grouping.regroupCount, 0, "still decelerating: still held")
            // The last offset change happens while the flag is still set; the flag clears with no further change.
            f.scroll.scriptedDecelerating = false
            HostedPage.wait(0.5)
            XCTAssertEqual(f.grouping.regroupCount, 1, "applied once the scroll is over, with no new touch (width \(width))")
            XCTAssertEqual(order(f), ["#grid.group.on", "Tile 0", "Tile 1"])
            XCTAssertNil(f.tiles[0].layer.animationKeys(), "nobody tapped: no animation")
        }
    }

    // MARK: Accessibility

    func testAtTheLargestTextSizeTheHeadingsStayFullRowsWithTheHeaderTraitAndNothingOverlaps() throws {
        for width in Self.widths {
            let f = fixture(width: width, faces: [(false, false), (true, false), (false, true)], category: .accessibilityExtraExtraExtraLarge)
            defer { f.window.isHidden = true }
            XCTAssertEqual(f.grid.items.filter(\.isHeader).count, 3, "width \(width)")
            for item in f.grid.items {
                XCTAssertLessThanOrEqual(item.view.frame.maxX, f.grid.bounds.width + 0.5, "nothing leaves the grid at AX5")
                if item.isHeader { XCTAssertEqual(item.view.frame.width, f.grid.bounds.width, accuracy: 0.5) }
            }
            for header in f.grid.items.compactMap({ $0.view as? UKPageSectionHeaderView }) {
                XCTAssertTrue(HostedPage.descendants(of: header).contains { $0.accessibilityTraits.contains(.header) })
                XCTAssertGreaterThanOrEqual(header.frame.height, 28, "a heading at AX5 has room for its text")
            }
            let frames = f.grid.items.map(\.view.frame)
            for (index, frame) in frames.enumerated() {
                for other in frames[(index + 1)...] { XCTAssertFalse(frame.intersects(other.insetBy(dx: 1, dy: 1)), "no overlap at AX5 (width \(width))") }
            }
        }
    }

    func testAMovedTileIsTheSameElementSoVoiceOverFocusStaysOnIt() throws {
        for width in Self.widths {
            let f = fixture(width: width, faces: [(false, false), (true, false)])
            defer { f.window.isHidden = true }
            let tile = f.tiles[0]
            let element = tile.accessibilityElements?.first as AnyObject?
            tile.configure(model("Tile 0", active: true), animated: false)
            HostedPage.wait(0.2)
            XCTAssertEqual(f.grouping.regroupCount, 1)
            XCTAssertTrue(tile.superview === f.grid, "the same view: not rebuilt (width \(width))")
            XCTAssertTrue((tile.accessibilityElements?.first as AnyObject?) === element, "the same accessibility element: focus is kept")
            XCTAssertTrue(f.tiles[1].superview === f.grid)
            XCTAssertEqual(order(f), ["#grid.group.on", "Tile 0", "Tile 1"], "the heading is read before the tiles under it")
        }
    }
}
