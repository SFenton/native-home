import Foundation
@testable import HassDesign
import SwiftUI
import Testing

/// The app icon's art, read back from rendered pixels: the house, the heart on its ring and the glass around them, in each Home
/// Screen appearance (HIG App icons, "Appearances"). `tools/render_app_icons.sh` renders the asset catalog from this view.
@MainActor
struct AppIconArtworkTests {
    typealias Pixel = (r: Int, g: Int, b: Int)
    static let side = 200

    private func render(_ art: AppIconArtwork) throws -> CGImage {
        let renderer = ImageRenderer(content: art.frame(width: CGFloat(Self.side), height: CGFloat(Self.side)))
        renderer.scale = 1
        return try #require(renderer.cgImage)
    }

    private func pixel(_ image: CGImage, x: Int, y: Int) throws -> Pixel {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let drawn = data.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                                          bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        try #require(drawn)
        let i = (y * image.width + x) * 4
        return (Int(data[i]), Int(data[i + 1]), Int(data[i + 2]))
    }

    /// Where a point in the glyph's 100-unit coordinates lands on the rendered icon.
    private func point(_ x: Double, _ y: Double) -> (x: Int, y: Int) {
        let box = Double(Self.side) * Double(AppIconArtwork.glyphFraction)
        let origin = (Double(Self.side) - box) / 2
        return (Int(origin + x * box / 100), Int(origin + y * box / 100))
    }

    private func luma(_ p: Pixel) -> Double { 0.2126 * Double(p.r) + 0.7152 * Double(p.g) + 0.0722 * Double(p.b) }

    private func near(_ p: Pixel, _ r: Int, _ g: Int, _ b: Int, within slack: Int = 6) -> Bool {
        abs(p.r - r) <= slack && abs(p.g - g) <= slack && abs(p.b - b) <= slack
    }

    @Test func theHouseAndTheHeartAreDrawnInTheGlyphColourAndTheWindowIsCutOut() throws {
        let image = try render(AppIconArtwork(tint: 0x203040, glyph: 0xFF8040))
        // The house wall, left of the heart's ring.
        let wall = point(50, 80)
        #expect(near(try pixel(image, x: wall.x, y: wall.y), 0xFF, 0x80, 0x40), "the house is the glyph colour")
        // The heart: its centre in the heart's own box (50, 50) placed at (55, 60) and scaled to 0.40.
        let heart = point(55 + 0.4 * 50, 60 + 0.4 * 50)
        #expect(near(try pixel(image, x: heart.x, y: heart.y), 0xFF, 0x80, 0x40), "the heart is the glyph colour")
        // A window pane is a hole in the house: the glass shows through.
        let pane = point(29.75, 63.75)
        let glass = try pixel(image, x: pane.x, y: pane.y)
        #expect(!near(glass, 0xFF, 0x80, 0x40, within: 40), "the four-pane window is cut out of the house: \(glass)")
        // The ring around the heart is the glass itself, not the glyph colour: just outside the heart's lobe, inside the house.
        let ring = point(55 + 0.4 * 8 - 1.2, 60 + 0.4 * 34)
        #expect(!near(try pixel(image, x: ring.x, y: ring.y), 0xFF, 0x80, 0x40, within: 40), "the house is cut away around the heart")
    }

    @Test func theGlassCoversTheWholeSquareToTheCorners() throws {
        let image = try render(AppIconArtwork(tint: 0x203040, glyph: 0xFFFFFF))
        for (x, y) in [(0, 0), (Self.side - 1, 0), (0, Self.side - 1), (Self.side - 1, Self.side - 1)] {
            let corner = try pixel(image, x: x, y: y)
            #expect(luma(corner) < 120, "full-bleed art, not a rounded tile on white: \(corner) at \(x),\(y)")
        }
    }

    @Test func theDuskGlowWarmsTheLowerRightAndTheTintOpacityDecidesHowMuchShowsThrough() throws {
        let open = try render(AppIconArtwork(tint: 0x000000, tintOpacity: 0, glyph: 0xFFFFFF))
        let topLeft = try pixel(open, x: 4, y: 100)
        let lowerRight = try pixel(open, x: Int(Double(Self.side) * 0.74), y: Int(Double(Self.side) * 0.84))
        #expect(topLeft.b > topLeft.r, "the top of the dusk is blue: \(topLeft)")
        #expect(lowerRight.r > lowerRight.b + 20, "the amber glow is low right: \(lowerRight)")
        let covered = try render(AppIconArtwork(tint: 0x000000, tintOpacity: 1, glyph: 0xFFFFFF))
        let under = try pixel(covered, x: Int(Double(Self.side) * 0.74), y: Int(Double(Self.side) * 0.84))
        #expect(luma(under) < luma(lowerRight) / 2, "an opaque tint hides the glow: \(under) vs \(lowerRight)")
        #expect(AppIconArtwork.Standard.background.count == 3)
        #expect(AppIconArtwork.Standard.glows.count == 2)
    }

    @Test func theDarkAppearanceIsDeeperThanTheStandardOne() throws {
        let standard = try render(AppIconArtwork(tint: 0x4060A0, glyph: 0xFFFFFF, appearance: .standard))
        let dark = try render(AppIconArtwork(tint: 0x4060A0, glyph: 0xFFFFFF, appearance: .dark))
        let spots = [(10, 10), (Self.side - 10, Self.side - 10), (10, Self.side - 10)]
        for (x, y) in spots {
            #expect(luma(try pixel(dark, x: x, y: y)) < luma(try pixel(standard, x: x, y: y)) + 1, "dark is not brighter at \(x),\(y)")
        }
        let wall = point(50, 80)
        #expect(near(try pixel(dark, x: wall.x, y: wall.y), 255, 255, 255), "the glyph stays white")
    }

    @Test func theTintedAppearanceIsGreyscaleWithABrightGlyphTheSystemCanTint() throws {
        let image = try render(AppIconArtwork(tint: 0xFF0000, glyph: 0x00FF00, appearance: .tinted))
        for (x, y) in [(10, 10), (Self.side - 10, Self.side - 10), (100, 20)] {
            let p = try pixel(image, x: x, y: y)
            #expect(abs(p.r - p.g) <= 3 && abs(p.g - p.b) <= 3, "greyscale at \(x),\(y): \(p)")
        }
        let wall = try pixel(image, x: point(50, 80).x, y: point(50, 80).y)
        #expect(abs(wall.r - wall.g) <= 3 && wall.r > 230, "a near-white glyph whatever colour was asked for: \(wall)")
        let ground = try pixel(image, x: 10, y: 10)
        #expect(luma(wall) > luma(ground) + 100, "the glyph is the brightest thing")
    }

    @Test func theGeometryIsInsideTheHundredUnitBox() {
        for path in [AppIconArtwork.house, AppIconArtwork.heart] {
            let bounds = path.boundingRect
            #expect(bounds.minX >= 0 && bounds.minY >= 0 && bounds.maxX <= 100 && bounds.maxY <= 100, "\(bounds)")
        }
        #expect(AppIconArtwork.glyphFraction == 0.8)
    }
}
