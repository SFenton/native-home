import Foundation
@testable import HassDesign
import SwiftUI
import Testing

/// The tile finish (`.agents/design/direction-g.md`, Tile finish): the tinted glass tokens, the accessibility fallback to
/// solid, and the rendered contrast of every family, room, Quick Link, chore and food fill on the wallpaper's lightest and
/// darkest regions and in dark and light sheets.
@MainActor
struct TileFinishTests {
    typealias RGB = (r: Double, g: Double, b: Double)

    /// The lightest wallpaper under the scrim that white text still reads on at 4.5:1 (sRGB grey 0.46, 4.7:1 for white), and
    /// the darkest, the web shell's `#111723`.
    nonisolated static let lightest: RGB = (0.46, 0.46, 0.46)
    nonisolated static let darkest: RGB = (17 / 255, 23 / 255, 35 / 255)

    /// A surface the finish is drawn on: the wallpaper (dark, always) or a sheet in either appearance.
    struct Place: CustomTestStringConvertible, Sendable {
        var surface: TileSurface
        var scheme: ColorScheme
        var backdrop: RGB?
        var testDescription: String { "\(surface) \(scheme)\(backdrop == nil ? "" : " \(backdrop!)")" }
        var appearance: TileAppearance { .resolve(surface: surface, scheme: scheme) }
    }

    nonisolated static let places: [Place] = [
        Place(surface: .page, scheme: .dark, backdrop: lightest), Place(surface: .page, scheme: .dark, backdrop: darkest),
        Place(surface: .sheet, scheme: .dark, backdrop: nil), Place(surface: .sheet, scheme: .light, backdrop: nil),
    ]

    // MARK: Tokens

    @Test func tintedGlassShipsAndSolidIsTheFallback() {
        #expect(TileFinish.standard == .tintedGlass, "The owner chose A, Tinted Glass (2026-10-17)")
        #expect(EnvironmentValues().tileFinish == .tintedGlass)
        #expect(TileFinish.allCases == [.tintedGlass, .solid])
        #expect(TileFinish.solid.offGlyphKeep == 0.72 && TileFinish.tintedGlass.offGlyphKeep == 0.88)
    }

