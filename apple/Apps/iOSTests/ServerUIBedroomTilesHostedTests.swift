@testable import HassCore
import HassDemoHouse
import HassDesign
import UIKit
import XCTest
@testable import HassUI

// MARK: - Bedroom tiles through the real control

/// Hosted checks for `pl-bedtile`: the bed and wake tiles an authored page places, drawn by the real ``UKServerUIBedroomControl`` inside
/// the server-driven page's two-column tile grid, at the width of each family (iPhone 390, folded Duo 466, unfolded Duo 868, iPad 744).
///
/// These fail when the tile loses the ``UKMeasuredView`` host that gives it a height in the control's stack: the tile is then 0 pt tall.
@MainActor
final class ServerUIBedroomTilesHostedTests: DemoHouseTestCase {
    private static let sizes = [CGSize(width: 390, height: 844), CGSize(width: 466, height: 678),
                                CGSize(width: 868, height: 678), CGSize(width: 744, height: 1133)]
    private static let ids = ["tile-left", "tile-right", "tile-wake"]

    override func tearDown() async throws {
        HostedPage.hideTracked()
        HostedPage.resetGlobals()
        try await super.tearDown()
    }

    // MARK: Fixture

    /// The synthetic page with three bedroom tiles (two beds, the wake light) in its tile grid, two columns wide.
    private func publication() throws -> ServerUICompositionPublication {
        var root = try ServerUIRendererFixture.json()
        let pageID = try XCTUnwrap(root["document"]?["pages"]?.array?.first?["id"]?.string)
        var sources = try XCTUnwrap(root["document"]?["dataSources"]?.array)
        for (id, provider, kind) in [("src-left", "synthetic-left", "bed-side"), ("src-right", "synthetic-right", "bed-side"),
                                     ("src-wake", "synthetic-wake", "wake-light")] {
            sources.append(.object(["id": .string(id), "kind": "model", "model": "bedroom-provider@1",
                                    "inputs": .object(["providerId": .string(provider), "kind": .string(kind)])]))
        }
        root = try ServerUIRendererFixture.changing(root, path: "/document/dataSources", to: .array(sources))
        func tile(_ id: String, source: String, control: String) -> JSONValue {
            .object(["id": .string(id), "type": "bedroom-control", "title": .string(id), "layout": .object(["span": .number(1)]),
                     "props": .object(["control": .string(control), "sourceId": .string(source), "label": .string(id),
                                       "unavailableText": "Unavailable",
                                       "action": .object(["type": "push", "pageId": .string(pageID), "arguments": .object([:]),
                                                          "origin": "sender", "duplicate": "reuse-nearest"])])])
        }
        root = try ServerUIRendererFixture.changing(root, path: "/document/pages/0/components/0/children", to: .array([
            tile("tile-left", source: "src-left", control: "bed-tile"), tile("tile-right", source: "src-right", control: "bed-tile"),
            tile("tile-wake", source: "src-wake", control: "wake-tile"),
        ]))
        root = try ServerUIRendererFixture.changing(root, path: "/document/pages/0/components/0/props/maxColumns", to: .number(2))
        let existing = try XCTUnwrap(root["capabilities"]?.array?.compactMap(\.string))
        root = try ServerUIRendererFixture.changing(root, path: "/capabilities", to: .array(
            Set(existing + ["sh.bedroom-sources@1", "sh.bed-tile@1", "sh.wake-tile@1"]).sorted().map(JSONValue.string)))
        return try ServerUIRendererFixture.publication(root)
    }

    private struct Rendered {
        let window: UIWindow
        let page: UKServerUIPage
        let controls: [UKServerUIBedroomControl]
        let store: EntityStore
    }

