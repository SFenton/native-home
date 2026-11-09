import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

/// What the section-column tests need of a grid: fill it with plain views and read their frames.
@MainActor
protocol UKGridItemsProviding: AnyObject {
    func setViews(_ views: [UIView])
    var itemViews: [UIView] { get }
}

extension UKDynamicGridView: UKGridItemsProviding {
    func setViews(_ views: [UIView]) { setItems(views.map { UKGridItem($0) }) }
    var itemViews: [UIView] { items.map(\.view) }
}

extension UKFlexGridView: UKGridItemsProviding {
    func setViews(_ views: [UIView]) { setItems(views) }
    var itemViews: [UIView] { items.map(\.view) }
}

/// Duo widths (`.agents/design/duo-widths.md`): short rows fill their section, section grids never go two-up in a portrait-shaped window,
/// and a lone last section spans both columns.
@MainActor
final class UKHostedGridFillTests: DemoHouseTestCase {
    private func solve(width: CGFloat, spans: [Int], fill: UKGridFill = .share, minCellWidth: CGFloat = 150, maxColumns: Int = 4,
                       band: ClosedRange<CGFloat>? = nil, equalRows: Bool = false, heights: [CGFloat]? = nil,
                       record: ((Int, CGFloat) -> Void)? = nil) -> UKGridSolution {
        var config = UKGridConfiguration(minCellWidth: minCellWidth, maxColumns: maxColumns, equalRowHeights: equalRows, fill: fill)
        if let band {
            config.evenColumns = true
            config.hingeBand = band
        }
        return UKGridSolver.solve(width: width, configuration: config, spans: spans, headers: spans.map { _ in false }) { index, width in
            record?(index, width)
            return heights?[index] ?? 60
        }
    }

    // MARK: Solver

    private func widthsOf(_ solution: UKGridSolution) -> [Int] { solution.frames.map { Int($0.width.rounded()) } }

    func testAOneRowGridSharesEquallyAndNoneKeepsTheTrack() {
        let share = solve(width: 637, spans: [1, 1, 1], fill: .share)
        let none = solve(width: 637, spans: [1, 1, 1], fill: .none)
        XCTAssertEqual(share.frames[0].width, 204.33, accuracy: 0.01)
        XCTAssertEqual(share.frames[2].maxX, 637, accuracy: 0.01)
        XCTAssertEqual(none.frames[0].width, none.frames[2].width, accuracy: 0.01)
        XCTAssertLessThan(none.frames[2].maxX, 637 - 100, "short rows stay leading")
    }

    func testAGridOfSeveralRowsFillsShortRowsInWholeTracks() {
        // 637 pt, four tracks of 150.25 and 12 pt gaps: a track is 150.25, two are 312.5, four are 637.
        let track = 150.25, two = 312.5
        // 4 + 3 becomes 4 + (1, 1, 2).
        let bed = solve(width: 637, spans: Array(repeating: 1, count: 7))
        XCTAssertEqual(bed.frames[4].width, track, accuracy: 0.01)
        XCTAssertEqual(bed.frames[5].width, track, accuracy: 0.01)
        XCTAssertEqual(bed.frames[6].width, two, accuracy: 0.01)
        XCTAssertEqual(bed.frames[6].maxX, 637, accuracy: 0.01)
        XCTAssertEqual(bed.frames[4].minX, bed.frames[0].minX, accuracy: 0.01, "on the track lines of the row above")
        // Quick Links in three tracks (480 pt): a last row of two becomes (1, 2).
        let links = solve(width: 480, spans: Array(repeating: 1, count: 5))
        XCTAssertEqual(links.frames[3].width, links.frames[0].width, accuracy: 0.01)
        XCTAssertEqual(links.frames[4].width, links.frames[0].width * 2 + 12, accuracy: 0.01)
        // [1, 2, 2] in four becomes (2, 2) + (4).
        let mixed = solve(width: 637, spans: [1, 2, 2])
        XCTAssertEqual(widthsOf(mixed), [313, 313, 637])
        // A lone tile after a full row spans.
        XCTAssertEqual(solve(width: 637, spans: [1, 1, 1, 1, 1]).frames[4].width, 637, accuracy: 0.01)
    }

    func testAOneRowGridKeepsThirdsAndALoneTileSpans() {
        XCTAssertEqual(widthsOf(solve(width: 637, spans: [1, 1, 1])), [204, 204, 204])
        XCTAssertEqual(widthsOf(solve(width: 637, spans: [1])), [637])
    }

    func testAHeadingDoesNotMakeAOneRowGridSeveralRows() {
        var config = UKGridConfiguration()
        config.fill = .share
        let solution = UKGridSolver.solve(width: 637, configuration: config, spans: [Int.max, 1, 1, 1], headers: [true, false, false, false]) { _, _ in 60 }
        XCTAssertEqual(widthsOf(solution), [637, 204, 204, 204])
    }

