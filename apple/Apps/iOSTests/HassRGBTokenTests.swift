import HassCore
import HassDesign
import SwiftUI
import UIKit
import XCTest
@testable import HassUI

/// The UIKit port draws design tokens from raw ``HassRGB``; SwiftUI draws the `Color` derived from the same value. These tests
/// resolve both for every converted token in light and dark, with and without Increase Contrast, and require the same sRGB
/// components within 1/255, so the two apps cannot drift apart.
final class HassRGBTokenTests: XCTestCase {
    private static let traitSets: [UITraitCollection] = [UIUserInterfaceStyle.light, .dark].flatMap { style in
        [UIAccessibilityContrast.normal, .high].map { contrast in
            UITraitCollection(traitsFrom: [UITraitCollection(userInterfaceStyle: style), UITraitCollection(accessibilityContrast: contrast)])
        }
    }

    private func components(_ color: UIColor, _ traits: UITraitCollection) -> [CGFloat] {
        var (r, g, b, a): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        color.resolvedColor(with: traits).getRed(&r, green: &g, blue: &b, alpha: &a)
        return [r, g, b, a]
    }

    private func check(_ name: String, _ color: Color, _ token: HassRGB, file: StaticString = #filePath, line: UInt = #line) {
        for traits in Self.traitSets {
            let swiftUI = components(UIColor(color), traits), raw = components(UIColor(token), traits)
            for (index, pair) in zip(swiftUI, raw).enumerated() {
                XCTAssertEqual(pair.0, pair.1, accuracy: 1.0 / 255, "\(name) channel \(index) in \(traits.userInterfaceStyle.rawValue)/\(traits.accessibilityContrast.rawValue)", file: file, line: line)
            }
        }
    }

    func testHassTokens() {
        typealias T = HassTokens
        let tint: [(String, Color, HassRGB)] = [
            ("light", T.Tint.light, T.RGB.Tint.light), ("security", T.Tint.security, T.RGB.Tint.security),
            ("climate", T.Tint.climate, T.RGB.Tint.climate), ("presence", T.Tint.presence, T.RGB.Tint.presence),
            ("contact", T.Tint.contact, T.RGB.Tint.contact), ("air", T.Tint.air, T.RGB.Tint.air),
            ("vacuum", T.Tint.vacuum, T.RGB.Tint.vacuum), ("warning", T.Tint.warning, T.RGB.Tint.warning),
            ("slate", T.Tint.slate, T.RGB.Tint.slate), ("heat", T.Tint.heat, T.RGB.Tint.heat),
            ("cool", T.Tint.cool, T.RGB.Tint.cool), ("water", T.Tint.water, T.RGB.Tint.water),
            ("settingsSwitch", T.Tint.settingsSwitch, T.RGB.Tint.settingsSwitch),
            ("settingsControl", T.Tint.settingsControl, T.RGB.Tint.settingsControl),
        ]
        let ink: [(String, Color, HassRGB)] = [
            ("primary", T.Ink.primary, T.RGB.Ink.primary), ("secondary", T.Ink.secondary, T.RGB.Ink.secondary),
            ("onDark", T.Ink.onDark, T.RGB.Ink.onDark), ("onDarkSecondary", T.Ink.onDarkSecondary, T.RGB.Ink.onDarkSecondary),
            ("error", T.Ink.error, T.RGB.Ink.error), ("danger", T.Ink.danger, T.RGB.Ink.danger),
            ("warning", T.Ink.warning, T.RGB.Ink.warning), ("action", T.Ink.action, T.RGB.Ink.action),
            ("success", T.Ink.success, T.RGB.Ink.success), ("onSuccessFill", T.Ink.onSuccessFill, T.RGB.Ink.onSuccessFill),
            ("unavailable", T.Ink.unavailable, T.RGB.Ink.unavailable), ("actionFill", T.Ink.actionFill, T.RGB.Ink.actionFill),
            ("onFamilyFill", T.Ink.onFamilyFill, T.RGB.Ink.onFamilyFill), ("badge", T.Ink.badge, T.RGB.Ink.badge),
            ("trackNormal", T.Ink.track(increasedContrast: false), T.RGB.Ink.track(increasedContrast: false)),
            ("trackHigh", T.Ink.track(increasedContrast: true), T.RGB.Ink.track(increasedContrast: true)),
        ]
        let surface: [(String, Color, HassRGB)] = [
            ("sheetGround", T.Surface.sheetGround, T.RGB.Surface.sheetGround), ("sheetCell", T.Surface.sheetCell, T.RGB.Surface.sheetCell),
            ("moduleThin", T.Surface.moduleThin, T.RGB.Surface.moduleThin), ("moduleDense", T.Surface.moduleDense, T.RGB.Surface.moduleDense),
            ("separator", T.Surface.separator, T.RGB.Surface.separator),
            ("secondaryOnModule", T.Surface.secondaryOnModule, T.RGB.Surface.secondaryOnModule),
            ("secondaryOnWash", T.Surface.secondaryOnWash, T.RGB.Surface.secondaryOnWash),
            ("secondaryOnWallpaper", T.Surface.secondaryOnWallpaper, T.RGB.Surface.secondaryOnWallpaper),
            ("secondaryInSheet", T.Surface.secondaryInSheet, T.RGB.Surface.secondaryInSheet),
            ("selectedSegment", T.Surface.selectedSegment, T.RGB.Surface.selectedSegment),
            ("selectedSegmentInk", T.Surface.selectedSegmentInk, T.RGB.Surface.selectedSegmentInk),
        ]
        for (name, color, token) in tint + ink + surface { check(name, color, token) }
        // The raw values equal the system colours they stand for.
        for traits in Self.traitSets {
            assertComponents(components(UIColor(T.RGB.Ink.primary), traits), components(.label, traits), accuracy: 1.0 / 255)
        }
    }

