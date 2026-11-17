import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

// MARK: - A glyph that differs in light and dark

/// Hosted UX and accessibility checks for the light and dark colour pair (`sh.solid-appearance@1`), drawn as the glyph of the Auto-Clean toggle
/// row: the cleaning glyph is purple `0x9C6DC3` in light and a lighter `0xC88CFA` in dark.
///
/// Each test runs at the iPhone, iPhone Duo and iPad widths (a simulator narrower than a width draws it at the simulator's own, as the other
/// hosted layout tests do). The colour is a dynamic `UIColor`, so switching the window's appearance redraws the glyph with no reload: the same
/// row, the same view, the other member of the pair.
@MainActor
final class ServerUIAppearanceHostedTests: XCTestCase {
    /// The widths of the three families: iPhone, folded Duo and iPad.
    private static let widths: [CGFloat] = [390, 744, 1024]
    private static let light = AppearanceFill(light: 0x9C6DC3, dark: 0xC88CFA).rgb(isDark: false)
    private static let dark = AppearanceFill(light: 0x9C6DC3, dark: 0xC88CFA).rgb(isDark: true)

    private var store = EntityStore()
    private var window: UIWindow?

    override func tearDown() async throws {
        HostedPage.hideTracked()
        HostedPage.resetGlobals()
        window = nil
        try await super.tearDown()
    }

    // MARK: Fixture

    /// The Auto-Clean row from the corpus, its glyph replaced by the pair and the capability declared.
    private func publication() throws -> ServerUICompositionPublication {
        let apple = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = apple.appendingPathComponent("Tests/HassCoreTests/ContractCorpus/accept/parts-row-auto-clean-row.json")
        var json = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
        let pages = try XCTUnwrap(json["document"]?["pages"]?.array)
        json = try ServerUIRendererFixture.changing(json, path: "/document/pages/0/components", to: XCTUnwrap(pages[2]["components"]))
        json = try ServerUIRendererFixture.changing(json, path: "/document/pages/2/components", to: XCTUnwrap(pages[0]["components"]))
        func member(_ rgb: UInt32) -> JSONValue {
            .object(["type": .string("solid-rgb"), "red": .number(Double(rgb >> 16 & 0xFF)),
                     "green": .number(Double(rgb >> 8 & 0xFF)), "blue": .number(Double(rgb & 0xFF))])
        }
        let pair: JSONValue = .object(["type": .string("solid-appearance"), "light": member(Self.light), "dark": member(Self.dark)])
        json = try ServerUIRendererFixture.changing(json, path: "/document/pages/0/components/0/props/glyph", to: pair)
        let declared = try XCTUnwrap(json["capabilities"]?.array?.compactMap(\.string))
        json = try ServerUIRendererFixture.changing(json, path: "/capabilities",
                                                    to: .array((declared + ["sh.solid-appearance@1"]).sorted().map { .string($0) }))
        return try ServerUICompositionPublication.decode(JSONEncoder().encode(json))
    }

    private func page(width: CGFloat) throws -> UKServerUIPage {
        store = EntityStore()
        store.replaceAll([EntityState(entityId: "input_boolean.demo_auto_clean", state: "on")])
        let host = try UKServerUIRenderer(publication: publication(), context: UKContext(store: store, caller: HostedCaller()),
                                          backdrop: ServerUIRendererFixture.backdrop())
        window = HostedPage.show(host, size: HostedPage.inScene(CGSize(width: width, height: 1180)))
        HostedPage.wait(0.1)
        let root = try ServerUIRendererFixture.root(host)
        root.view.layoutIfNeeded()
        return root
    }

    /// Draws the page in `style`. The page pins its own appearance (pages stay dark), so the override goes on the page's view, below the window.
    private func setStyle(_ style: UIUserInterfaceStyle, _ root: UKServerUIPage) {
        window?.overrideUserInterfaceStyle = style
        root.view.overrideUserInterfaceStyle = style
        HostedPage.wait(0.1)
    }

    private func row(_ root: UKServerUIPage) throws -> UKModuleToggleRow {
        let node = try XCTUnwrap(root.nodes["auto-clean-row"]?.view as? UKServerUILocalControl)
        return try XCTUnwrap(node.drawnControl as? UKModuleToggleRow)
    }

    private func images(in view: UIView) -> [UIImageView] {
        ((view as? UIImageView).map { [$0] } ?? []) + view.subviews.flatMap { images(in: $0) }
    }

