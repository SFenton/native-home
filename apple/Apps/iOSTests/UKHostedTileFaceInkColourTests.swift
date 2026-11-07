import HassDesign
import SwiftUI
import UIKit
import XCTest

/// The SwiftUI colours of a tile face resolve to the same sRGB as their tokens, on the real UIKit colour system.
/// (The host `swift test` run compares the tokens; SwiftUI `Color` has no usable equality or resolution there.)
@MainActor
final class UKHostedTileFaceInkColourTests: XCTestCase {
    private func components(_ color: Color, _ style: UIUserInterfaceStyle = .light) -> [CGFloat] {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style)).getRed(&r, green: &g, blue: &b, alpha: &a)
        return [r, g, b, a]
    }

    private func components(_ rgb: HassRGB) -> [CGFloat] { components(Color(rgb)) }

    func testTheMutedGreyDiffersBetweenLightAndDark() {
        XCTAssertNotEqual(components(TileFaceInk.muted(appearance: .light)), components(TileFaceInk.muted(appearance: .dark)))
        XCTAssertEqual(components(TileFaceInk.muted(appearance: .dark)), components(TileFaceInk.mutedToken(appearance: .dark)), accuracy: 0.001)
        XCTAssertEqual(components(TileFaceInk.muted(appearance: .light)), components(TileFaceInk.mutedToken(appearance: .light)), accuracy: 0.001)
    }

    func testThePrimaryInkIsItsTokenForEveryFace() {
        let styles: [TileFaceStyle] = [.off, .lit, .filled(.occupancy), .tinted, .error, .colored(0x3366CC)]
        for style in styles {
            for appearance in [TileAppearance.dark, .light] {
                XCTAssertEqual(components(TileFaceInk.primary(style: style, appearance: appearance)),
                               components(TileFaceInk.primaryToken(style: style, appearance: appearance)), accuracy: 0.001)
                for enabled in [true, false] {
                    XCTAssertEqual(
                        components(TileFaceInk.glyph(style: style, appearance: appearance, finish: .solid, isEnabled: enabled, family: .occupancy, tintGlyph: .white)),
                        components(TileFaceInk.glyphToken(style: style, appearance: appearance, finish: .solid, isEnabled: enabled, family: .occupancy, tintGlyph: .white)),
                        accuracy: 0.001)
                }
            }
        }
    }

    func testTheSecondaryInkIsItsToken() {
        XCTAssertEqual(
            components(TileFaceInk.secondary(style: .off, appearance: .dark, finish: .solid, surface: .page, hasWash: false)),
            components(TileFaceInk.secondaryToken(style: .off, appearance: .dark, finish: .solid, surface: .page, hasWash: false)),
            accuracy: 0.001)
    }
}

private func XCTAssertEqual(_ a: [CGFloat], _ b: [CGFloat], accuracy: CGFloat, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(a.count, b.count, file: file, line: line)
    for (x, y) in zip(a, b) { XCTAssertEqual(x, y, accuracy: accuracy, file: file, line: line) }
}
