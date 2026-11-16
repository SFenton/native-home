import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

// MARK: - A state tile's ink and cell fit

/// Hosted UX and accessibility checks for `sh.tile-ink@1`: the icon colour (`glyphTint`), the button icon colour (`discGlyphTint`), the fit
/// in a taller cell (`cellFit`) and the ink of the state line on a style fill (`fillInk`), each drawn by the generic state tile.
///
/// Every field reproduces what the old atom drew (the family `.cleaning` tile of `UKServerUIVacuumView` at 2678f1d1): the off glyph
/// (`TileFaceInk.swift:38-44`), the dark disc's glyph (`TileActionInk.swift:28-33`), the family fill's 92% ink (`ColorFamily.swift:195`) and the
/// card that kept its own height in an equal-height row. The tests run at the iPhone, iPhone Duo and iPad widths (clamped to the scene they
/// run in, as the other hosted layout tests do), and a tile with none of the fields draws what it always drew.
@MainActor
final class ServerUITileInkHostedTests: XCTestCase {
    /// The widths of the three families: iPhone, folded Duo and iPad.
    private static let widths: [CGFloat] = [393, 466, 834]
    private static let glyphLight: UInt32 = 0x8E6DAC
    private static let glyphDark: UInt32 = 0xC18CEE
    private static let discDark: UInt32 = 0xB88DDD
    private static let tileID = "tile"

    private var window: UIWindow?

    override func tearDown() async throws {
        HostedPage.hideTracked()
        HostedPage.resetGlobals()
        window = nil
        try await super.tearDown()
    }

    // MARK: Fixtures

