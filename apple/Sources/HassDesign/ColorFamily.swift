import SwiftUI

/// A kind of device and the one colour it uses everywhere: tile glyphs, filled tiles and status chips
/// (`.agents/design/direction-g.md`, Colour families; owner, 2026-10-14: "codify some colors for device families,
/// occupancy, contact sensors, vents, etc so we have distinct tile colors throughout the app").
///
/// Off tiles stay dark with the glyph in ``glyph``, mixed toward grey. On tiles fill with ``fill`` and draw their
/// text in ``ink``. Lights have no fill: they use the warm lit tile. Red is never a family; alerts draw a red glyph
/// and state on whatever tile they belong to.
public enum ColorFamily: String, CaseIterable, Sendable {
    case lights
    /// Thermostats and bed sides while heating (the thermostat dial's heat, darkened for white text).
    case heating
    /// Thermostats and bed sides while cooling (the dial's cool, darkened for white text).
    case cooling
    case vents
    /// Fans, purifiers, bath fans and air quality (web air teal).
    case air
    /// Humidifiers and sprinklers.
    case water
    /// Presence and motion sensors (web presence green).
    case occupancy
    /// Contact sensors and the garage (the web's soft contact green).
    case contact
    /// TVs, remotes, consoles, PCs and speakers (web media pink).
    case media
    /// Vacuums, dishwasher and laundry.
    case cleaning
    /// Plugs, the towel rack and chargers: bright yellow with dark text.
    case power
    /// Grill and oven.
    case cooking
    /// Whole-home climate status (web navy with the yellow thermometer). Thermostat tiles use ``heating`` and
    /// ``cooling``.
    case climate
    /// Security by alarm mode, as on the web.
    case securityHome, securityAway, securityNight, securityDisarmed, securityTriggered
    /// The Chores quick-link tiles (owner, 2026-10-16: "header tiles for Chores sub-pages need distinct colours not
    /// reused elsewhere"). Ultramarine, magenta, raspberry, violet and chestnut: none within 0.05 (OKLab) of any device, security, Food or room fill.
    case choreResident1, choreResident2, choreUnassigned, choreHome, groceries
    /// The Food pages (owner, 2026-10-16: "Food Spaces / All Food should have colours like the web"). Each is the web's
    /// tile colour (`ha-sfenton-react-dash@9ac2a46:src/constants/everShelfFood.ts:13-18`, `FoodHubPage.tsx:46,60,69`)
    /// darkened (or, for the Fridge, Freezer, Spice Rack and Cabinet, nudged apart) until white text on it passes 4.5:1 and no two Food tiles read as one. They fill as a tile on the Food hub: the spaces are places, but the
    /// web gives each its own colour, and the hub is the only page that draws them.
    case pantry, fridge, freezer, spiceRack, cabinet
    /// All Food (the web's sage green, `rgba(88,128,94)`).
    case food
    /// All Recipes (the web's blue, `rgba(42,126,180)`, the same as the Fridge).
    case recipes
    /// Anything without a family: grey glyph, no fill.
    case neutral

    /// The family's sRGB values as `0xRRGGBB`, kept raw so tests can check contrast.
    public struct Spec: Sendable, Equatable {
        /// Glyph colour on dark tiles, chips and rows.
        public let glyph: UInt32
        /// On-tile fill, or nil for families that are never filled (lights use the lit tile; neutral).
        public let fill: UInt32?
        /// Whether text on ``fill`` is dark (power) rather than white.
        public let darkInk: Bool
    }

    /// The Chores quick-link families, in tile order.
    public static let choreFamilies: [ColorFamily] = [.choreResident1, .choreResident2, .choreUnassigned, .choreHome, .groceries]

