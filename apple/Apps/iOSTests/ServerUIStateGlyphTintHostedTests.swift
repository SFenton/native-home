import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

// MARK: - Icon colour by state

/// Hosted UX and accessibility checks for `sh.state-style-glyph-tint@1`: a state style rule's `glyphTint`, drawn by the generic state tile on
/// its dark face. Each check runs at the iPhone, iPhone Duo and iPad widths (clamped to the scene they run in, as the other hosted layout
/// tests do), from the shared corpus documents `accept/state-style-glyph-tint-*.json`.
@MainActor
final class ServerUIStateGlyphTintHostedTests: XCTestCase {
    private static let widths: [CGFloat] = [393, 466, 834]
    private static let warm: UInt32 = 0xF2A65A
    private static let warmLight: UInt32 = 0xB5651D
    private static let cool: UInt32 = 0x78B4F0
    private static let tileID = "demo-tile"
    private static let entity = "vacuum.demo_robot"

    private var window: UIWindow?
    private var scheduler = HandScheduler()

    override func setUp() async throws {
        try await super.setUp()
        scheduler = HandScheduler()
        UKStateTileTransition.schedulerOverride = scheduler
    }

    override func tearDown() async throws {
        HostedPage.hideTracked()
        HostedPage.resetGlobals()
        window = nil
        try await super.tearDown()
    }

    // MARK: Fixtures