    /// A corpus `accept/tile-ink-<name>.json` with the tile page swapped onto the root page, as the state style tests do.
    private func publication(_ name: String) throws -> ServerUICompositionPublication {
        let apple = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        var json = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf:
            apple.appendingPathComponent("Tests/HassCoreTests/ContractCorpus/accept/tile-ink-\(name).json")))
        let pages = try XCTUnwrap(json["document"]?["pages"]?.array)
        json = try ServerUIRendererFixture.changing(json, path: "/document/pages/0/components", to: XCTUnwrap(pages[2]["components"]))
        json = try ServerUIRendererFixture.changing(json, path: "/document/pages/2/components", to: XCTUnwrap(pages[0]["components"]))
        return try ServerUIRendererFixture.publication(json)
    }

    private func page(_ name: String, width: CGFloat, state: String, tile id: String = "tile")
        async throws -> (UKServerUIPage, UKGlassTileView, EntityStore) {
        let store = EntityStore()
        store.replaceAll([EntityState(entityId: "vacuum.demo_robot", state: state)])
        let host = try UKServerUIRenderer(publication: publication(name), context: UKContext(store: store, caller: HostedCaller()),
                                          backdrop: ServerUIRendererFixture.backdrop())
        host.stateStylesEnabled = true
        window = HostedPage.show(host, size: HostedPage.inScene(CGSize(width: width, height: 852)))
        let root = try ServerUIRendererFixture.root(host)
        await HostedPage.settle { root.nodes[id]?.view is UKGlassTileView }
        let tile = try XCTUnwrap(root.nodes[id]?.view as? UKGlassTileView)
        root.view.layoutIfNeeded()
        return (root, tile, store)
    }

    /// Draws the page in `style`. The page pins its own appearance (pages stay dark), so the override goes on the page's view too.
    private func setStyle(_ style: UIUserInterfaceStyle, _ root: UKServerUIPage) {
        window?.overrideUserInterfaceStyle = style
        root.view.overrideUserInterfaceStyle = style
        HostedPage.wait(0.15)
        root.view.layoutIfNeeded()
    }

    /// A tile for `model` on its own, in a window `width` wide.
    private func tile(_ model: UKGlassTileModel, width: CGFloat = 170) -> UKGlassTileView {
        let tile = UKGlassTileView(model: model, environment: UKTileEnvironment())
        let host = UIViewController()
        host.view.addSubview(tile)
        window = HostedPage.show(host, size: HostedPage.inScene(CGSize(width: max(width + 40, 240), height: 400)))
        tile.frame = CGRect(x: 0, y: 0, width: width, height: tile.gridHeight(forWidth: width))
        HostedPage.wait(0.1)
        tile.layoutIfNeeded()
        return tile
    }

    private func model(_ title: String = "Robot", symbol: String = "fan", isActive: Bool = false, isUnavailable: Bool = false,
                       isError: Bool = false, family: ColorFamily? = .neutral, fill: UInt32? = nil, actions: [TileActionItem] = [],
                       glyphTint: AppearanceFill? = nil, discGlyphTint: AppearanceFill? = nil, soft: Bool = false) -> UKGlassTileModel {
        var model = actions.isEmpty
            ? UKGlassTileModel(title: title, subtitle: "Docked", symbol: symbol, family: family, fillRGB: fill, isActive: isActive,
                               isUnavailable: isUnavailable, isError: isError, kind: .state, identifier: Self.tileID)
            : UKGlassTileModel(title: title, subtitle: "Docked", symbol: symbol, family: family, fillRGB: fill, isActive: isActive,
                               isUnavailable: isUnavailable, isError: isError, behavior: .perform(actions[0].id), actions: actions,
                               identifier: Self.tileID)
        model.glyphTint = glyphTint
        model.discGlyphTint = discGlyphTint
        model.softFillInk = soft
        return model
    }

    private static let pause = TileActionItem(id: "pause", verb: "Pause", symbol: "pause.fill")
    private static let pair = AppearanceFill(light: glyphLight, dark: glyphDark)
    private static let discPair = AppearanceFill(light: glyphLight, dark: discDark)

    private func discs(in view: UIView) -> [UKTileActionDisc] { HostedPage.descendants(of: view).compactMap { $0 as? UKTileActionDisc } }

    /// The channels of `color` as `view` sees it, as 0...255 and an opacity.
    private func channels(_ color: UIColor, in view: UIView) -> (red: Int, green: Int, blue: Int, alpha: Double) {
        let resolved = color.resolvedColor(with: view.traitCollection)
        var (red, green, blue, alpha) = (CGFloat(0), CGFloat(0), CGFloat(0), CGFloat(0))
        XCTAssertTrue(resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        return (Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()), Double(alpha))
    }

    private func packed(_ color: UIColor, in view: UIView) -> UInt32 {
        let value = channels(color, in: view)
        return UInt32(value.red) << 16 | UInt32(value.green) << 8 | UInt32(value.blue)
    }

    // MARK: UX: icon colour

    func testTheIconColourFollowsTheAppearanceOnAPlainFaceAtEveryWidth() async throws {
        for width in Self.widths {
            let (root, tile, _) = try await page("glyph-tint-pair", width: width, state: "docked")
            XCTAssertEqual(tile.model.glyphTint, Self.pair, "the document's pair reached the model (width \(width))")
            for (style, expected) in [(UIUserInterfaceStyle.light, Self.glyphLight), (.dark, Self.glyphDark)] {
                setStyle(style, root)
                XCTAssertEqual(packed(tile.face.drawnGlyphColor, in: tile), expected, "docked icon, \(style.rawValue), width \(width)")
                XCTAssertEqual(tile.face.drawnGlyphAlpha, 1, accuracy: 0.001)
            }
            HostedPage.hideTracked()
        }
    }

    func testASingleColourIsTheSameInBothAppearances() async throws {
        let (root, tile, _) = try await page("glyph-tint", width: 393, state: "idle")
        for style in [UIUserInterfaceStyle.light, .dark] {
            setStyle(style, root)
            XCTAssertEqual(packed(tile.face.drawnGlyphColor, in: tile), Self.glyphLight, style.rawValue)
        }
    }

    func testAnUnavailableTileDrawsTheIconColourAtHalfOpacityAsItDrawsTheGrey() async throws {
        for width in Self.widths {
            let (root, tile, store) = try await page("glyph-tint-pair", width: width, state: "docked")
            store.apply([EntityState(entityId: "vacuum.demo_robot", state: "unavailable")])
            await HostedPage.settle { tile.model.isUnavailable }
            setStyle(.dark, root)
            XCTAssertTrue(tile.model.isUnavailable)
            XCTAssertEqual(packed(tile.face.drawnGlyphColor, in: tile), Self.glyphDark, "still the authored colour (width \(width))")
            XCTAssertEqual(tile.face.drawnGlyphAlpha, 0.5, accuracy: 0.001, "dimmed to 50%, as the grey icon is")
            HostedPage.hideTracked()
        }
    }

    func testTheIconColourFollowsTheLiveStateWithNoReload() async throws {
        let (root, tile, store) = try await page("glyph-tint-pair", width: 393, state: "docked")
        setStyle(.dark, root)
        let before = root.nodes[Self.tileID]?.view
        store.apply([EntityState(entityId: "vacuum.demo_robot", state: "idle")])
        HostedPage.wait(0.2)
        XCTAssertEqual(packed(tile.face.drawnGlyphColor, in: tile), Self.glyphDark)
        XCTAssertTrue(root.nodes[Self.tileID]?.view === before, "the tile was not rebuilt")
    }

    func testAFilledFaceAnErrorFaceAndTheLitFaceKeepTheirOwnIcon() throws {
        let pair = Self.pair
        let filled = tile(model(isActive: false, fill: 0x785AA0, glyphTint: pair))
        XCTAssertEqual(packed(filled.face.drawnGlyphColor, in: filled), 0xFFFFFF, "a style fill keeps the white icon")
        let lit = tile(model(isActive: true, family: .lights, glyphTint: pair))
        XCTAssertNotEqual(packed(lit.face.drawnGlyphColor, in: lit), Self.glyphDark, "the lit face keeps its own ink")
        let plain = tile(model(isActive: true, family: .lights))
        XCTAssertEqual(lit.face.drawnGlyphColor.resolvedColor(with: lit.traitCollection), plain.face.drawnGlyphColor.resolvedColor(with: plain.traitCollection))
        let error = tile(model(isError: true, glyphTint: pair))
        let bare = tile(model(isError: true))
        XCTAssertEqual(error.face.drawnGlyphColor.resolvedColor(with: error.traitCollection), bare.face.drawnGlyphColor.resolvedColor(with: bare.traitCollection),
                       "an error face keeps its red icon")
    }

    // MARK: UX: button icon colour

    func testTheButtonIconColourDrawsOnAnOffDiscOnADarkFaceAtEveryWidth() async throws {
        for width in Self.widths {
            let (root, tile, _) = try await page("both-tints", width: width, state: "docked")
            let disc = try XCTUnwrap(discs(in: tile).first, "the authored Pause button (width \(width))")
            for (style, expected) in [(UIUserInterfaceStyle.light, Self.glyphLight), (.dark, Self.discDark)] {
                setStyle(style, root)
                XCTAssertEqual(packed(disc.drawnGlyphColor, in: disc), expected, "button icon, \(style.rawValue), width \(width)")
            }
            HostedPage.hideTracked()
        }
    }

    func testAFilledFaceKeepsTheBlackDiscAndTheWhiteGlyphWhateverTheTint() throws {
        let filled = tile(model(fill: 0x785AA0, actions: [Self.pause], discGlyphTint: Self.discPair), width: 260)
        let disc = try XCTUnwrap(discs(in: filled).first)
        XCTAssertEqual(packed(disc.drawnGlyphColor, in: disc), 0xFFFFFF)
        let ground = channels(try XCTUnwrap(disc.backgroundColor), in: disc)
        XCTAssertEqual(ground.red + ground.green + ground.blue, 0)
        XCTAssertEqual(ground.alpha, TileActionInk.filledDiscOpacity, accuracy: 0.01, "black at 18%")
    }

    func testAnErrorFaceStillTakesTheButtonIconColour() throws {
        let error = tile(model(isError: true, actions: [Self.pause], discGlyphTint: Self.discPair), width: 260)
        let disc = try XCTUnwrap(discs(in: error).first)
        XCTAssertEqual(packed(disc.drawnGlyphColor, in: disc), Self.discDark)
    }

    func testAnUnavailableButtonKeepsItsTintAtHalfOpacity() throws {
        let item = TileActionItem(id: "pause", verb: "Pause", symbol: "pause.fill", phase: .unavailable)
        let unavailable = tile(model(isUnavailable: true, actions: [item], discGlyphTint: Self.discPair), width: 260)
        let disc = try XCTUnwrap(discs(in: unavailable).first)
        XCTAssertEqual(packed(disc.drawnGlyphColor, in: disc), Self.discDark)
        XCTAssertFalse(disc.isEnabled)
    }

    // MARK: UX: ink on a fill

    func testTheSoftInkIsWhiteAtNinetyTwoPercentOnAFillAndTheDefaultIsWhiteAtEveryWidth() async throws {
        for width in Self.widths {
            let (_, soft, _) = try await page("fill-ink-soft", width: width, state: "docked")
            let line = channels(soft.face.drawnStateLineColor, in: soft)
            XCTAssertEqual([line.red, line.green, line.blue], [255, 255, 255], "width \(width)")
            XCTAssertEqual(line.alpha, 0.92, accuracy: 0.005, "soft is white at 92% (width \(width))")
            HostedPage.hideTracked()
            let (_, white, _) = try await page("fill-ink-white", width: width, state: "docked")
            XCTAssertEqual(channels(white.face.drawnStateLineColor, in: white).alpha, 1, accuracy: 0.001, "white is 100% (width \(width))")
            HostedPage.hideTracked()
        }
    }

    func testTheSoftInkChangesTheStateLineOnlyAndOnlyWhileTheStateHasItsFill() async throws {
        let (_, tile, store) = try await page("fill-ink-soft", width: 393, state: "docked")
        let title = try XCTUnwrap(HostedPage.descendants(of: tile).compactMap { $0 as? UILabel }.first { $0.text == "Robot" || $0.text == "tile" })
        XCTAssertEqual(channels(title.textColor, in: tile).alpha, 1, accuracy: 0.001, "the title stays white at 100%")
        store.apply([EntityState(entityId: "vacuum.demo_robot", state: "cleaning")])
        HostedPage.wait(0.3)
        XCTAssertNotEqual(channels(tile.face.drawnStateLineColor, in: tile).alpha, 0.92, accuracy: 0.001, "a state with no fill has no soft ink")
    }

    func testAFillWithNoInkDrawsWhiteAtFullOpacity() throws {
        let plain = tile(model(fill: 0x785AA0))
        XCTAssertEqual(channels(plain.face.drawnStateLineColor, in: plain).alpha, 1, accuracy: 0.001)
        let soft = tile(model(fill: 0x785AA0, soft: true))
        XCTAssertEqual(channels(soft.face.drawnStateLineColor, in: soft).alpha, 0.92, accuracy: 0.005)
        let off = tile(model(soft: true))
        let reference = tile(model())
        XCTAssertEqual(off.face.drawnStateLineColor.resolvedColor(with: off.traitCollection),
                       reference.face.drawnStateLineColor.resolvedColor(with: reference.traitCollection), "soft ink is for a fill only")
    }

    // MARK: UX: cell fit

    /// A two-column grid of equal rows: tile A is short, tile B is taller (a long title and state line wrap).
    private func grid(width: CGFloat, natural: Bool) -> (UKDynamicGridView, UKGlassTileView, UKGlassTileView) {
        var short = model("A", isActive: false)
        short.keepsNaturalHeight = natural
        var tall = model("Upstairs hallway ceiling light group and the stair lamps", isActive: false)
        tall.subtitle = "Warming up to the evening scene at forty percent"
        let (a, b) = (UKGlassTileView(model: short, environment: UKTileEnvironment()), UKGlassTileView(model: tall, environment: UKTileEnvironment()))
        let grid = UKDynamicGridView(configuration: UKGridConfiguration(minCellWidth: 150, maxColumns: 2, equalRowHeights: true))
        grid.setItems([UKGridItem(a), UKGridItem(b)])
        let host = UIViewController()
        host.view.addSubview(grid)
        window = HostedPage.show(host, size: HostedPage.inScene(CGSize(width: width, height: 700)))
        grid.frame = CGRect(x: 0, y: 0, width: width, height: grid.sizeThatFits(CGSize(width: width, height: 0)).height)
        HostedPage.wait(0.1)
        grid.layoutIfNeeded()
        return (grid, a, b)
    }

    func testANaturalTileKeepsItsOwnHeightAtTheTopOfATallerCellAtEveryWidth() {
        for width in Self.widths {
            let (_, a, b) = grid(width: min(width, 420), natural: true)
            let own = a.gridHeight(forWidth: a.frame.width)
            XCTAssertGreaterThan(b.frame.height, own + 1, "the row is as tall as its tallest cell (width \(width))")
            XCTAssertEqual(a.frame.height, own, accuracy: 0.5, "the natural tile keeps its own height (width \(width))")
            XCTAssertEqual(a.frame.minY, b.frame.minY, accuracy: 0.5, "top-aligned")
            XCTAssertTrue(a.keepsNaturalHeight && !b.keepsNaturalHeight)
            HostedPage.hideTracked()
        }
    }

    func testAFillTileStretchesToItsCellAsItAlwaysDid() {
        for width in Self.widths {
            let (_, a, b) = grid(width: min(width, 420), natural: false)
            XCTAssertEqual(a.frame.height, b.frame.height, accuracy: 0.5, "equal row heights (width \(width))")
            XCTAssertFalse(a.keepsNaturalHeight)
            HostedPage.hideTracked()
        }
    }

    func testTheDocumentsCellFitReachesTheTile() async throws {
        let (_, natural, _) = try await page("cell-fit-natural", width: 393, state: "docked", tile: "a")
        XCTAssertTrue(natural.keepsNaturalHeight)
        let fill = try XCTUnwrap(window?.rootViewController.flatMap { HostedPage.descendants(of: $0.view) }.compactMap { $0 as? UKGlassTileView }
            .first { $0.model.identifier == "b" })
        XCTAssertFalse(fill.keepsNaturalHeight, "cellFit fill is the default")
    }

    // MARK: Defaults

    /// A default state tile (no ink field anywhere) draws the grey icon, the white 16% disc with its glyph and the height it always had.
    func testADefaultStateTileDrawsWhatItAlwaysDrew() throws {
        let plain = tile(model(actions: [Self.pause]), width: 260)
        let disc = try XCTUnwrap(discs(in: plain).first)
        let expectedGlyph = TileFaceInk.glyphToken(style: .off, appearance: .dark, finish: .solid, isEnabled: true, family: .neutral, tintGlyph: .white)
        XCTAssertEqual(plain.face.drawnGlyphColor.resolvedColor(with: plain.traitCollection),
                       UIColor(expectedGlyph).resolvedColor(with: plain.traitCollection), "the icon is the neutral off glyph")
        XCTAssertNotEqual(packed(plain.face.drawnGlyphColor, in: plain), Self.glyphDark)
        let ink = TileActionInk.resolveTokens(face: .dark, isOn: false, family: .neutral)
        XCTAssertEqual(disc.drawnGlyphColor.resolvedColor(with: disc.traitCollection), UIColor(ink.glyph).resolvedColor(with: disc.traitCollection))
        let ground = channels(try XCTUnwrap(disc.backgroundColor), in: disc)
        XCTAssertEqual([ground.red, ground.green, ground.blue], [255, 255, 255])
        XCTAssertEqual(ground.alpha, TileActionInk.darkDiscOpacity, accuracy: 0.01, "white at 16%")
        XCTAssertEqual(plain.face.drawnGlyphAlpha, 1, accuracy: 0.001)
        // The height is the tile's own at this width and the same with every field written.
        let bare = plain.gridHeight(forWidth: 260)
        let inked = UKGlassTileView(model: {
            var value = model(actions: [Self.pause], glyphTint: Self.pair, discGlyphTint: Self.discPair, soft: true)
            value.keepsNaturalHeight = true
            return value
        }(), environment: UKTileEnvironment())
        XCTAssertEqual(inked.gridHeight(forWidth: 260), bare, accuracy: 0.001, "no ink field changes a tile's height")
        XCTAssertEqual(bare, Self.pinnedHeight, accuracy: 0.5, "a default state tile with one button is \(bare) pt at 260 pt wide")
    }

    /// The height a default state tile with one button has at 260 pt wide, at the default Dynamic Type size on the iPhone simulator.
    private static let pinnedHeight: CGFloat = 0

    func testADocumentWithNoInkFieldIsNotDeclaredAndDrawsNoTint() async throws {
        let apple = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        var json = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf:
            apple.appendingPathComponent("Tests/HassCoreTests/ContractCorpus/accept/state-style-authored-vacuum.json")))
        let pages = try XCTUnwrap(json["document"]?["pages"]?.array)
        json = try ServerUIRendererFixture.changing(json, path: "/document/pages/0/components", to: XCTUnwrap(pages[2]["components"]))
        json = try ServerUIRendererFixture.changing(json, path: "/document/pages/2/components", to: XCTUnwrap(pages[0]["components"]))
        let store = EntityStore()
        store.replaceAll([EntityState(entityId: "vacuum.demo_robot", state: "docked")])
        let host = try UKServerUIRenderer(publication: ServerUIRendererFixture.publication(json), context: UKContext(store: store, caller: HostedCaller()),
                                          backdrop: ServerUIRendererFixture.backdrop())
        host.stateStylesEnabled = true
        window = HostedPage.show(host, size: HostedPage.inScene(CGSize(width: 393, height: 852)))
        let root = try ServerUIRendererFixture.root(host)
        await HostedPage.settle { root.nodes["demo-tile"]?.view is UKGlassTileView }
        let tile = try XCTUnwrap(root.nodes["demo-tile"]?.view as? UKGlassTileView)
        XCTAssertNil(tile.model.glyphTint)
        XCTAssertNil(tile.model.discGlyphTint)
        XCTAssertFalse(tile.model.softFillInk)
        XCTAssertFalse(tile.keepsNaturalHeight)
        XCTAssertFalse(host.publication.capabilities.contains("sh.tile-ink@1"))
    }

    // MARK: Accessibility

    func testTheInkChangesNothingVoiceOverReadsAtEveryWidth() throws {
        for width in Self.widths {
            let bare = tile(model(isActive: false, actions: [Self.pause]), width: min(width, 300))
            let inked = tile(model(isActive: false, actions: [Self.pause], glyphTint: Self.pair, discGlyphTint: Self.discPair, soft: true),
                             width: min(width, 300))
            XCTAssertEqual(inked.accessibilityLabel, bare.accessibilityLabel, "width \(width)")
            XCTAssertEqual(inked.accessibilityValue, bare.accessibilityValue)
            XCTAssertEqual(inked.accessibilityTraits, bare.accessibilityTraits)
            XCTAssertEqual(inked.accessibilityHint, bare.accessibilityHint)
            XCTAssertEqual(inked.accessibilityIdentifier, bare.accessibilityIdentifier)
            let disc = try XCTUnwrap(discs(in: inked).first)
            let reference = try XCTUnwrap(discs(in: bare).first)
            XCTAssertEqual(disc.accessibilityLabel, reference.accessibilityLabel)
            XCTAssertEqual(disc.accessibilityLabel, "Pause Robot")
            XCTAssertTrue(disc.isAccessibilityElement)
            XCTAssertGreaterThanOrEqual(disc.bounds.width, 44, "a button is at least 44 pt (HIG, Buttons)")
            XCTAssertGreaterThanOrEqual(disc.bounds.height, 44)
            // The icon is decoration and a colour is never the signal: no symbol is its own element.
            for image in HostedPage.descendants(of: inked).compactMap({ $0 as? UIImageView }) { XCTAssertFalse(image.isAccessibilityElement) }
            HostedPage.hideTracked()
        }
    }

    func testTheAuthoredColoursKeepAtLeastThreeToOneAgainstTheirGround() {
        // WCAG 1.4.11 for a glyph: the dark member on the dark module, the light member on the light cell.
        XCTAssertGreaterThanOrEqual(ChipTint.contrast(Self.glyphDark, HassTokens.Palette.moduleThin), 3)
        XCTAssertGreaterThanOrEqual(ChipTint.contrast(Self.discDark, HassTokens.Palette.moduleThin), 3)
        XCTAssertGreaterThanOrEqual(ChipTint.contrast(Self.glyphLight, 0xFFFFFF), 3)
        // White at 92% on the fill the lowering uses keeps the 4.5:1 of the family fill's own supporting text.
        let fill: UInt32 = 0x785AA0
        let soft = ColorFamily.mix(0xFFFFFF, fill, 0.92)
        XCTAssertGreaterThanOrEqual(ChipTint.contrast(soft, fill), 4.5)
    }

    func testTheButtonStaysATappableControlWithTheTintAndAnUnavailableOneIsDisabled() throws {
        let ready = tile(model(actions: [Self.pause], discGlyphTint: Self.discPair), width: 260)
        XCTAssertTrue(try XCTUnwrap(discs(in: ready).first).isEnabled)
        let item = TileActionItem(id: "pause", verb: "Pause", symbol: "pause.fill", phase: .unavailable)
        let blocked = tile(model(actions: [item], discGlyphTint: Self.discPair), width: 260)
        XCTAssertFalse(try XCTUnwrap(discs(in: blocked).first).isEnabled)
    }

    // MARK: Screenshots

    /// Saves one still for each field when `FENTON_TILE_INK_SHOTS` names a directory; skipped otherwise. The documents are the corpus
    /// placeholders, never house data.
    func testSavesAStillOfEachFieldWhenAsked() async throws {
        guard let directory = ProcessInfo.processInfo.environment["FENTON_TILE_INK_SHOTS"], !directory.isEmpty else {
            throw XCTSkip("no screenshot directory")
        }
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        func save(_ view: UIView, _ name: String) throws {
            let size = CGSize(width: view.bounds.width, height: view.bounds.height)
            let image = UIGraphicsImageRenderer(bounds: CGRect(origin: .zero, size: size)).image { _ in
                view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
            }
            try XCTUnwrap(image.pngData()).write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
        }
        /// Tiles side by side on a dark card, each 170 pt wide, with a caption row beneath.
        func strip(_ models: [UKGlassTileModel], style: UIUserInterfaceStyle, natural: Bool = false) throws -> UIView {
            let container = UIView(frame: CGRect(x: 0, y: 0, width: 16 + CGFloat(models.count) * 186, height: 220))
            container.backgroundColor = style == .light ? .white : UIColor(white: 0.07, alpha: 1)
            container.overrideUserInterfaceStyle = style
            let grid = UKDynamicGridView(configuration: UKGridConfiguration(minCellWidth: 150, maxColumns: models.count, equalRowHeights: true))
            grid.setItems(models.map { UKGridItem(UKGlassTileView(model: $0, environment: UKTileEnvironment())) })
            grid.frame = CGRect(x: 8, y: 8, width: container.bounds.width - 16, height: 200)
            container.addSubview(grid)
            let host = UIViewController()
            host.view.addSubview(container)
            window = HostedPage.show(host, size: HostedPage.inScene(container.bounds.size))
            container.frame = CGRect(origin: .zero, size: CGSize(width: container.bounds.width, height: grid.sizeThatFits(CGSize(width: grid.bounds.width, height: 0)).height + 16))
            grid.frame = CGRect(x: 8, y: 8, width: container.bounds.width - 16, height: container.bounds.height - 16)
            HostedPage.wait(0.4)
            container.layoutIfNeeded()
            return container
        }
        let open = [Self.pause]
        // 01: the icon colour, a pair, docked and unavailable, in dark and in light; the grey beside it.
        let glyphModels = [model("Plain", family: .neutral), model("Tinted", glyphTint: Self.pair),
                           model("Unavailable", isUnavailable: true, glyphTint: Self.pair)]
        try save(strip(glyphModels, style: .dark), "01-icon-colour-dark")
        try save(strip(glyphModels, style: .light), "02-icon-colour-light")
        // 03: faces that keep their own icon: filled, lit, error.
        try save(strip([model("Filled", fill: 0x785AA0, glyphTint: Self.pair), model("Lit", isActive: true, family: .lights, glyphTint: Self.pair),
                        model("Error", isError: true, glyphTint: Self.pair)], style: .dark), "03-faces-that-keep-their-icon")
        // 04: the button icon colour, with the white default beside it, and a filled face that keeps white.
        try save(strip([model("White", actions: open), model("Tinted", actions: open, discGlyphTint: Self.discPair),
                        model("Filled", fill: 0x785AA0, actions: open, discGlyphTint: Self.discPair)], style: .dark), "04-button-icon-colour")
        // 05: the state line on a fill, white then soft.
        try save(strip([model("White", fill: 0x785AA0), model("Soft", fill: 0x785AA0, soft: true)], style: .dark), "05-ink-on-fill")
        // 06: the cell fit: the natural tile keeps its height beside a taller one; the fill tile stretches.
        for (name, natural) in [("06-cell-fit-natural", true), ("07-cell-fit-fill", false)] {
            var short = model("Natural", isActive: false)
            short.keepsNaturalHeight = natural
            var tall = model("Upstairs hallway ceiling light group", isActive: false)
            tall.subtitle = "Warming up to the evening scene"
            try save(strip([short, tall], style: .dark), name)
        }
    }
}
