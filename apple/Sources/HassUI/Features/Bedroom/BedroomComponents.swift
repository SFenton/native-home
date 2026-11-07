import HassCore
import HassDesign
import SwiftUI

/// Colors and small views shared by the wake-light and bed sheets. Tiles and buttons use the direction G pieces
/// (`ColorFamily`, `PrimaryButtonStyle`); cards sit on the sheet's cell colour.
enum BedroomStyle {
    /// Stop and Delete fills: a deep red that keeps white labels at about 6:1 (system red gives 3.6:1 and fails the audit).
    static let danger = Color(red: 0.76, green: 0.12, blue: 0.12)

    /// A bed side's tile face (direction G, Colour families: Heating and Cooling): filled while heating or cooling,
    /// and idle or off keep the family glyph on the dark face (Cooling when the level is below zero).
    static func face(action: String, level: Double?, isAvailable: Bool) -> ThermostatTileFace {
        ThermostatTileFace.bedSide(action: action, level: level, isAvailable: isAvailable)
    }

    /// A card on the sheet's cell colour (direction G, Layers: Sheets).
    static func card(_ content: some View) -> some View {
        content
            .padding(HassTokens.Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(HassTokens.Surface.sheetCell, in: RoundedRectangle(cornerRadius: HassTokens.Radius.tile, style: .continuous))
    }
}

/// An `HH:MM` time bound to a wheel/compact `DatePicker`.
struct ClockTimeField {
    var title: String
    var identifier: String



    static func date(_ value: String, calendar: Calendar = .current) -> Date {
        let parts = value.split(separator: ":").compactMap { Int($0) }
        var components = calendar.dateComponents([.year, .month, .day], from: .now)
        components.hour = parts.first ?? 7
        components.minute = parts.count > 1 ? parts[1] : 0
        return calendar.date(from: components) ?? .now
    }

    static func string(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        // A stored `HH:MM` value, so ASCII digits whatever the locale.
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
}
