import Foundation

/// A glyph id from the app's own set (`symbol` in the attributes, `icon` in a problem). The wire never carries an SF
/// Symbol name: the engine names a glyph and this build draws it (`FentonActivityViews`), so a newer engine can ask for a
/// glyph an older app does not know and still get ``generic``.
public enum ActivityGlyph: String, Hashable, Sendable, CaseIterable {
    // MARK: Jobs
    case fan, dishwasher, dryer, washer, vacuum
    case hotFlash = "hot_flash"
    case generic

    // MARK: Problems (`.agents/platforms/apple/live-activities-per-job.md` §5)
    /// A stop or a general alarm.
    case alert
    /// A closed door in the way.
    case door
    /// The dock.
    case dock
    /// A drop or ramp.
    case edge
    /// A brush.
    case brush
    /// Battery.
    case battery
    /// The clean water tank.
    case water
    /// The wastewater tank.
    case waste
    /// Mop pads.
    case mop
    /// The dust bag and the dock cover.
    case bag
    /// An error we have no words for.
    case question
    /// The dishwasher's door or display.
    case doorDish = "door_dish"

    /// The glyph for a wire id; an unknown id reads ``generic``.
    public init(wire: String?) {
        self = wire.flatMap(ActivityGlyph.init(rawValue:)) ?? .generic
    }

    /// The glyph for an attribute: its `symbol` when this build knows it, else the one for its `kind`, else ``generic``.
    public init(symbol: String, kind: String) {
        if let known = ActivityGlyph(rawValue: symbol) {
            self = known
        } else {
            self = ActivityGlyph(rawValue: kind) ?? Self.kindDefault(kind)
        }
    }

    private static func kindDefault(_ kind: String) -> ActivityGlyph {
        switch kind {
        case "bathroom_fan": .fan
        case "problem": .alert
        default: .generic
        }
    }

    /// Every glyph a problem can name (the §5 table).
    public static let problemSet: [ActivityGlyph] = [.alert, .door, .dock, .edge, .brush, .battery, .water, .waste, .mop, .bag, .question, .doorDish]
    /// Every glyph a job can name.
    public static let jobSet: [ActivityGlyph] = [.fan, .dishwasher, .dryer, .washer, .vacuum, .hotFlash, .generic]
}
