import Foundation
@testable import HassDesign
import SwiftUI
import Testing

/// The Quick Links tile colours (`.agents/design/direction-g.md`, Colour: Quick Links tiles): every link has a solid fill that
/// white passes 4.5:1 on, links reuse their page's colour family, and no two links on the sheet read as one.
struct QuickLinkPaletteTests {
    private static let alarmStates: [String?] = ["armed_home", "armed_away", "armed_night", "disarmed", "triggered", "arming", nil]

    private func linear(_ value: Double) -> Double { value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }

    private func channels(_ rgb: UInt32) -> (Double, Double, Double) {
        (Double((rgb >> 16) & 0xFF) / 255, Double((rgb >> 8) & 0xFF) / 255, Double(rgb & 0xFF) / 255)
    }

    private func contrastWithWhite(_ rgb: UInt32) -> Double {
        let (r, g, b) = channels(rgb)
        return 1.05 / (0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b) + 0.05)
    }

    private func oklab(_ rgb: UInt32) -> (Double, Double, Double) {
        let (r, g, b) = channels(rgb)
        let (lr, lg, lb) = (linear(r), linear(g), linear(b))
        let l = cbrt(0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb)
        let m = cbrt(0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb)
        let s = cbrt(0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb)
        return (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
    }

    private func distance(_ a: UInt32, _ b: UInt32) -> Double {
        let (x, y) = (oklab(a), oklab(b))
        return (pow(x.0 - y.0, 2) + pow(x.1 - y.1, 2) + pow(x.2 - y.2, 2)).squareRoot()
    }

    @Test func everyLinkHasAFillAndOtherIDsHaveNone() {
        for id in QuickLinkPalette.linkIDs { #expect(QuickLinkPalette.fill(forLink: id) != nil, "\(id)") }
        #expect(QuickLinkPalette.fill(forLink: "chores") == nil)
        #expect(QuickLinkPalette.linkIDs.count == 7)
    }

    @Test func linksReuseTheirPagesColourFamily() {
        #expect(QuickLinkPalette.fill(forLink: "food") == ColorFamily.food.spec.fill)
        #expect(QuickLinkPalette.fill(forLink: "vacuums") == ColorFamily.cleaning.spec.fill)
        #expect(QuickLinkPalette.fill(forLink: "media") == ColorFamily.media.spec.fill)
        #expect(QuickLinkPalette.fill(forLink: "sprinklers") == ColorFamily.water.spec.fill)
        #expect(QuickLinkPalette.fill(forLink: "custom-lights") == ColorFamily.lights.chipFillRGB)
    }

    @Test func securityFollowsTheAlarmModeAndHidesItWhenRedacted() {
        #expect(QuickLinkPalette.fill(forLink: "security-system", alarmState: "armed_away") == ColorFamily.securityAway.spec.fill)
        #expect(QuickLinkPalette.fill(forLink: "security-system", alarmState: "disarmed") == ColorFamily.securityDisarmed.spec.fill)
        #expect(QuickLinkPalette.fill(forLink: "security-system", alarmState: "arming") == QuickLinkPalette.securityUnknown)
        #expect(QuickLinkPalette.fill(forLink: "security-system", alarmState: "armed_away", isRedacted: true)
            == QuickLinkPalette.securityUnknown)
    }

    @Test(arguments: QuickLinkPaletteTests.alarmStates)
    func whiteInkPassesBodyContrastOnEveryFill(_ alarm: String?) throws {
        for id in QuickLinkPalette.linkIDs {
            let fill = try #require(QuickLinkPalette.fill(forLink: id, alarmState: alarm))
            #expect(contrastWithWhite(fill) >= 4.5, "\(id) \(String(fill, radix: 16)) is \(contrastWithWhite(fill)):1")
        }
    }

    @Test(arguments: QuickLinkPaletteTests.alarmStates)
    func noTwoLinksOnTheSheetReadAsOne(_ alarm: String?) throws {
        let fills = try QuickLinkPalette.linkIDs.map { try #require(QuickLinkPalette.fill(forLink: $0, alarmState: alarm)) }
        for (index, a) in fills.enumerated() {
            for (other, b) in fills.enumerated() where other > index {
                #expect(distance(a, b) >= 0.05, "\(QuickLinkPalette.linkIDs[index]) and \(QuickLinkPalette.linkIDs[other]) are \(distance(a, b)) apart")
            }
        }
    }

    @Test func roomsIsItsOwnColour() {
        for (room, fill) in RoomPalette.fills.enumerated() { #expect(distance(QuickLinkPalette.rooms, fill) >= 0.05, "\(room)") }
        for family in ColorFamily.allCases {
            guard let fill = family.spec.fill else { continue }
            #expect(distance(QuickLinkPalette.rooms, fill) >= 0.05, "\(family)")
        }
    }
}
