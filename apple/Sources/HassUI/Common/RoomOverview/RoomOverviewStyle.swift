import HassCore
import HassDesign
import SwiftUI

/// Tints and symbols shared by the overview and detail tiles.
enum RoomOverviewStyle {
    /// A kind's colour family (direction G, Colour families).
    static func family(_ kind: RoomOverviewKind) -> ColorFamily {
        switch kind {
        case .lights: .lights
        case .climate: .climate
        case .occupancy: .occupancy
        case .contacts: .contact
        case .airQuality: .air
        }
    }

    /// The icon tint for a kind's tiles: its family's glyph colour.
    static func tint(_ kind: RoomOverviewKind) -> Color { family(kind).glyph }

    /// Whether an active tile of this kind draws filled (lit for lights). Climate and air quality are "active"
    /// whenever they report, so their tiles stay dark with the family glyph, as in the mockups (n2 climate).
    static func isFilled(_ kind: RoomOverviewKind, active: Bool) -> Bool {
        switch kind {
        case .lights, .occupancy, .contacts: active
        case .climate, .airQuality: false
        }
    }

    /// Door or window, open or closed (web `ContactIcon`).
    static func contactSymbol(window: Bool, open: Bool) -> String {
        SymbolMap.symbol(for: window ? (open ? "mdi:window-open" : "mdi:window-closed") : (open ? "mdi:door-open" : "mdi:door"))
    }
}