    func testEachSideOfABandSnapsToItsOwnTracksInATwoRowGrid() {
        // 800 pt, band 380...420: two tracks of 184 a side.
        let solution = solve(width: 800, spans: Array(repeating: 1, count: 7), band: 380...420)
        // Row 1 is four tiles (two a side); row 2 is three: the leading side's two and the trailing side's lone tile, which spans its side.
        XCTAssertEqual(solution.frames[4].width, solution.frames[0].width, accuracy: 0.5)
        XCTAssertEqual(solution.frames[5].width, solution.frames[1].width, accuracy: 0.5)
        XCTAssertEqual(solution.frames[6].minX, 420, accuracy: 0.5)
        XCTAssertEqual(solution.frames[6].maxX, 800, accuracy: 0.5)
        for frame in solution.frames { XCTAssertFalse(frame.minX < 420 && frame.maxX > 380, "\(frame) crosses the band") }
    }

    func testAGridOfSmallControlsNeverFills() {
        let chips = solve(width: 637, spans: [1], minCellWidth: 52, maxColumns: 7)
        XCTAssertLessThan(chips.frames[0].width, 100)
    }

    func testALoneTileSpansItsRowAndReportsFullRow() {
        let solution = solve(width: 637, spans: [1])
        XCTAssertEqual(solution.frames[0].width, 637, accuracy: 0.01)
        XCTAssertEqual(solution.fullRow, [true])
        let none = solve(width: 637, spans: [1], fill: .none)
        XCTAssertEqual(none.fullRow, [false])
    }

    func testABandIsAWallForALoneTile() {
        let solution = solve(width: 800, spans: [1], band: 380...420)
        XCTAssertEqual(solution.frames[0].minX, 0, accuracy: 0.01)
        XCTAssertEqual(solution.frames[0].width, 380, accuracy: 0.5, "it fills its side, not the band")
        XCTAssertEqual(solution.fullRow, [true], "full row means its side")
        let three = solve(width: 800, spans: [1, 1, 1], band: 380...420)
        XCTAssertLessThanOrEqual(three.frames[1].maxX, 380.5)
        XCTAssertGreaterThanOrEqual(three.frames[2].minX, 420 - 0.5)
        XCTAssertEqual(three.frames[2].maxX, 800, accuracy: 0.5, "the trailing side's lone tile fills it")
    }

    func testEqualRowHeightsStillEqualiseAndTheHeightClosureGetsTheFilledWidth() {
        var asked: [Int: CGFloat] = [:]
        let solution = solve(width: 637, spans: [1, 1, 1, 1, 1], equalRows: true, heights: [40, 80, 40, 40, 40]) { asked[$0] = $1 }
        XCTAssertEqual(Set(solution.rowHeights).count, 1)
        XCTAssertEqual(asked[4] ?? 0, 637, accuracy: 0.01, "the lone tile in row 2 was measured at the filled width")
        XCTAssertEqual(asked[0] ?? 0, solution.frames[0].width, accuracy: 0.01)
    }

    func testAMirroredFlexGridFillsFromTheTrailingEdge() {
        let grid = UKFlexGridView(minWidth: 150, maxColumns: 4)
        let host = UIViewController()
        let window = HostedPage.show(host, size: CGSize(width: 637, height: 400))
        defer { window.isHidden = true }
        host.view.semanticContentAttribute = .forceRightToLeft
        grid.semanticContentAttribute = .forceRightToLeft
        host.view.addSubview(grid)
        grid.frame = CGRect(x: 0, y: 0, width: 637, height: 100)
        let views = (0..<3).map { _ in UIView() }
        grid.setItems(views)
        grid.layoutIfNeeded()
        XCTAssertEqual(views[0].frame.maxX, 637, accuracy: 0.5, "the first item sits at the trailing edge")
        XCTAssertEqual(views[2].frame.minX, 0, accuracy: 0.5, "the last fills to the leading edge")
        XCTAssertEqual(views[0].frame.width, views[1].frame.width, accuracy: 0.5)
    }

    // MARK: Section columns

    private func columns(of grid: UIView & UKGridItemsProviding, width: CGFloat, size: UIContentSizeCategory) -> Int {
        let host = UIViewController()
        host.traitOverrides.preferredContentSizeCategory = size
        let window = HostedPage.show(host, size: CGSize(width: width, height: 800))
        defer { window.isHidden = true }
        host.view.addSubview(grid)
        grid.frame = CGRect(x: 0, y: 0, width: width, height: 100)
        grid.setViews((0..<4).map { _ in UIView() })
        hostedSettle(0.1)
        grid.layoutIfNeeded()
        return Set(grid.itemViews.map { $0.frame.minX.rounded() }).count
    }

