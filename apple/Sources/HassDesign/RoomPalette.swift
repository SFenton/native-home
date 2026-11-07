import SwiftUI

/// One colour per room for navigation tiles (the Rooms grid, Climate's Advanced Controls rooms): a solid fill with a
/// white, filled glyph and white text (`.agents/design/direction-g.md`, Colour: Room tiles; owner, 2026-10-16: "room
/// tiles don't have nice colours, and icons should be filled/white").
///
/// **Source.** The web colours every room card from `AREA_ITEMS`
/// (`ha-sfenton-react-dash@f5a7bf9:src/constants/atAGlance.ts:324-340`) as `rgb(color / 0.6)` under white text
/// (`src/components/core/Card.module.css`, `.card`). Those raw values are not usable as tile fills: composited the
/// way the web draws them, seven of the sixteen miss 4.5:1 with white (Downstairs Hallway 2.9:1, Entryway 3.3:1,
/// Living Room 3.6:1) and Cinema Room is `rgb(0 0 1)`, which is invisible on a dark tile. Each room here keeps its web
/// hue and is moved to a lightness where white holds at least 4.7:1, a chroma that reads as a colour, and a distance
/// of at least 0.05 (OKLab) from every other room and from every colour family and security mode fill, so a room
/// never reads as a device or as an alarm state. Cinema Room (web black) and Master Bathroom (web grey) have no hue
/// to keep and take a deep plum and a slate.
///
/// Fixed fills with fixed inks: the tile looks the same on a page and in a light or dark sheet.
public enum RoomPalette {
    /// The fill for the room at `index` in the house document's room list, as `0xRRGGBB`; an index past the sixteenth wraps. Nil for
    /// a nil index (a path that is not a room).
    public static func fill(at index: Int?) -> UInt32? {
        guard let index, index >= 0 else { return nil }
        return fills[index % fills.count]
    }

    /// The fill as a colour.
    public static func color(at index: Int?) -> Color? { fill(at: index).map { Color(rgb: $0) } }

    /// Ink on every fill: white.
    public static let ink = Color(inkToken)

    /// ``ink`` as raw sRGB.
    public static let inkToken = HassRGB.white

    /// The sixteen fills in the document's room order (the web's `AREA_ITEMS` order, the Rooms grid's default). The palette
    /// names no room: a room takes the fill at its position, so the colours stay with the rooms while the document keeps its order.
    public static let fills: [UInt32] = [
        0x8A6F44, 0x0D8457, 0xAF5F00, 0x3E3EB7, 0x007E94, 0x72492D, 0x547F12, 0x901E79,
        0xA6222C, 0x453057, 0x195E20, 0x637145, 0x407B6E, 0x59596F, 0x975B46, 0x7D7200,
    ]
}
