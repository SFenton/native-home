import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

// MARK: - A tile inside a wrapper takes the span its content needs

/// The content-aware span (owner, 2026-11-01; `.agents/patterns/dynamic-grid.md`) for a tile that sits inside a wrapper, as a media
/// source tile sits inside the remote atom and a robot card inside a column. The grid reads a tile's minimum width from the view it
/// holds, so a wrapper that reported none left a one-disc media card or a robot card squeezed into one track; a wrapper now reports the
/// widest minimum among the views it hosts (``UKGridWrapping``).
///
/// The grids are 150 minimum, at most 4 columns, as the reference's tile grids are. Each test runs at the spec's widths (350 and 637)
/// and at the iPhone, folded Duo and iPad widths, so a rule that only holds for one family fails here. The grid is laid out at its own
/// frame, so the result does not depend on which family's simulator runs it.
@MainActor
final class UKHostedContentSpanTests: XCTestCase {
    /// The iPhone, the folded Duo and the iPad portrait widths.
    private static let familyWidths: [CGFloat] = [393, 466, 834]

    override func tearDown() async throws {
        HostedPage.hideTracked()
        HostedPage.resetGlobals()
        try await super.tearDown()
    }

    // MARK: Fixtures

    /// A media source tile as the remote atom draws it: a navigation tile with the power disc, the family's states known up front.
    private func mediaCard() -> UKGlassTileView {
        let power = TileActionItem(id: "power", verb: "Turn On", symbol: "power", isOn: false)
        var model = UKGlassTileModel(title: "Demo Media", subtitle: "Off", symbol: "tv", family: .media, isActive: false,
                                     behavior: TileBehavior(.navigation(actionCount: 1), primary: nil), actions: [power], identifier: "demo_media")
        model.stateCandidates = ["On", "Off", "Unavailable", "Didn't Respond"]
        return UKGlassTileView(model: model)
    }

    /// A robot card as the vacuum lowering draws it: a navigation tile with the start and dock discs and the words of every state.
    private func robotCard(_ id: String = "demo_robot") -> UKGlassTileView {
        let start = TileActionItem(id: "start", verb: "Start", symbol: "play.fill")
        let dock = TileActionItem(id: "dock", verb: "Dock", symbol: "house.fill")
        var model = UKGlassTileModel(title: "Demo Robot", subtitle: "Docked • 80%", symbol: "robotic.vacuum", family: .cleaning, isActive: false,
                                     behavior: TileBehavior(.classify(hasDestination: true, actions: 2), primary: nil), actions: [start, dock],
                                     identifier: id)
        model.stateCandidates = ["Docked • 100%", "Cleaning • 100%", "Returning • 100%", "Paused • 100%", "Unavailable"]
        return UKGlassTileView(model: model)
    }

    /// A tile with no discs and no state candidates, as a Food Spaces link tile is: it has no opinion on its width.
    private func plainTile(_ title: String) -> UKGlassTileView {
        UKGlassTileView(model: UKGlassTileModel(title: title, subtitle: "Pantry", symbol: "cabinet", isActive: false, kind: .navigate,
                                                identifier: title))
    }

    /// `tile` inside the shared wrapper the server-driven atoms use.
    private func wrapped(_ tile: UKGlassTileView) -> UKColumnView {
        let column = UKColumnView(spacing: HassTokens.Spacing.s)
        column.setViews([tile])
        return column
    }

    private func laidOut(_ items: [UIView], width: CGFloat) -> (UKDynamicGridView, UIWindow) {
        let grid = UKDynamicGridView(configuration: UKGridConfiguration(minCellWidth: 150, maxColumns: 4))
        let host = UIViewController()
        let window = HostedPage.show(host)
        host.view.addSubview(grid)
        grid.frame = CGRect(x: 0, y: 60, width: width, height: 10)
        grid.setItems(items.map { UKGridItem($0) })
        grid.layoutIfNeeded()
        return (grid, window)
    }

    // MARK: What each tile reports

    func testTheMinimumsTheMediaAndRobotTilesReport() {
        let media = mediaCard(), robot = robotCard(), plain = plainTile("Pantry")
        let wrappedMedia = wrapped(media), wrappedRobot = wrapped(robot)
        print("MINIMUM media=\(media.gridMinimumWidth) robot=\(robot.gridMinimumWidth) plain=\(plain.gridMinimumWidth)"
              + " wrappedMedia=\(wrappedMedia.gridMinimumWidth) wrappedRobot=\(wrappedRobot.gridMinimumWidth)")
        XCTAssertGreaterThan(media.gridMinimumWidth, 150, "a one-disc media card needs more than a track of 150")
        XCTAssertGreaterThan(robot.gridMinimumWidth, media.gridMinimumWidth, "two discs and a longer state line need more than one disc")
        XCTAssertEqual(plain.gridMinimumWidth, 0, "a tile with no discs has no opinion")
        XCTAssertEqual(wrappedMedia.gridMinimumWidth, media.gridMinimumWidth, "the wrapper reports what its tile reports")
        XCTAssertEqual(wrappedRobot.gridMinimumWidth, robot.gridMinimumWidth)
        XCTAssertEqual(wrapped(plain).gridMinimumWidth, 0)
    }