    /// The raw values (direction-g.md table).
    public var spec: Spec {
        switch self {
        case .lights: Spec(glyph: 0xFF9630, fill: nil, darkInk: true)
        case .heating: Spec(glyph: 0xFF7A2F, fill: 0xA8440A, darkInk: false)
        case .cooling: Spec(glyph: 0x3FC6D2, fill: 0x1B6F78, darkInk: false)
        case .vents: Spec(glyph: 0x8FA8FF, fill: 0x3B58B8, darkInk: false)
        case .air: Spec(glyph: 0x2FD3C1, fill: 0x006E62, darkInk: false)
        case .water: Spec(glyph: 0x4CC9F0, fill: 0x076C91, darkInk: false)
        case .occupancy: Spec(glyph: 0x5BD16A, fill: 0x2A732E, darkInk: false)
        case .contact: Spec(glyph: 0x7ED787, fill: 0x3B523E, darkInk: false)
        case .media: Spec(glyph: 0xFF7AA8, fill: 0xA03A61, darkInk: false)
        case .cleaning: Spec(glyph: 0xC88CFA, fill: 0x7A3FB0, darkInk: false)
        case .power: Spec(glyph: 0xFFD60A, fill: 0xFFD60A, darkInk: true)
        case .cooking: Spec(glyph: 0xFF8A4C, fill: 0xA8420E, darkInk: false)
        case .climate: Spec(glyph: 0xFFCC00, fill: 0x195482, darkInk: false)
        case .securityHome: Spec(glyph: 0x64B0FF, fill: 0x1565C0, darkInk: false)
        case .securityAway: Spec(glyph: 0xFF6961, fill: 0xC62828, darkInk: false)
        case .securityNight: Spec(glyph: 0xD08CF0, fill: 0x7B1FA2, darkInk: false)
        case .securityDisarmed: Spec(glyph: 0x5BD16A, fill: 0x2A732E, darkInk: false)
        case .securityTriggered: Spec(glyph: 0xFF6961, fill: 0xD70015, darkInk: false)
        case .choreResident1: Spec(glyph: 0x8FA0FF, fill: 0x0022CC, darkInk: false)
        case .choreResident2: Spec(glyph: 0xFF8CF7, fill: 0xB410AE, darkInk: false)
        case .choreUnassigned: Spec(glyph: 0xFF8FBF, fill: 0xC2127A, darkInk: false)
        case .choreHome: Spec(glyph: 0xB98CFF, fill: 0x6600CC, darkInk: false)
        case .groceries: Spec(glyph: 0xE0916F, fill: 0x802200, darkInk: false)
        case .pantry: Spec(glyph: 0xAC8F6B, fill: 0x855A25, darkInk: false)
        case .fridge, .recipes: Spec(glyph: 0x639AB6, fill: 0x196B94, darkInk: false)
        case .freezer: Spec(glyph: 0x8292C5, fill: 0x2F4A9E, darkInk: false)
        case .spiceRack: Spec(glyph: 0xC5826C, fill: 0xAA4727, darkInk: false)
        case .cabinet: Spec(glyph: 0x9A928B, fill: 0x6A5F55, darkInk: false)
        case .food: Spec(glyph: 0x849A87, fill: 0x4A6B4E, darkInk: false)
        case .neutral: Spec(glyph: 0x8E8E93, fill: nil, darkInk: false)
        }
    }

    /// The glyph on a light sheet: ``Spec/glyph`` darkened until it is at least 3:1 (WCAG 1.4.11, non-text) on the
    /// white cell and on the sheet ground `#F2F2F7`, keeping its hue. (The dark values are 1.5–2.7:1 on white.)
    public var glyphLightRGB: UInt32 {
        switch self {
        case .lights: 0xBD6F24
        case .heating: 0xCF6326
        case .cooling: 0x2D8F97
        case .vents: 0x6D80C2
        case .air: 0x209285
        case .water: 0x358DA8
        case .occupancy, .securityDisarmed: 0x40924A
        case .contact: 0x54905A
        case .media: 0xC96085
        case .cleaning: 0x9C6DC3
        case .power: 0x998006
        case .cooking: 0xC46A3B
        case .climate: 0x9E7E00
        case .securityHome: 0x4C86C2
        case .securityAway, .securityTriggered: 0xD95952
        case .securityNight: 0xA26DBB
        case .choreResident1: 0x0022CC
        case .choreResident2: 0xB410AE
        case .choreUnassigned: 0xC2127A
        case .choreHome: 0x6600CC
        case .groceries: 0x802200
        case .pantry: 0xA28665
        case .fridge, .recipes: 0x5D91AB
        case .freezer: 0x7A89B9
        case .spiceRack: 0xB97A66
        case .cabinet: 0x918983
        case .food: 0x7B8F7E
        case .neutral: 0x818186
        }
    }

    /// The glyph colour for an appearance, as `0xRRGGBB`.
    public func glyphRGB(_ scheme: ColorScheme) -> UInt32 {
        scheme == .light ? glyphLightRGB : spec.glyph
    }

    /// The off glyph for an appearance: the glyph mixed 72% with grey (system grey on dark, `#6C6C70` on light so the
    /// mix keeps 3:1 on white), so the kind of device stays visible without reading as on.
    /// - Parameter keep: How much of the family colour the mix keeps (0.72 shipped). Tinted glass keeps more
    ///   (``TileFinish/offGlyphKeep``) because its off ground is a little lighter.
    public func offGlyphRGB(_ scheme: ColorScheme, keep: Double = 0.72) -> UInt32 {
        scheme == .light
            ? Self.mix(glyphLightRGB, Self.offGreyLight, keep)
            : Self.mix(spec.glyph, Self.offGreyDark, keep)
    }