    @Test func theTokensAreTheOwnersChoiceAndASheetIsOpaque() {
        let page = TileFinish.Tokens.tintedGlass(on: .page)
        #expect(page == TileFinish.Tokens(underlay: 0.66, fillUnderlay: 0.50, fillOpacity: 0.78, sheenTop: 0.14, sheenBottom: 0.08,
                                          rimTop: 0.32, rimBottom: 0.06))
        // The wallpaper tints a fill a little, but not so much that white ink loses its contrast.
        #expect(page.fillOpacity < 1 && page.fillOpacity >= 0.7)
        #expect(page.rimTop > page.rimBottom && page.rimBottom > 0)
        // A sheet has no wallpaper to show through: the fill is opaque, the sheen and rim are the page's.
        let sheet = TileFinish.Tokens.tintedGlass(on: .sheet)
        #expect(sheet.fillOpacity == 1)
        #expect(sheet.sheenTop == page.sheenTop && sheet.rimTop == page.rimTop)
    }

    @Test func reduceTransparencyAndIncreaseContrastFallBackToSolid() {
        for finish in TileFinish.allCases {
            #expect(TileFinish.effective(finish, reduceTransparency: true, increasedContrast: false) == .solid)
            #expect(TileFinish.effective(finish, reduceTransparency: false, increasedContrast: true) == .solid)
            #expect(TileFinish.effective(finish, reduceTransparency: true, increasedContrast: true) == .solid)
            #expect(TileFinish.effective(finish, reduceTransparency: false, increasedContrast: false) == finish)
        }
    }

    @Test func flattenedLayersCompositeLikeTheirStack() {
        let stack: [(rgb: UInt32, opacity: Double)] = [(0x1C1C1E, 0.66), (0x076C91, 0.78)]
        let (r, g, b, a) = FinishColor.premultiplied(stack)
        // The expected alpha of two layers: 1 - (1 - 0.66)(1 - 0.78).
        #expect(abs(a - (1 - 0.34 * 0.22)) < 1e-9)
        // Over a backdrop, the flattened colour (r/a, g/a, b/a at alpha a) gives the stack's pixels.
        let backdrop = 0.46
        func layered(_ channel: (UInt32) -> Double) -> Double {
            var v = backdrop
            for layer in stack { v = channel(layer.rgb) * layer.opacity + v * (1 - layer.opacity) }
            return v
        }
        let flat = (r / a) * a + backdrop * (1 - a)
        #expect(abs(flat - layered { Double(($0 >> 16) & 0xFF) / 255 }) < 1e-9)
        #expect(abs((g / a) * a + backdrop * (1 - a) - layered { Double(($0 >> 8) & 0xFF) / 255 }) < 1e-9)
        #expect(abs((b / a) * a + backdrop * (1 - a) - layered { Double($0 & 0xFF) / 255 }) < 1e-9)
        #expect(FinishColor.premultiplied([]).3 == 0)
        #expect(TileFinish.omitted.isEmpty, "A normal launch leaves no layer out")
    }

    // MARK: Rendering

    @Test func theOffGlyphIsLiftedOnlyWhereTintedGlassNeedsIt() {
        for family in ColorFamily.allCases {
            // Solid is the shipped mix; a light sheet is the same mix with tinted glass's keep.
            #expect(family.offGlyphRGB(.dark, under: .solid) == family.offGlyphRGB(.dark))
            #expect(family.offGlyphRGB(.light, under: .solid) == family.offGlyphRGB(.light))
            #expect(family.offGlyphRGB(.light, under: .tintedGlass) == family.offGlyphRGB(.light, keep: 0.88))
            // The dark glyph is never darker than the plain mix, and reads 3:1 on the lightest ground.
            let plain = family.offGlyphRGB(.dark, keep: 0.88)
            let lifted = family.offGlyphRGB(.dark, under: .tintedGlass)
            #expect(ChipTint.luminance(lifted) >= ChipTint.luminance(plain) - 1e-9, "\(family)")
            #expect(ChipTint.contrast(lifted, ColorFamily.lightestGlyphGround) >= 3, "\(family)")
        }
        // A family that already reads is untouched; the Food families are the ones that needed it.
        #expect(ColorFamily.lights.offGlyphRGB(.dark, under: .tintedGlass) == ColorFamily.lights.offGlyphRGB(.dark, keep: 0.88))
        #expect(ColorFamily.pantry.offGlyphRGB(.dark, under: .tintedGlass) != ColorFamily.pantry.offGlyphRGB(.dark, keep: 0.88))
    }

    // MARK: Contrast

    /// Where a tile's text sits, as fractions of its height. A row's title is at about a third of the height and its state
    /// below the middle; an anchored-bottom tile's text is lower still.
    private static let titleRows = [0.3, 0.5, 0.85]
    private static let stateRows = [0.5, 0.85]

    /// Every white-ink fill, the way the app uses it: the families (which include the chore lists and the food spaces), the
    /// sixteen rooms, and the Quick Links (Rooms, Security by alarm mode and unknown, Custom Lights).
    private static let whiteInkFills: [(name: String, style: TileFaceStyle)] = {
        var fills: [(String, TileFaceStyle)] = ColorFamily.allCases.compactMap { family in
            family.spec.darkInk || family.spec.fill == nil ? nil : (family.rawValue, .filled(family))
        }
        fills += RoomPalette.fills.enumerated().map { ("room \($0.offset)", .colored($0.element)) }
        var links = Set(["rooms", "custom-lights"].compactMap { QuickLinkPalette.fill(forLink: $0) })
        links.insert(QuickLinkPalette.securityUnknown)
        for state in ["armed_home", "armed_away", "armed_night", "disarmed", "triggered", "arming"] {
            if let fill = QuickLinkPalette.fill(forLink: "security-system", alarmState: state) { links.insert(fill) }
        }
        fills += links.sorted().map { ("link \(String($0, radix: 16))", .colored($0)) }
        return fills
    }()

    /// The page's text holds 4.5:1 and a glyph 3:1 under tinted glass in every place a tile draws, measured on rendered
    /// pixels at the tile's right edge (clear of the text) at the heights the title and state sit: the wallpaper's lightest
    /// and darkest regions, and a dark and a light sheet.
    @Test(arguments: places)
    func inkHoldsContrastEverywhere(_ place: Place) {
        let secondary: Double = switch (place.surface, place.appearance) {
        case (.page, _): HassTokens.Surface.secondaryOnWallpaperOpacity
        case (.sheet, .dark): HassTokens.Palette.secondaryInSheetDarkOpacity
        case (.sheet, .light): HassTokens.Palette.secondaryInSheetLightOpacity
        }
        // Off: the neutral module on the page, the cell in a sheet (a white cell in a light sheet carries label ink).
        let primary: RGB = place.appearance == .light ? hex(0x1C1C1E) : white
        let secondaryInk: RGB = place.appearance == .light ? hex(0x3C3C43) : (235 / 255, 235 / 255, 245 / 255)
        for ground in samples(.off, in: place, fractions: Self.titleRows) {
            expectRatio(primary, over: ground, atLeast: 4.5, "\(place) off title")
        }
        for ground in samples(.off, in: place, fractions: Self.stateRows) {
            expectRatio(blend(secondaryInk, over: ground, alpha: secondary), over: ground, atLeast: 4.5, "\(place) off state")
        }
        // On: white ink on every white-ink fill the app uses.
        for (name, style) in Self.whiteInkFills {
            for ground in samples(style, in: place, fractions: Self.titleRows) {
                expectRatio(white, over: ground, atLeast: 4.5, "\(place) \(name) title")
            }
            for ground in samples(style, in: place, fractions: Self.stateRows) {
                expectRatio(blend(white, over: ground, alpha: style.isColored ? 1 : 0.92), over: ground, atLeast: 4.5, "\(place) \(name) state")
            }
            // A chore list's open count is a bold 22 pt numeral in the top-trailing corner, under the sheen's brightest part.
            if case .filled = style {
                for ground in samples(style, in: place, fractions: [0.15]) {
                    expectRatio(white, over: ground, atLeast: 3, "\(place) \(name) count")
                }
            }
        }
        // Dark ink on the lit tile and on power: the sheen only lightens the top and shades the bottom a little.
        for ground in samples(.lit, in: place, fractions: Self.titleRows) {
            expectRatio(hex(0x1C1C1E), over: ground, atLeast: 4.5, "\(place) lit title")
        }
        for ground in samples(.lit, in: place, fractions: Self.stateRows) {
            expectRatio(blend(hex(0x1C1C1E), over: ground, alpha: LitTile.secondaryInkOpacity), over: ground, atLeast: 4.5, "\(place) lit state")
        }
        for ground in samples(.filled(.power), in: place, fractions: Self.titleRows) {
            expectRatio(hex(0x1C1C1E), over: ground, atLeast: 4.5, "\(place) power title")
        }
        for ground in samples(.filled(.power), in: place, fractions: Self.stateRows) {
            expectRatio(blend(hex(0x282000), over: ground, alpha: 0.82), over: ground, atLeast: 4.5, "\(place) power state")
        }
        // An error: the red state text on the dense ground (page) or the cell (sheet).
        for ground in samples(.error, in: place, fractions: Self.stateRows) {
            expectRatio(hex(place.appearance.errorRGB), over: ground, atLeast: 4.5, "\(place) error")
        }
        // Off glyphs: the family colour mixed toward grey; 3:1 in every place a tile draws.
        for family in ColorFamily.allCases where family != .neutral {
            let glyph = hex(family.offGlyphRGB(place.appearance.scheme, under: .tintedGlass))
            for ground in samples(.off, in: place, fractions: [0.15, 0.3, 0.5]) {
                expectRatio(glyph, over: ground, atLeast: 3, "\(place) \(family) off glyph")
            }
        }
    }

    // MARK: Helpers

    private var white: RGB { (1, 1, 1) }

    private func hex(_ value: UInt32) -> RGB {
        (Double((value >> 16) & 0xFF) / 255, Double((value >> 8) & 0xFF) / 255, Double(value & 0xFF) / 255)
    }

    private func blend(_ ink: RGB, over ground: RGB, alpha: Double) -> RGB {
        (ink.r * alpha + ground.r * (1 - alpha), ink.g * alpha + ground.g * (1 - alpha), ink.b * alpha + ground.b * (1 - alpha))
    }

    private func luminance(_ c: RGB) -> Double {
        func linear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(c.r) + 0.7152 * linear(c.g) + 0.0722 * linear(c.b)
    }

    private func ratio(_ a: RGB, _ b: RGB) -> Double {
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    private func expectRatio(_ ink: RGB, over ground: RGB, atLeast minimum: Double, _ label: String,
                             sourceLocation: SourceLocation = #_sourceLocation) {
        let value = ratio(ink, ground)
        #expect(value >= minimum, "\(label): \(value):1 over \(ground)", sourceLocation: sourceLocation)
    }

    /// The ground tinted glass draws behind text, read from rendered pixels at the right edge at the given heights (a
    /// fraction of the tile): where the title and state sit by default.
    private func samples(_ style: TileFaceStyle, in place: Place, fractions: [Double]) -> [RGB] {
        let size = CGSize(width: 170, height: 90)
        let ground = TintedGlassGround(style: style, surface: place.surface, appearance: place.appearance,
                                       tint: .gray, wash: nil, level: nil, levelTint: nil)
            .clipShape(RoundedRectangle(cornerRadius: HassTokens.Radius.tile, style: .continuous))
        let view = ZStack {
            Color(.sRGB, red: place.backdrop?.r ?? 0, green: place.backdrop?.g ?? 0, blue: place.backdrop?.b ?? 0)
            ground
        }
        .frame(width: size.width, height: size.height)
        .environment(\.colorScheme, place.scheme)
        let image = ImageRenderer(content: view)
        image.scale = 1
        guard let cg = image.cgImage else { return [] }
        return fractions.compactMap { fraction in pixel(cg, x: Int(size.width * 0.85), y: Int(size.height * fraction)) }
    }

    private func pixel(_ image: CGImage, x: Int, y: Int) -> RGB? {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let drawn = data.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                                          bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        guard drawn, x < image.width, y < image.height else { return nil }
        let i = (y * image.width + x) * 4
        return (Double(data[i]) / 255, Double(data[i + 1]) / 255, Double(data[i + 2]) / 255)
    }
}