    private func render(_ size: CGSize) throws -> Rendered {
        let store = EntityStore()
        store.replaceAll(BedroomFixtures.states(.default), freshness: .live)
        let log = LoggingResponder(BedroomGalleryRecorder(store: store))
        let devices = BedroomDevices(store: store, caller: log)
        let host = try UKServerUIRenderer(publication: publication(), context: UKContext(store: store, caller: log),
                                          backdrop: ServerUIRendererFixture.backdrop(),
                                          bedroomProviders: ["synthetic-left": .bed(devices.bed(.left)), "synthetic-right": .bed(devices.bed(.right)),
                                                             "synthetic-wake": .wake(devices.wakeLight)])
        let window = HostedPage.show(host, size: HostedPage.inScene(size))
        HostedPage.wait(0.2)
        let page = try ServerUIRendererFixture.root(host)
        window.layoutIfNeeded()
        let controls = try Self.ids.map { id -> UKServerUIBedroomControl in
            let view = try XCTUnwrap(page.nodes[id]?.view, "\(id) is on the page")
            return try XCTUnwrap(([view] + HostedPage.descendants(of: view)).compactMap { $0 as? UKServerUIBedroomControl }.first,
                                 "\(id) is drawn by the real bedroom control")
        }
        return Rendered(window: window, page: page, controls: controls, store: store)
    }

    private func tile(in control: UKServerUIBedroomControl) throws -> UKBedroomTile {
        try XCTUnwrap(HostedPage.descendants(of: control).compactMap { $0 as? UKBedroomTile }.first, "the control holds its tile")
    }

    // MARK: UX

    /// UX: every tile the control draws has its tile's height, the glass fills it, no two tiles overlap, and the page scrolls past them.
    func testBedAndWakeTilesHaveHeightAndNothingOverlapsAtEveryFamilyWidth() throws {
        for size in Self.sizes {
            let rendered = try render(size)
            defer { rendered.window.isHidden = true }
            var frames: [CGRect] = []
            for control in rendered.controls {
                let tile = try tile(in: control)
                let glass = try XCTUnwrap(tile.subviews.first as? UKGlassTileView)
                let frame = control.convert(control.bounds, to: nil)
                XCTAssertGreaterThanOrEqual(tile.frame.height, 44, "\(size): the tile has height, not 0 pt: \(tile.frame)")
                XCTAssertGreaterThanOrEqual(frame.height, tile.frame.height - 0.5, "\(size): the control holds its tile")
                XCTAssertEqual(glass.frame.height, tile.frame.height, accuracy: 0.5, "\(size): the glass fills the tile")
                XCTAssertGreaterThan(tile.frame.width, 100, "\(size): the tile has width: \(tile.frame)")
                frames.append(frame)
            }
            for (index, frame) in frames.enumerated() {
                for other in frames[(index + 1)...] {
                    XCTAssertTrue(frame.insetBy(dx: 1, dy: 1).intersection(other.insetBy(dx: 1, dy: 1)).isNull, "\(size): tiles do not overlap: \(frame) \(other)")
                }
            }
            let scroll = try XCTUnwrap(HostedPage.descendants(of: rendered.page.view).compactMap { $0 as? UKPageScrollView }.first)
            let bottom = rendered.controls.map { scroll.convert($0.bounds, from: $0).maxY }.max() ?? 0
            XCTAssertGreaterThanOrEqual(scroll.contentSize.height, bottom - 1, "\(size): the page holds every tile")
        }
    }

    /// UX: the grid places the two bed tiles side by side only when one track holds their minimum, else it stacks them at the section width. Either way each is the width
    /// of its track and shows the tile's own minimum.
    func testBedTilesShareARowOnlyWhenTheGridHasRoom() throws {
        for size in Self.sizes {
            let rendered = try render(size)
            defer { rendered.window.isHidden = true }
            let left = rendered.controls[0].convert(rendered.controls[0].bounds, to: nil)
            let right = rendered.controls[1].convert(rendered.controls[1].bounds, to: nil)
            let minimum = try tile(in: rendered.controls[0]).gridMinimumWidth
            let sideBySide = abs(left.minY - right.minY) < 1
            XCTAssertGreaterThan(minimum, 0, "\(size): the bed tile declares the width its text needs")
            let grid = try XCTUnwrap(rendered.controls[0].superview?.superview, "the control sits in the page's grid")
            let oneTrack = (grid.bounds.width - HassTokens.Spacing.m) / 2
            if oneTrack < minimum {
                // The minimum (the longest line a bed can show) is wider than one track here, so each tile takes the full section.
                XCTAssertFalse(sideBySide, "\(size): the bed tiles stack (one track \(oneTrack), minimum \(minimum))")
                XCTAssertEqual(left.width, grid.bounds.width, accuracy: 1, "\(size): each bed tile spans the section: \(left)")
                XCTAssertEqual(right.width, left.width, accuracy: 1, "\(size): both bed tiles are as wide")
            } else {
                XCTAssertTrue(sideBySide, "\(size): one track holds the minimum, so the tiles share a row (one track \(oneTrack), minimum \(minimum))")
            }
            if sideBySide {
                XCTAssertGreaterThanOrEqual(left.width, minimum - 0.5, "\(size): each track holds the tile's minimum")
            } else {
                XCTAssertEqual(left.minX, right.minX, accuracy: 1, "\(size): stacked tiles share a left edge")
            }
        }
    }