    private func publication(_ name: String) throws -> ServerUICompositionPublication {
        let apple = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        var json = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf:
            apple.appendingPathComponent("Tests/HassCoreTests/ContractCorpus/accept/state-style-glyph-tint-\(name).json")))
        let pages = try XCTUnwrap(json["document"]?["pages"]?.array)
        json = try ServerUIRendererFixture.changing(json, path: "/document/pages/0/components", to: XCTUnwrap(pages[2]["components"]))
        json = try ServerUIRendererFixture.changing(json, path: "/document/pages/2/components", to: XCTUnwrap(pages[0]["components"]))
        return try ServerUIRendererFixture.publication(json)
    }

    private func page(_ name: String, width: CGFloat, state: String, capability: Bool = true)
        async throws -> (UKServerUIPage, UKGlassTileView, EntityStore) {
        let store = EntityStore()
        store.replaceAll([EntityState(entityId: Self.entity, state: state)])
        let host = try UKServerUIRenderer(publication: publication(name), context: UKContext(store: store, caller: HostedCaller()),
                                          backdrop: ServerUIRendererFixture.backdrop())
        host.stateStylesEnabled = capability
        window = HostedPage.show(host, size: HostedPage.inScene(CGSize(width: width, height: 852)))
        let root = try ServerUIRendererFixture.root(host)
        await HostedPage.settle { root.nodes[Self.tileID]?.view is UKGlassTileView }
        let tile = try XCTUnwrap(root.nodes[Self.tileID]?.view as? UKGlassTileView)
        root.view.layoutIfNeeded()
        return (root, tile, store)
    }

    private func setStyle(_ style: UIUserInterfaceStyle, _ root: UKServerUIPage) {
        window?.overrideUserInterfaceStyle = style
        root.view.overrideUserInterfaceStyle = style
        HostedPage.wait(0.15)
        root.view.layoutIfNeeded()
    }

    /// Flips the entity and fires the hand scheduler until the tile's text and colour have settled, as the state style tests do.
    private func flip(_ store: EntityStore, to state: String, _ tile: UKGlassTileView, until condition: @escaping @MainActor () -> Bool) async {
        store.apply([EntityState(entityId: Self.entity, state: state)])
        let landed = await HostedPage.settle {
            self.scheduler.fire()
            return condition()
        }
        XCTAssertTrue(landed, "the tile settled on \(state)")
    }

    private func packed(_ color: UIColor, in view: UIView) -> UInt32 {
        let resolved = color.resolvedColor(with: view.traitCollection)
        var (red, green, blue, alpha) = (CGFloat(0), CGFloat(0), CGFloat(0), CGFloat(0))
        XCTAssertTrue(resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        return UInt32((red * 255).rounded()) << 16 | UInt32((green * 255).rounded()) << 8 | UInt32((blue * 255).rounded())
    }

    // MARK: UX

    func testTheRuleColourDrawsOnTheDarkFaceAtEveryWidthFromTheFirstRender() async throws {
        for width in Self.widths {
            let (root, tile, _) = try await page("per-state", width: width, state: "docked")
            setStyle(.dark, root)
            XCTAssertEqual(packed(tile.face.drawnGlyphColor, in: tile), Self.warm, "docked icon, width \(width)")
            XCTAssertEqual(tile.face.drawnGlyphAlpha, 1, accuracy: 0.001)
            XCTAssertEqual(tile.model.glyphTint, AppearanceFill(Self.warm))
            HostedPage.hideTracked()
        }
    }

    func testATintOnlyFlipFadesTheColourAndRelaysNothingAtEveryWidth() async throws {
        for width in Self.widths {
            let (root, tile, store) = try await page("per-state", width: width, state: "docked")
            setStyle(.dark, root)
            let view = root.nodes[Self.tileID]?.view
            let frame = tile.frame, height = tile.gridHeight(forWidth: tile.bounds.width)
            let words = HostedPage.labels(in: tile)
            XCTAssertEqual(packed(tile.face.drawnGlyphColor, in: tile), Self.warm)
            await flip(store, to: "paused", tile) { self.packed(tile.face.drawnGlyphColor, in: tile) == Self.cool }
            XCTAssertEqual(packed(tile.face.drawnGlyphColor, in: tile), Self.cool, "paused takes its own colour (width \(width))")
            XCTAssertTrue(root.nodes[Self.tileID]?.view === view, "the tile was not rebuilt")
            XCTAssertEqual(tile.frame, frame, "the tile did not move or resize")
            XCTAssertEqual(tile.gridHeight(forWidth: tile.bounds.width), height, accuracy: 0.001, "its measured height is unchanged")
            XCTAssertEqual(HostedPage.labels(in: tile), words, "no word changed: the flip is the colour alone")
            HostedPage.hideTracked()
        }
    }

    func testAnEqualTintOnAStateChangeIsUntouched() async throws {
        let (root, tile, store) = try await page("per-state", width: 393, state: "docked")
        setStyle(.dark, root)
        let configures = tile.configureCount
        store.apply([EntityState(entityId: Self.entity, state: "idle")])
        HostedPage.wait(0.2)
        scheduler.fire()
        XCTAssertEqual(packed(tile.face.drawnGlyphColor, in: tile), Self.warm)
        XCTAssertEqual(tile.model.glyphTint, AppearanceFill(Self.warm))
        XCTAssertLessThanOrEqual(tile.configureCount - configures, 1, "an equal tint costs at most the one box update")
    }

    func testAPairFollowsTheAppearanceAtEveryWidth() async throws {
        for width in Self.widths {
            let (root, tile, _) = try await page("pair", width: width, state: "docked")
            XCTAssertEqual(tile.model.glyphTint, AppearanceFill(light: Self.warmLight, dark: Self.warm))
            for (style, expected) in [(UIUserInterfaceStyle.light, Self.warmLight), (.dark, Self.warm)] {
                setStyle(style, root)
                XCTAssertEqual(packed(tile.face.drawnGlyphColor, in: tile), expected, "\(style.rawValue), width \(width)")
            }
            HostedPage.hideTracked()
        }
    }

    func testAnUnavailableStateStaysGreyAtEveryWidth() async throws {
        for width in Self.widths {
            let (root, tile, store) = try await page("per-state", width: width, state: "docked")
            setStyle(.dark, root)
            await flip(store, to: "unavailable", tile) { tile.model.isUnavailable }
            setStyle(.dark, root)
            let grey = packed(tile.face.drawnGlyphColor, in: tile)
            XCTAssertNotEqual(grey, Self.warm, "the rule colour is not drawn while unavailable (width \(width))")
            XCTAssertNotEqual(grey, Self.cool)
            XCTAssertEqual(tile.face.drawnGlyphAlpha, 0.5, accuracy: 0.001, "the muted grey at half opacity")
            HostedPage.hideTracked()
        }
    }

    func testTheTilesStaticTintStandsWhereTheRuleHasNoneAtEveryWidth() async throws {
        for width in Self.widths {
            let (_, tile, store) = try await page("with-static-tint", width: width, state: "docked")
            XCTAssertEqual(tile.model.glyphTint, AppearanceFill(Self.warm), "the rule wins in its state (width \(width))")
            await flip(store, to: "cleaning", tile) { tile.model.glyphTint == AppearanceFill(Self.cool) }
            XCTAssertEqual(tile.model.glyphTint, AppearanceFill(Self.cool), "a rule with none leaves the tile's own tint")
            HostedPage.hideTracked()
        }
    }

    func testAStyleWithNoColourDrawsAsItAlwaysDidAtEveryWidth() async throws {
        for width in Self.widths {
            let (_, tile, _) = try await page("absent-needs-no-capability", width: width, state: "docked")
            XCTAssertNil(tile.model.glyphTint, "no tint reached the model (width \(width))")
            HostedPage.hideTracked()
        }
    }

    func testABuildWithoutStateStylesDrawsNoRuleColour() async throws {
        let (_, tile, _) = try await page("per-state", width: 393, state: "docked", capability: false)
        // This toggles `sh.state-style@1` (the style library), not the tint id: a build without `sh.state-style-glyph-tint@1` cannot be hosted, because
        // the compiler refuses a publication naming an id outside `supportedCapabilities` (corpus: `state-style-glyph-tint-missing-capability`).
        XCTAssertNil(tile.model.glyphTint, "without state styles the built-in style draws: no rule colour")
    }

    // MARK: Accessibility

    func testTheColourChangesNothingVoiceOverReadsAtEveryWidth() async throws {
        for width in Self.widths {
            let (_, tile, store) = try await page("per-state", width: width, state: "docked")
            let label = tile.accessibilityLabel, value = tile.accessibilityValue
            let hint = tile.accessibilityHint, traits = tile.accessibilityTraits
            await flip(store, to: "paused", tile) { tile.model.glyphTint == AppearanceFill(Self.cool) }
            XCTAssertEqual(tile.accessibilityLabel, label, "width \(width)")
            XCTAssertEqual(tile.accessibilityValue, value, "the state text is the signal, never the colour")
            XCTAssertEqual(tile.accessibilityHint, hint)
            XCTAssertEqual(tile.accessibilityTraits, traits)
            XCTAssertTrue(tile.isAccessibilityElement || tile.accessibilityElements?.isEmpty == false)
            for image in HostedPage.descendants(of: tile).compactMap({ $0 as? UIImageView }) { XCTAssertFalse(image.isAccessibilityElement) }
            HostedPage.hideTracked()
        }
    }
}