    func testAHiddenTileInsideAWrapperTakesNoRoom() {
        let media = mediaCard()
        let column = wrapped(media)
        media.isHidden = true
        XCTAssertEqual(column.gridMinimumWidth, 0, "a hidden view takes no room, so it asks for none")
        let nested = UIStackView(arrangedSubviews: [mediaCard()])
        let holder = UKColumnView()
        holder.setViews([nested])
        XCTAssertGreaterThan(holder.gridMinimumWidth, 150, "a plain container between the wrapper and its tile does not hide the minimum")
    }

    // MARK: The row

    func testAMediaCardAndARobotCardEachTakeTheFullRowAt350() {
        let (grid, window) = laidOut([wrapped(mediaCard()), wrapped(robotCard())], width: 350)
        defer { window.isHidden = true }
        let frames = grid.items.map(\.view.frame)
        XCTAssertEqual(frames[0].width, 350, accuracy: 1, "the one-disc media card takes the full row")
        XCTAssertEqual(frames[1].width, 350, accuracy: 1, "the robot card takes the full row")
        XCTAssertLessThan(frames[0].maxY, frames[1].minY + 1, "one under the other")
    }

    func testATileWithNoDiscsStaysOneTrack() {
        let (grid, window) = laidOut([plainTile("Pantry"), plainTile("Fridge"), wrapped(mediaCard())], width: 350)
        defer { window.isHidden = true }
        let frames = grid.items.map(\.view.frame)
        XCTAssertEqual(frames[0].minY, frames[1].minY, accuracy: 1, "two plain tiles sit two up at 350")
        XCTAssertLessThan(frames[0].width, 200)
        XCTAssertEqual(frames[0].width, frames[1].width, accuracy: 1)
        XCTAssertEqual(frames[2].width, 350, accuracy: 1, "the media card under them takes the row")
    }

    func testTwoRobotCardsSitTwoAcrossAt637() {
        let (grid, window) = laidOut([wrapped(robotCard("one")), wrapped(robotCard("two"))], width: 637)
        defer { window.isHidden = true }
        let frames = grid.items.map(\.view.frame)
        XCTAssertEqual(frames[0].minY, frames[1].minY, accuracy: 1, "two robot cards per row at 637")
        XCTAssertLessThan(frames[0].maxX, frames[1].minX + 1)
        XCTAssertLessThanOrEqual(frames[1].maxX, 637 + 1)
    }

    // MARK: Every family

    func testNoWrappedTileIsSqueezedBelowItsMinimumAtAnyFamilyWidth() {
        for width in Self.familyWidths + [350, 637] {
            let media = mediaCard(), robot = robotCard()
            let (grid, window) = laidOut([wrapped(media), wrapped(robot), plainTile("Pantry"), plainTile("Fridge")], width: width)
            defer { window.isHidden = true }
            let frames = grid.items.map(\.view.frame)
            XCTAssertGreaterThanOrEqual(frames[0].width + 0.5, media.gridMinimumWidth, "media card at \(width)")
            XCTAssertGreaterThanOrEqual(frames[1].width + 0.5, robot.gridMinimumWidth, "robot card at \(width)")
            for frame in frames { XCTAssertLessThanOrEqual(frame.maxX, width + 1, "inside the grid at \(width)") }
        }
    }

    /// The accessibility half: a tile that takes the tracks its content needs shows its whole state line and keeps its discs reachable.
    func testAWrappedTileKeepsItsDiscsAtLeast44ptAndItsLabelsAtEveryFamilyWidth() {
        for width in Self.familyWidths + [350, 637] {
            let media = mediaCard(), robot = robotCard()
            let (grid, window) = laidOut([wrapped(media), wrapped(robot)], width: width)
            defer { window.isHidden = true }
            HostedPage.layoutTracked()
            for (tile, title, discs) in [(media, "Demo Media", 1), (robot, "Demo Robot", 2)] {
                XCTAssertTrue(tile.accessibilityLabel?.contains(title) == true, "\(title) keeps its label at \(width)")
                XCTAssertFalse(tile.accessibilityValue?.isEmpty ?? true, "\(title) keeps its spoken value at \(width)")
                let controls = HostedPage.descendants(of: tile).compactMap { $0 as? UKTileActionDisc }
                XCTAssertEqual(controls.count, discs, "\(title) at \(width)")
                for disc in controls {
                    XCTAssertGreaterThanOrEqual(disc.bounds.width, 44 - 0.5, "a disc is at least 44 pt wide at \(width)")
                    XCTAssertGreaterThanOrEqual(disc.bounds.height, 44 - 0.5, "and 44 pt tall at \(width)")
                    XCTAssertFalse(disc.accessibilityLabel?.isEmpty ?? true, "each disc is named for VoiceOver at \(width)")
                }
            }
            XCTAssertEqual(grid.items.map(\.view.isAccessibilityElement), [false, false], "the wrapper itself is not an element: its tile is")
        }
    }