    private static let offGreyDark: UInt32 = 0x8E8E93
    private static let offGreyLight: UInt32 = 0x6C6C70

    /// Glyph colour on the surface it is drawn on: the dark value on pages and dark sheets, ``glyphLightRGB`` in a light
    /// sheet. Not for a fixed fill (a filled button, a chip): use `Color(rgb: spec.glyph)` there.
    public var glyph: Color { Self.adaptiveGlyphColors[self] ?? .gray }

    /// ``glyph`` as raw sRGB.
    public var glyphToken: HassRGB { Self.adaptiveGlyphs[self] ?? HassRGB(rgb: 0x808080) }

    /// Glyph colour on an off tile: the family colour mixed 72% with grey, so the kind of device stays visible without
    /// reading as on. Adapts like ``glyph``.
    public var offGlyph: Color { Self.adaptiveOffGlyphColors[self] ?? .gray }

    /// ``offGlyph`` as raw sRGB.
    public var offGlyphToken: HassRGB { Self.adaptiveOffGlyphs[self] ?? HassRGB(rgb: 0x808080) }

    /// Built once per family: a dynamic colour is a new object each time it is made, so views and tests that compare
    /// two reads of ``glyph`` need the same instance.
    private static let adaptiveGlyphs: [ColorFamily: HassRGB] = Dictionary(
        uniqueKeysWithValues: allCases.map { ($0, HassRGB.adaptive(light: $0.glyphLightRGB, dark: $0.spec.glyph)) })
    private static let adaptiveOffGlyphs: [ColorFamily: HassRGB] = Dictionary(
        uniqueKeysWithValues: allCases.map { ($0, HassRGB.adaptive(light: $0.offGlyphRGB(.light), dark: $0.offGlyphRGB(.dark))) })

    private static let adaptiveGlyphColors: [ColorFamily: Color] = adaptiveGlyphs.mapValues { Color($0) }
    private static let adaptiveOffGlyphColors: [ColorFamily: Color] = adaptiveOffGlyphs.mapValues { Color($0) }

    /// The on-tile fill, or nil when the family is never filled.
    public var fill: Color? { fillToken.map { Color($0) } }

    /// ``fill`` as raw sRGB.
    public var fillToken: HassRGB? { spec.fill.map { HassRGB(rgb: $0) } }

    /// Title and glyph colour on ``fill``.
    public var ink: Color { Color(inkToken) }

    /// ``ink`` as raw sRGB.
    public var inkToken: HassRGB { spec.darkInk ? HassRGB(rgb: 0x1C1C1E) : .white }

    /// Supporting text on ``fill``: white at 92% (4.5:1 or better on every fill), or a dark olive on power.
    public var secondaryInk: Color { Color(secondaryInkToken) }

    /// ``secondaryInk`` as raw sRGB.
    public var secondaryInkToken: HassRGB { spec.darkInk ? HassRGB(rgb: 0x282000).opacity(0.82) : HassRGB.white.opacity(0.92) }

    // MARK: Status chips

    /// An active status chip's fill (direction-g.md, "Status chips follow the web"): the family fill, except
    /// lights, whose chip is amber where its tile is the lit tile. Nil for families that have no chip fill.
    public var chipFillRGB: UInt32? {
        self == .lights ? 0x7A4A00 : spec.fill
    }

    /// An active status chip's glyph: orange on the amber lights chip, yellow on climate's navy, the family's
    /// own green on the soft contact green, teal for air; white on every other fill.
    public var chipGlyphRGB: UInt32 {
        switch self {
        case .lights, .climate, .contact, .air: spec.glyph
        default: 0xFFFFFF
        }
    }

    /// The security family for an alarm panel state (web `alarmColor`), or nil while it is arming, pending or
    /// unknown.
    public static func security(alarmState: String?) -> ColorFamily? {
        switch alarmState {
        case "armed_home": .securityHome
        case "armed_away": .securityAway
        case "armed_night": .securityNight
        case "disarmed": .securityDisarmed
        case "triggered": .securityTriggered
        default: nil
        }
    }

    /// Mixes two `0xRRGGBB` colours: `amount` of `a`, the rest `b`.
    static func mix(_ a: UInt32, _ b: UInt32, _ amount: Double) -> UInt32 {
        func channel(_ shift: UInt32) -> UInt32 {
            let ca = Double((a >> shift) & 0xFF), cb = Double((b >> shift) & 0xFF)
            return UInt32((ca * amount + cb * (1 - amount)).rounded()) << shift
        }
        return channel(16) | channel(8) | channel(0)
    }
}