    /// UX: the control reports the minimum width of its tile (the grid reads it to choose the tracks), as a tile placed directly does.
    func testControlForwardsItsTilesMinimumWidth() throws {
        let rendered = try render(Self.sizes[0])
        defer { rendered.window.isHidden = true }
        for control in rendered.controls {
            let tile = try tile(in: control)
            XCTAssertEqual(control.gridMinimumWidth, tile.gridMinimumWidth, "the control wraps its tile's minimum")
        }
        for control in rendered.controls.prefix(2) {
            XCTAssertGreaterThan(control.gridMinimumWidth, 0, "a bed tile reports a minimum: 0 would keep it one track")
        }
        XCTAssertEqual(rendered.controls[2].gridMinimumWidth, 0, "the wake tile is left as it was")
    }

    /// UX: a live change (Hot Flash Mode on) leaves the bed tile's minimum alone, so a state change never re-spans the grid.
    func testALiveStateChangeDoesNotChangeTheBedMinimum() throws {
        for size in [Self.sizes[0], Self.sizes[3]] {
            let rendered = try render(size)
            defer { rendered.window.isHidden = true }
            let before = rendered.controls.prefix(2).map(\.gridMinimumWidth)
            let frames = rendered.controls.prefix(2).map { $0.convert($0.bounds, to: nil) }
            rendered.store.replaceAll(BedroomFixtures.states(.hotFlash), freshness: .live)
            HostedPage.wait(0.3)
            rendered.window.layoutIfNeeded()
            XCTAssertEqual(rendered.controls.prefix(2).map(\.gridMinimumWidth), before, "\(size): the minimum does not follow the text")
            XCTAssertEqual(rendered.controls.prefix(2).map { $0.convert($0.bounds, to: nil).width }, frames.map(\.width),
                           "\(size): the tiles keep their widths")
        }
    }

    // MARK: Accessibility

    /// Accessibility: each tile is in the tree as a named button at least 44 pt tall, drawn and not a zero-height frame.
    func testTilesAreNamedButtonsAtLeast44PointTallAtEveryFamilyWidth() throws {
        for size in Self.sizes {
            let rendered = try render(size)
            defer { rendered.window.isHidden = true }
            for control in rendered.controls {
                let glass = try XCTUnwrap(tile(in: control).subviews.first as? UKGlassTileView)
                // A tile with a subtitle is a container whose first element is the body; one without is the element itself.
                let elements: [Any] = glass.isAccessibilityElement ? [glass] : (glass.accessibilityElements ?? [])
                let body = try XCTUnwrap(elements.first as? NSObject, "\(size): the tile reaches VoiceOver")
                let label = try XCTUnwrap(body.accessibilityLabel, "\(size): the tile is named")
                XCTAssertTrue(label.contains(glass.model.title), "\(size): the title is in the label: \(label)")
                XCTAssertTrue(body.accessibilityTraits.contains(.button), "\(size): \(label) is a button")
                XCTAssertGreaterThanOrEqual(glass.convert(glass.bounds, to: nil).height, 44, "\(size): \(label) is drawn")
            }
        }
    }

    // MARK: Scroll cost

    /// UX: scrolling the page lays it out on every frame and measures no bedroom control again.
    func testScrollingMeasuresNoBedroomControlAgain() throws {
        let rendered = try render(Self.sizes[0])
        defer { rendered.window.isHidden = true }
        let scroll = try XCTUnwrap(HostedPage.descendants(of: rendered.page.view).compactMap { $0 as? UKPageScrollView }.first)
        let before = rendered.controls.map(\.fitCache.fits)
        for frame in 1...40 {
            scroll.contentOffset = CGPoint(x: 0, y: CGFloat(frame))
            scroll.setNeedsLayout()
            scroll.layoutIfNeeded()
        }
        XCTAssertEqual(rendered.controls.map(\.fitCache.fits), before, "no control was measured by a scroll")
    }
}