    // MARK: A long-status authored state tile

    /// The models the authored long-status tiles draw (`AuthoredLongStatusTile`: a state tile over a generic sensor, each state's longest line as its
    /// rule text), taken from the real renderer once and then laid out as tiles of their own at the exact family widths, whatever the simulator.
    private func authoredStatusModels() throws -> [UKGlassTileModel] {
        let store = EntityStore()
        store.replaceAll([AuthoredLongStatusTile.sensor("a", state: "running"), AuthoredLongStatusTile.sensor("b", state: "off")])
        let host = try UKServerUIRenderer(publication: AuthoredLongStatusTile.publication(), context: UKContext(store: store, caller: HostedCaller()),
                                          backdrop: ServerUIRendererFixture.backdrop())
        let window = HostedPage.show(host, size: HostedPage.inScene(CGSize(width: 390, height: 1180)))
        defer { window.isHidden = true }
        HostedPage.wait(0.1)
        let root = try ServerUIRendererFixture.root(host)
        root.view.layoutIfNeeded()
        return try ["a", "b"].map { try XCTUnwrap(root.nodes["unit-\($0)"]?.view as? UKGlassTileView, "tile \($0)").model }
    }

    /// Two authored tiles stack at 390 and 466 and share a row at 744 and 868 only where two minimums fit; neither is squeezed below its own.
    func testAuthoredLongStatusTilesStackAtPhoneWidthsAndShareOnlyWhereTheMinimumsFit() throws {
        let models = try authoredStatusModels()
        var minimum: CGFloat = 0
        for width in [390, 466, 744, 868] as [CGFloat] {
            let tiles = models.map { UKGlassTileView(model: $0) }
            minimum = tiles[0].gridMinimumWidth
            let (grid, window) = laidOut(tiles.map(wrapped), width: width)
            defer { window.isHidden = true }
            let frames = grid.items.map(\.view.frame)
            let sharing = abs(frames[0].minY - frames[1].minY) < 1
            print("LONGSPAN width=\(width) minimum=\(minimum) share=\(sharing) frames=\(frames.map { "\($0.minX),\($0.minY) \($0.width)x\($0.height)" })")
            XCTAssertGreaterThan(minimum, 150, "the longest line asks for more than one track (\(width))")
            for frame in frames {
                XCTAssertGreaterThanOrEqual(frame.width + 0.5, minimum, "never squeezed below its minimum at \(width)")
                XCTAssertLessThanOrEqual(frame.maxX, width + 1)
            }
            XCTAssertEqual(sharing, 2 * minimum + HassTokens.Spacing.m <= width + 0.5,
                           "two tiles share a row exactly when both minimums fit (\(width), minimum \(minimum))")
            if sharing {
                XCTAssertLessThan(frames[0].maxX, frames[1].minX + 1, "side by side at \(width)")
            } else {
                XCTAssertEqual(frames[0].width, width, accuracy: 1, "a stacked tile takes the row at \(width)")
                XCTAssertLessThan(frames[0].maxY, frames[1].minY + 1)
            }
            if width <= 466 { XCTAssertFalse(sharing, "one tile per row at \(width)") }
        }
        XCTAssertGreaterThan(minimum, 0)
    }

    /// Touch height and accessibility of the authored tile at the exact family widths: at least 44 pt tall, title and line spoken, never a disc.
    func testAuthoredLongStatusTilesKeepTheirHeightAndSpeechAtEveryFamilyWidth() throws {
        let models = try authoredStatusModels()
        for width in [390, 466, 744, 868] as [CGFloat] {
            let tiles = models.map { UKGlassTileView(model: $0) }
            let (grid, window) = laidOut(tiles.map(wrapped), width: width)
            defer { window.isHidden = true }
            HostedPage.layoutTracked()
            for (tile, title) in zip(tiles, ["Unit A", "Unit B"]) {
                XCTAssertEqual(tile.accessibilityLabel, title, "width \(width)")
                XCTAssertFalse(tile.accessibilityValue?.isEmpty ?? true, "\(title) speaks its line at \(width)")
                XCTAssertGreaterThanOrEqual(tile.bounds.height, 44 - 0.5, "\(title) is at least 44 pt tall at \(width)")
                XCTAssertTrue(HostedPage.descendants(of: tile).compactMap { $0 as? UKTileActionDisc }.isEmpty, "no disc on \(title)")
            }
            XCTAssertEqual(grid.items.map(\.view.isAccessibilityElement), [false, false], "the wrapper is not an element: its tile is")
        }
    }
}

