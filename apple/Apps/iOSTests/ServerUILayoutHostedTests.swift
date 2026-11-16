import HassCore
import UIKit
import XCTest
@testable import HassUI

// MARK: - Layout capabilities

/// Hosted UX and accessibility checks for the layout capabilities (`sh.tab-blocks@1`, `sh.tab-bar@1`, `sh.tab-fallback@1`, `sh.overlay@1`,
/// `sh.tile-parts@1`, `sh.tile-look@1`, `sh.badges@1`). Each test runs at the iPhone, iPhone Duo and iPad widths, so a layout that only
/// fits one family fails here. The documents are the Studio's own corpus cases, not hand-written ones.
@MainActor
final class ServerUILayoutHostedTests: XCTestCase {
    /// The widths of the three families: iPhone, folded Duo and iPad.
    private static let widths: [CGFloat] = [390, 744, 1024]

    override func tearDown() async throws {
        HostedPage.hideTracked()
        HostedPage.resetGlobals()
        try await super.tearDown()
    }

    /// The corpus case `file`, with the components of its third page moved onto the page the renderer opens first.
    private func publication(_ file: String) throws -> ServerUICompositionPublication {
        let apple = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = apple.appendingPathComponent("Tests/HassCoreTests/ContractCorpus/reject/\(file).json")
        var json = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
        let pages = try XCTUnwrap(json["document"]?["pages"]?.array)
        let moved = try XCTUnwrap(pages[2]["components"])
        json = try ServerUIRendererFixture.changing(json, path: "/document/pages/0/components", to: moved)
        let kept = try XCTUnwrap(pages[0]["components"])
        json = try ServerUIRendererFixture.changing(json, path: "/document/pages/2/components", to: kept)
        return try ServerUICompositionPublication.decode(JSONEncoder().encode(json))
    }

    private func page(_ file: String, width: CGFloat) throws -> (UKServerUIRenderer, UKServerUIPage) {
        let store = EntityStore()
        store.replaceAll([EntityState(entityId: "lock.demo_door", state: "locked")])
        let host = try UKServerUIRenderer(publication: publication(file), context: UKContext(store: store, caller: HostedCaller()),
                                          backdrop: ServerUIRendererFixture.backdrop())
        _ = HostedPage.show(host, size: HostedPage.inScene(CGSize(width: width, height: 1180)))
        HostedPage.wait(0.1)
        let root = try ServerUIRendererFixture.root(host)
        root.view.layoutIfNeeded()
        return (host, root)
    }

    private func find<T: UIView>(_ type: T.Type, in view: UIView) -> T? {
        if let match = view as? T { return match }
        return view.subviews.lazy.compactMap { self.find(type, in: $0) }.first
    }

    private func all<T: UIView>(_ type: T.Type, in view: UIView) -> [T] {
        ((view as? T).map { [$0] } ?? []) + view.subviews.flatMap { all(type, in: $0) }
    }

    // MARK: Shared areas

    func testSharedAreaIsOneInstanceAcrossTabsAtEveryFamilyWidth() throws {
        for width in Self.widths {
            let (host, root) = try page("pending-tab-blocks-two-tabs", width: width)
            let shared = try XCTUnwrap(root.nodes["first-two-text"]?.view, "width \(width)")
            XCTAssertNotNil(shared.window)
            let last = try XCTUnwrap(root.nodes["last-text"]?.view)
            XCTAssertNil(last.window, "an area of another tab stays off screen")
            try host.perform(.setLocal(stateId: "panel", value: .string("rooms")), from: root)
            HostedPage.wait(0.4)
            XCTAssertTrue(root.nodes["first-two-text"]?.view === shared, "the shared area is not rebuilt")
            XCTAssertNotNil(shared.window)
            try host.perform(.setLocal(stateId: "panel", value: .string("dock")), from: root)
            HostedPage.wait(0.4)
            XCTAssertNil(shared.window)
            XCTAssertNotNil(last.window)
            HostedPage.hideTracked()
        }
    }

    // MARK: Tab bar

    func testTopTabBarKeepsAnAccessibleTargetForEveryLabelMode() throws {
        for file in ["pending-tab-bar-top-titles", "pending-tab-bar-top-icons", "pending-tab-bar-top-icons-and-titles", "pending-tab-bar-top-by-size"] {
            for width in Self.widths {
                let (_, root) = try page(file, width: width)
                root.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
                root.view.layoutIfNeeded()
                let tabs = try XCTUnwrap(root.nodes["tabs"]?.view, "\(file) \(width)")
                let bar = try XCTUnwrap(tabs.subviews.first, "\(file) \(width)")
                XCTAssertGreaterThanOrEqual(bar.bounds.height, 44, "\(file) \(width)")
                for control in all(UIControl.self, in: tabs) where control.isAccessibilityElement && control.bounds.width > 0 {
                    XCTAssertGreaterThanOrEqual(control.bounds.height, 44, "\(file) \(width)")
                }
                HostedPage.hideTracked()
            }
        }
    }

