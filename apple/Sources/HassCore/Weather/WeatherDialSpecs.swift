import Foundation

// MARK: - The weather panel's dials as documents

/// The weather panel's compass, barometer and sun arc, written as the generic `dial` and `arc-track` an author would write (`sh.dial@1`,
/// `sh.arc-track@1`), so the panel draws through the app's one dial (`UKDialView`, `UKArcTrackView`) and not through three hand-drawn views.
///
/// Each function gives the same numbers the hand-drawn views had: the compass is 104 pt scaled with the footnote size up to 160, 48 ticks with the
/// north one a flag, four letters and a needle; the barometer is 49 ticks over 250 degrees from 145 with one lit, 1.4 wide to 1 tall with its centre
/// 0.56 down; the sun arc is a dashed curve over a horizon in a 100 by 48 box, 200 pt at most. The inks are the panel's: white (`HassTokens.Ink.onDark`)
/// and its opacities, the amber of the needle and the pressure tick, and the yellow of the sun.
public enum WeatherDialSpecs {
    // MARK: Inks

    private static func white(_ alpha: Double = 1) -> ServerUIInk {
        .init(.init(rgb: .init(red: 255, green: 255, blue: 255), alpha: alpha))
    }

    /// The needle and the pressure tick (`UKWeatherInk.amber`: 1, 0.82, 0.30).
    public static let amber = ServerUIInk(.init(rgb: .init(red: 255, green: 209, blue: 77)))
    /// The sun's marker (1, 0.85, 0.30).
    public static let sun = ServerUIInk(.init(rgb: .init(red: 255, green: 217, blue: 77)))

    private static func node(_ id: String) -> ServerUICompositionDocument.Node { .init(id: id, title: id, span: 1) }

    private static func look(weight: ServerUITextLook.Weight? = nil, digits: ServerUITextLook.Digits? = nil, shrinks: Bool = false, ink: ServerUIInk) -> ServerUITextLook {
        var look = ServerUITextLook()
        look.weight = weight
        look.digits = digits
        look.ink = ink
        look.lines = 1
        look.overflow = shrinks ? nil : .truncate
        look.align = .center
        look.isDeclared = true
        return look
    }

    // MARK: Compass

    /// The wind compass: a needle that points where the wind blows to, with a dot at the side it comes from. The needle's reading is the bearing in
    /// degrees, and E and W are drawn only with one.
    public static func compass() -> ServerUIDial {
        ServerUIDial(
            node: node("weather-compass"), sweep: .init(start: -90, length: 360), scale: .degrees,
            size: .init(points: 104, relativeTo: .footnote, maxPoints: 160),
            ticks: .init(ring: .init(count: 48, inner: 0.80, outer: 0.92, alternateInner: 0.85, skip: [0]), width: 1.2, ink: white(0.55)),
            pointer: .needle(value: .literal(.number(0)), ink: amber, tailInk: white(0.55), dotInk: white(), animates: true),
            labels: .init(ink: white(), items: [.init(at: 0, text: "N"), .init(at: 0.25, text: "E", needsValue: true),
                                                .init(at: 0.5, text: "S"), .init(at: 0.75, text: "W", needsValue: true)]),
            flag: .init(at: 0, ink: white()))
    }

    // MARK: Barometer

    /// The barometer: one lit tick at the pressure's share of 970 to 1050 hPa (0 to 100), with the value and its unit in the middle, half the height down and 4 pt below, where the hand-built view put them.
    /// - Parameter hasUnit: Whether a second line, the unit, is drawn.
    public static func barometer(hasUnit: Bool) -> ServerUIDial {
        var lines = [ServerUIDial.Line(value: .literal(""), style: .title3, unavailableText: "-",
                                       look: look(weight: .bold, digits: .monospaced, shrinks: true, ink: white()))]
        if hasUnit {
            lines.append(.init(value: .literal(""), style: .caption1, unavailableText: "-", look: look(ink: white(0.85))))
        }
        return ServerUIDial(
            node: node("weather-barometer"), sweep: .init(start: 145, length: 250), scale: .percent, aspect: 1.4, centerY: 0.56,
            ticks: .init(ring: .init(count: 49, inner: 0.78, outer: 0.92), width: 1.4, ink: white(0.5)),
            pointer: .tick(value: .literal(.number(0)), inner: 0.70, outer: 0.98, width: 3, ink: amber), center: lines,
            textPlace: .init(share: 0.5, offset: 4))
    }

    // MARK: Sun arc

    /// The daylight arc: a dashed curve over a horizon with the sun at its progress (0 to 100).
    public static func sunArc() -> ServerUIArcTrack {
        ServerUIArcTrack(
            node: node("weather-sun-arc"), curve: .init(from: .init(8, 40), control: .init(50, 4), to: .init(92, 40)),
            box: .init(width: 100, height: 48), maxWidth: 200, ink: white(0.6), width: 2, dash: .init(stroke: 3, gap: 4),
            horizon: .init(line: .init(from: .init(4, 40), to: .init(96, 40)), ink: white(0.35), width: 1),
            progress: .literal(.number(0)), scale: .percent, marker: .init(size: 10, ink: sun), mirrors: false)
    }
}