    /// The channels of `color` as seen by `view` in its present appearance, as `0xRRGGBB`.
    private func packed(_ color: UIColor?, in view: UIView) throws -> UInt32 {
        let resolved = try XCTUnwrap(color).resolvedColor(with: view.traitCollection)
        var (red, green, blue, alpha) = (CGFloat(0), CGFloat(0), CGFloat(0), CGFloat(0))
        XCTAssertTrue(resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        XCTAssertEqual(alpha, 1, accuracy: 0.001, "an authored pair is opaque")
        return UInt32((red * 255).rounded()) << 16 | UInt32((green * 255).rounded()) << 8 | UInt32((blue * 255).rounded())
    }

    // MARK: UX

    func testTheGlyphDrawsItsLightMemberInLightAndItsDarkMemberInDarkAtEveryFamilyWidth() throws {
        for width in Self.widths {
            let root = try page(width: width)
            let row = try self.row(root)
            for (style, expected) in [(UIUserInterfaceStyle.light, Self.light), (.dark, Self.dark)] {
                setStyle(style, root)
                root.view.layoutIfNeeded()
                XCTAssertEqual(row.traitCollection.userInterfaceStyle, style, "width \(width)")
                XCTAssertEqual(try packed(row.row.rowContent.glyph, in: row), expected, "the row's glyph colour, \(style.rawValue), width \(width)")
                let drawn = try images(in: row).filter { $0.image != nil }.map { try packed($0.tintColor, in: $0) }
                XCTAssertTrue(drawn.contains(expected), "a symbol is tinted \(String(expected, radix: 16)) in \(style.rawValue) at width \(width): \(drawn)")
            }
            HostedPage.hideTracked()
        }
    }

    func testAChangeOfAppearanceRedrawsTheSameRowWithNoReload() throws {
        let root = try page(width: 390)
        let row = try self.row(root)
        setStyle(.light, root)
        let before = try packed(row.row.rowContent.glyph, in: row)
        setStyle(.dark, root)
        let after = try packed(row.row.rowContent.glyph, in: row)
        XCTAssertNotEqual(before, after, "the colour followed the trait collection")
        XCTAssertTrue(try self.row(root) === row, "the row was not rebuilt")
        XCTAssertEqual(store.entity("input_boolean.demo_auto_clean").state?.state, "on")
    }

    // MARK: Accessibility

    func testTheRowIsStillOneSwitchWithItsLabelHintAndAMeetingTargetInBothAppearances() throws {
        for width in Self.widths {
            let root = try page(width: width)
            let row = try self.row(root)
            for style in [UIUserInterfaceStyle.light, .dark] {
                setStyle(style, root)
                root.view.layoutIfNeeded()
                XCTAssertEqual(row.accessibilityLabel, "Auto-Clean", "width \(width)")
                XCTAssertTrue(row.accessibilityTraits.contains(.toggleButton))
                XCTAssertEqual(row.accessibilityValue, "1")
                XCTAssertEqual(row.accessibilityHint, "Turns automatic cleaning on or off.")
                XCTAssertGreaterThanOrEqual(row.bounds.height, 60, "the module row with a subtitle is 60 pt")
                // The glyph is decoration: the label already names the row, so no symbol is its own element and colour is not the signal.
                for image in images(in: row) { XCTAssertFalse(image.isAccessibilityElement, "a symbol is decoration") }
            }
            HostedPage.hideTracked()
        }
    }

    // MARK: The colour itself

    func testAPairResolvesToDifferentColoursForLightAndDarkTraitCollections() throws {
        let color = UIColor(AppearanceFill(light: Self.light, dark: Self.dark).token)
        let light = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        let dark = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        XCTAssertNotEqual(light, dark)
        XCTAssertEqual(light, UIColor(red: 156 / 255, green: 109 / 255, blue: 195 / 255, alpha: 1))
        XCTAssertEqual(dark, UIColor(red: 200 / 255, green: 140 / 255, blue: 250 / 255, alpha: 1))
        // Increase Contrast keeps the author's colours.
        let contrast = UITraitCollection(traitsFrom: [UITraitCollection(userInterfaceStyle: .dark), UITraitCollection(accessibilityContrast: .high)])
        XCTAssertEqual(color.resolvedColor(with: contrast), dark)
        // One colour is a plain colour, the same in both.
        let fixed = UIColor(AppearanceFill(0x112233).token)
        XCTAssertEqual(fixed.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)),
                       fixed.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark)))
    }

    func testATileFaceSolidFillFollowsTheTraitCollection() throws {
        var model = UKGlassTileModel(title: "Hall", symbol: "house", family: .neutral, fillRGB: Self.light, isActive: false, kind: .navigate)
        model.fillDarkRGB = Self.dark
        let tile = UKGlassTileView(model: model, environment: UKTileEnvironment())
        let host = UIViewController()
        host.view.addSubview(tile)
        window = HostedPage.show(host, size: CGSize(width: 200, height: 200))
        tile.frame = CGRect(x: 0, y: 0, width: 170, height: 120)
        for (style, expected) in [(UIUserInterfaceStyle.light, Self.light), (.dark, Self.dark)] {
            window?.overrideUserInterfaceStyle = style
            HostedPage.wait(0.1)
            tile.layoutIfNeeded()
            XCTAssertEqual(tile.face.content.fillRGB, Self.light)
            XCTAssertEqual(tile.face.content.fillDarkRGB, Self.dark)
            XCTAssertEqual(tile.traitCollection.userInterfaceStyle, style)
            XCTAssertEqual(tile.face.drawnFillRGB, expected, "the tile drew the \(style.rawValue) member")
        }
    }

    // MARK: Screenshots

    /// Saves the glyph in light and in dark as PNGs when `FENTON_APPEARANCE_SHOTS` names a directory; skipped otherwise. The document is the
    /// corpus placeholder, never house data.
    func testSavesTheGlyphInLightAndDarkWhenAsked() throws {
        guard let directory = ProcessInfo.processInfo.environment["FENTON_APPEARANCE_SHOTS"], !directory.isEmpty else {
            throw XCTSkip("no screenshot directory")
        }
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let root = try page(width: 390)
        for (name, style) in [("01-auto-clean-glyph-light", UIUserInterfaceStyle.light), ("02-auto-clean-glyph-dark", .dark)] {
            setStyle(style, root)
            HostedPage.wait(0.4)
            let view = try XCTUnwrap(root.view.window ?? root.view)
            let image = UIGraphicsImageRenderer(bounds: CGRect(x: 0, y: 0, width: view.bounds.width, height: 220)).image { _ in
                view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
            }
            try XCTUnwrap(image.pngData()).write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
        }
    }
}