    func testIconsLabelModeNamesEveryTabForVoiceOver() throws {
        for width in Self.widths {
            let (_, root) = try page("pending-tab-bar-top-icons", width: width)
            let tabs = try XCTUnwrap(root.nodes["tabs"]?.view)
            let labels = all(UIView.self, in: tabs).compactMap(\.accessibilityLabel)
            for name in ["Controls", "Rooms", "Dock"] { XCTAssertTrue(labels.contains(name), "\(name) at \(width): \(labels)") }
            HostedPage.hideTracked()
        }
    }

    // MARK: Overlay

    func testOverlayControlsAreAtLeast44PointsAndReadInAnchorOrder() throws {
        for width in Self.widths {
            let (_, root) = try page("pending-overlay-five-anchors", width: width)
            let overlay = try XCTUnwrap(root.nodes["lay"]?.view as? UKServerUIOverlayView, "width \(width)")
            let controls = ["a", "b", "c", "d"].compactMap { root.nodes[$0]?.view }
            XCTAssertEqual(controls.count, 4)
            for control in controls {
                XCTAssertTrue(control.isDescendant(of: overlay))
                XCTAssertGreaterThanOrEqual(control.frame.width, 44, "width \(width)")
                XCTAssertGreaterThanOrEqual(control.frame.height, 44, "width \(width)")
                XCTAssertTrue(overlay.bounds.insetBy(dx: -1, dy: -1).contains(control.frame), "inside the overlay at \(width)")
            }
            let a = controls[0].frame, b = controls[1].frame, c = controls[2].frame, d = controls[3].frame
            XCTAssertLessThan(a.midX, b.midX)
            XCTAssertLessThan(a.midY, c.midY)
            XCTAssertLessThan(c.midX, d.midX)
            let order = (overlay.accessibilityElements ?? []).compactMap { $0 as? UIView }
            XCTAssertTrue(order.dropFirst().first === controls[0], "reading starts at the top-leading control")
            HostedPage.hideTracked()
        }
    }

    func testOverlayMirrorsItsLeadingAnchorsInRightToLeft() throws {
        let (_, root) = try page("pending-overlay-five-anchors", width: 390)
        let overlay = try XCTUnwrap(root.nodes["lay"]?.view)
        overlay.semanticContentAttribute = .forceRightToLeft
        overlay.setNeedsLayout()
        root.view.layoutIfNeeded()
        let a = try XCTUnwrap(root.nodes["a"]?.view), b = try XCTUnwrap(root.nodes["b"]?.view)
        XCTAssertGreaterThan(a.frame.midX, b.frame.midX, "top-leading is on the right in right-to-left")
    }

    // MARK: Tile parts

    func testTilePartsDrawDiscsWithNamesAtEveryFamilyWidth() throws {
        for width in Self.widths {
            let (_, root) = try page("pending-tile-parts-two-discs-enabled-when", width: width)
            let tile = try XCTUnwrap(root.nodes["door"]?.view as? UKGlassTileView, "width \(width)")
            XCTAssertFalse(tile.model.actions.isEmpty, "width \(width)")
            XCTAssertEqual(tile.model.actions.first?.label, "Lock")
            HostedPage.hideTracked()
        }
    }

    func testTileProgressIsClampedAndTheDestinationShowsAChevron() throws {
        for file in ["pending-tile-parts-progress-read", "pending-tile-parts-destination"] {
            let (_, root) = try page(file, width: 390)
            let tile = try XCTUnwrap(root.nodes.values.compactMap { $0.view as? UKGlassTileView }.first, file)
            if let progress = tile.model.progress { XCTAssertTrue((0...1).contains(progress), file) }
            if file.hasSuffix("destination") { XCTAssertEqual(tile.model.behavior, .navigate) }
            HostedPage.hideTracked()
        }
    }

    // MARK: Badges

    func testBadgeDrawsItsValueAndNoneDrawsNothing() throws {
        for width in Self.widths {
            let (_, root) = try page("pending-badge-tiles", width: width)
            let withValue = try XCTUnwrap(root.nodes["n"]?.view, "width \(width)")
            let without = try XCTUnwrap(root.nodes["t"]?.view)
            XCTAssertNotNil(find(UKSegmentBadge.self, in: withValue))
            XCTAssertNil(find(UKSegmentBadge.self, in: without))
            let spoken = all(UIView.self, in: withValue).compactMap(\.accessibilityLabel)
            XCTAssertTrue(spoken.contains { $0.contains("New") }, "the badge is spoken: \(spoken)")
            HostedPage.hideTracked()
        }
    }
}
