import FentonActivityModel
import SwiftUI

extension ActivityGlyph {
    /// The SF Symbol this build draws for the glyph id. The wire carries ids, never symbol names, so the set can change
    /// here without a relay update.
    var symbolName: String {
        switch self {
        case .fan: "fan.fill"
        case .dishwasher: "dishwasher.fill"
        case .dryer: "dryer.fill"
        case .washer: "washer.fill"
        case .vacuum: Self.vacuumSymbol
        case .hotFlash: "thermometer.snowflake"
        case .generic: "circle.dashed"
        case .alert: "exclamationmark"
        case .door: "door.left.hand.closed"
        case .dock: "bolt.horizontal.fill"
        case .edge: "arrow.down.to.line"
        case .brush: "scribble"
        case .battery: "battery.25percent"
        case .water: "drop.fill"
        case .waste: "trash.fill"
        case .mop: "water.waves"
        case .bag: "bag.fill"
        case .question: "questionmark"
        case .doorDish: "door.left.hand.open"
        }
    }

    /// The robot vacuum symbol arrived with iOS 18; earlier systems get sparkles.
    private static var vacuumSymbol: String {
        if #available(iOS 18.0, macOS 15.0, watchOS 11.0, *) { return "robotic.vacuum" }
        return "sparkles"
    }
}

/// A glyph, sized and coloured, hidden from VoiceOver (the card's own label says what it is).
struct ActivityGlyphImage: View {
    let glyph: ActivityGlyph
    var size: CGFloat
    var color: Color
    var weight: Font.Weight = .semibold

    var body: some View {
        Image(systemName: glyph.symbolName)
            .font(.system(size: size, weight: weight))
            .foregroundStyle(color)
            .accessibilityHidden(true)
    }
}