    func testASectionGridNeverGoesTwoUpInAPortraitShapedWindow() {
        let sizes: [UIContentSizeCategory] = [.extraSmall, .large, .accessibilityExtraExtraExtraLarge]
        for size in sizes {
            XCTAssertEqual(columns(of: UKRoomsGrid(minCellWidth: 340, maxColumns: 2, spacing: HassTokens.Spacing.xl, relativeTo: .body),
                                   width: 637, size: size), 1, "rooms grid at 637, \(size.rawValue)")
            XCTAssertEqual(columns(of: UKFlexGridView(minWidth: 340, maxColumns: 2, spacing: HassTokens.Spacing.xl, scaleStyle: .body),
                                   width: 637, size: size), 1, "flex grid at 637, \(size.rawValue)")
        }
        for make in [{ () -> UIView & UKGridItemsProviding in UKRoomsGrid(minCellWidth: 340, maxColumns: 2, spacing: HassTokens.Spacing.xl, relativeTo: .body) },
                     { UKFlexGridView(minWidth: 340, maxColumns: 2, spacing: HassTokens.Spacing.xl, scaleStyle: .body) }] {
            XCTAssertEqual(columns(of: make(), width: 836, size: .large), 2, "two section columns lying flat")
            XCTAssertEqual(columns(of: make(), width: 836, size: .accessibilityExtraExtraExtraLarge), 1, "text size removes a column")
            XCTAssertEqual(columns(of: make(), width: 802, size: .large), 2, "iPad portrait keeps two")
        }
    }

    // MARK: Surfaces

    private func tiles(in root: UIView) -> [UKGlassTileView] { HostedPage.descendants(of: root).compactMap { $0 as? UKGlassTileView } }

    func testEveryAdminTileFillsItsGrid() {
        for width in [637.0, 383.0] {
            let store = HouseholdSettingsFixtures.store()
            let recorder = HouseholdGalleryRecorder(store: store)
            let context = UKGalleryChrome.context(store: store, caller: recorder)
            let screen = UKHouseholdSettingsViewController.make(page: .admin, context: context)
            let window = HostedPage.show(UKGalleryChrome.wrap(screen, context: context), size: CGSize(width: width + 32, height: 2600))
            defer { window.isHidden = true }
            FeatureHost.settle(0.6)
            let opener = FeatureHost.view("admin.open.presenceOverrides", in: screen.view)
            let tile = opener as? UKGlassTileView ?? tiles(in: opener ?? screen.view).first
            let grid = tile?.superview
            XCTAssertNotNil(grid, "the opener sits in a grid at \(width)")
            if let tile, let grid {
                XCTAssertEqual(tile.frame.width, grid.bounds.width, accuracy: 1, "a lone Admin tile fills its section at \(width)")
            }
        }
    }

    private func room(_ id: String, width: CGFloat) throws -> (UIViewController, UIWindow) {
        let store = RoomsFixtures.store()
        let recorder = GalleryServiceRecorder(store: store)
        let log = LoggingResponder(RoomsGalleryCaller(recorder: recorder, bedroom: BedroomGalleryRecorder(store: store)))
        let context = UKGalleryChrome.context(store: store, caller: log)
        let page = try XCTUnwrap(RoomsConfig.page(id: id))
        let controller = UKRoomViewController(page: page, context: context, viewer: .resident1)
        let window = HostedPage.show(UINavigationController(rootViewController: controller), size: CGSize(width: width + 32, height: 2400))
        hostedSettle(0.5)
        return (controller, window)
    }

    func testTheWakeLightTileFillsItsSection() throws {
        let (controller, window) = try room("master-bedroom", width: 637)
        defer { window.isHidden = true }
        let wake = try XCTUnwrap(tiles(in: controller.view).first { $0.accessibilityLabel == RoomsConfig.WakeLight.title }, "the Wake-Light tile")
        let grid = try XCTUnwrap(wake.superview)
        XCTAssertEqual(wake.frame.width, grid.bounds.width, accuracy: 1)
    }

    func testTheVentAndTheAirPurifierShareTheirRow() throws {
        let (controller, window) = try room("living-room", width: 637)
        defer { window.isHidden = true }
        let all = tiles(in: controller.view)
        let vents = try XCTUnwrap(all.first { $0.accessibilityLabel == "Vents" }, "the Vents tile")
        let purifier = try XCTUnwrap(all.first { ($0.accessibilityLabel ?? "").contains("Purifier") }, "the Air Purifier tile")
        XCTAssertEqual(vents.frame.width, purifier.frame.width, accuracy: 1)
        XCTAssertEqual(vents.superview, purifier.superview)
    }

    func testAFlatLandscapeMediaPageGivesTheLoneTheaterRoomBothColumns() throws {
        let store = RoomsFixtures.store()
        let recorder = GalleryServiceRecorder(store: store)
        let context = UKGalleryChrome.context(store: store, caller: RoomsGalleryCaller(recorder: recorder, bedroom: BedroomGalleryRecorder(store: store)))
        let media = UKMediaViewController(context: context)
        let window = HostedPage.show(UINavigationController(rootViewController: media), size: CGSize(width: 836 + 32, height: 1600))
        defer { window.isHidden = true }
        hostedSettle(0.5)
        let theater = try XCTUnwrap(FeatureHost.view("media.section.media-room", in: media.view), "the Media Room section")
        let living = try XCTUnwrap(FeatureHost.view("media.section.living-room", in: media.view))
        let grid = try XCTUnwrap(theater.superview)
        XCTAssertLessThan(living.frame.width, grid.bounds.width * 0.6, "the first sections sit two-up")
        XCTAssertEqual(theater.frame.width, grid.bounds.width, accuracy: 1, "the lone last section spans both columns")
    }
}
