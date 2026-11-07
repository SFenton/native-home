import Foundation
@testable import HassDesign
import SwiftUI
import Testing

/// The room tile palette (`.agents/design/direction-g.md`, Colour: Room tiles): white ink passes 4.5:1 on every fill,
/// each room is its own colour, and none reads as a device family or an alarm mode.
struct RoomPaletteTests {
    private static let rooms = Array(RoomPalette.fills.indices)

    private func linear(_ value: Double) -> Double { value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }

    private func channels(_ rgb: UInt32) -> (Double, Double, Double) {
        (Double((rgb >> 16) & 0xFF) / 255, Double((rgb >> 8) & 0xFF) / 255, Double(rgb & 0xFF) / 255)
    }

    private func luminance(_ rgb: UInt32) -> Double {
        let (r, g, b) = channels(rgb)
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    private func contrastWithWhite(_ rgb: UInt32) -> Double { 1.05 / (luminance(rgb) + 0.05) }

    /// OKLab, the perceptual space the palette was tuned in.
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

    @Test func sixteenRoomsHaveAFill() {
        #expect(Self.rooms.count == 16)
        #expect(RoomPalette.fill(at: 6) == 0x547F12)
        #expect(RoomPalette.fill(at: nil) == nil)
        #expect(RoomPalette.fill(at: -1) == nil)
        #expect(RoomPalette.color(at: nil) == nil)
        #expect(RoomPalette.color(at: 2) != nil)
    }

    @Test func aPositionPastTheEndWraps() {
        #expect(RoomPalette.fill(at: 16) == RoomPalette.fill(at: 0))
        #expect(RoomPalette.fill(at: 19) == RoomPalette.fill(at: 3))
    }

    @Test(arguments: RoomPaletteTests.rooms)
    func whiteInkPassesBodyContrast(_ room: Int) throws {
        let fill = try #require(RoomPalette.fill(at: room))
        // Title, subtitle and the chevron are all white on a flat fill.
        #expect(contrastWithWhite(fill) >= 4.5, "\(room) \(String(fill, radix: 16)) is \(contrastWithWhite(fill)):1")
    }

    @Test func everyRoomIsItsOwnColour() throws {
        for (index, a) in Self.rooms.enumerated() {
            for b in Self.rooms[(index + 1)...] {
                let d = distance(try #require(RoomPalette.fill(at: a)), try #require(RoomPalette.fill(at: b)))
                #expect(d >= 0.05, "\(a) and \(b) are \(d) apart")
            }
        }
    }

    @Test func noRoomReusesADeviceFamilyOrASecurityMode() throws {
        let fills = ColorFamily.allCases.compactMap(\.spec.fill)
        #expect(fills.count >= 15)
        for room in Self.rooms {
            let fill = try #require(RoomPalette.fill(at: room))
            for family in fills {
                let d = distance(fill, family)
                #expect(d >= 0.04, "\(room) is \(d) from fill \(String(family, radix: 16))")
            }
        }
    }

    @Test func faceStyleIsColouredWhateverTheState() {
        let fill: UInt32 = 0x547F12
        #expect(TileFaceStyle.resolve(family: .neutral, isActive: false, isError: false, isUnavailable: false, solidFill: fill) == .colored(fill))
        #expect(TileFaceStyle.resolve(family: nil, isActive: true, isError: false, isUnavailable: false, solidFill: fill) == .colored(fill))
        #expect(TileFaceStyle.resolve(family: .neutral, isActive: false, isError: true, isUnavailable: false, solidFill: fill) == .error)
        #expect(TileFaceStyle.resolve(family: .neutral, isActive: false, isError: false, isUnavailable: true, solidFill: fill) == .off)
        #expect(TileFaceStyle.colored(fill).isColored)
        #expect(!TileFaceStyle.colored(fill).hasDarkInk)
        #expect(!TileFaceStyle.off.isColored)
    }
}