    func testColorFamilyAndFixedPalettes() {
        for family in ColorFamily.allCases {
            check("\(family) glyph", family.glyph, family.glyphToken)
            check("\(family) offGlyph", family.offGlyph, family.offGlyphToken)
            check("\(family) ink", family.ink, family.inkToken)
            check("\(family) secondaryInk", family.secondaryInk, family.secondaryInkToken)
            if let fill = family.fill, let token = family.fillToken { check("\(family) fill", fill, token) }
        }
        check("lit bandTop", LitTile.bandTop, LitTile.bandTopToken)
        check("lit bandBottom", LitTile.bandBottom, LitTile.bandBottomToken)
        check("lit base", LitTile.base, LitTile.baseToken)
        check("lit glyph", LitTile.glyph, LitTile.glyphToken)
        check("lit ink", LitTile.ink, LitTile.inkToken)
        check("lit secondaryInk", LitTile.secondaryInk, LitTile.secondaryInkToken)
        check("lit powerTop", LitTile.powerTop, LitTile.powerTopToken)
        check("room ink", RoomPalette.ink, RoomPalette.inkToken)
        check("fab tint", FloatingActionBar.tint, FloatingActionBar.tintToken)
        check("fab activeTint", FloatingActionBar.activeTint, FloatingActionBar.activeTintToken)
        check("fab activeGlyph", FloatingActionBar.activeGlyph, FloatingActionBar.activeGlyphToken)
        check("dial heat", ThermostatDialPalette.heat, ThermostatDialPalette.heatToken)
        check("dial cool", ThermostatDialPalette.cool, ThermostatDialPalette.coolToken)
        check("dial rim", ThermostatDialPalette.markerRim, ThermostatDialPalette.markerRimToken)
        check("dial neutral", ThermostatDialPalette.neutral, ThermostatDialPalette.neutralToken)
        for tone in [StatusPill.Tone.neutral, .ok, .active, .warning, .danger, .unavailable] {
            check("pill \(tone)", StatusPill.color(tone), StatusPill.colorToken(tone))
        }
    }

    private func assertComponents(_ a: [CGFloat], _ b: [CGFloat], accuracy: CGFloat, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.count, b.count, file: file, line: line)
        for (x, y) in zip(a, b) { XCTAssertEqual(x, y, accuracy: accuracy, file: file, line: line) }
    }
}
