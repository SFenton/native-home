import SwiftUI

/// Thermostat colors from the web (`DashboardViewPage.tsx` `THERMOSTAT_*_COLOR`).
public enum ThermostatDialPalette {
    /// Heating and the heat-to handle (`#cd5401`).
    public static let heat = Color(heatToken)
    /// Cooling and the cool-to handle (`#2c8e98`).
    public static let cool = Color(coolToken)
    /// The current-temperature marker's rim: near-black in light and dark mode so it never looks like a handle.
    public static let markerRim = Color(markerRimToken)
    /// Idle (web: 78% white; here the adaptive secondary ink so it reads in light mode too).
    public static let neutral = Color(neutralToken)

    public static let heatToken = HassTokens.RGB.Tint.heat
    public static let coolToken = HassTokens.RGB.Tint.cool
    public static let markerRimToken = HassRGB(red: 0.08, green: 0.08, blue: 0.08)
    public static let neutralToken = HassTokens.RGB.Ink.secondary

    /// The color for a thermal status.
    public static func color(for status: ThermostatThermalStatus) -> Color {
        switch status {
        case .heat: heat
        case .cool: cool
        case .idle: neutral
        }
    }

    /// ``color(for:)-(ThermostatThermalStatus)`` as raw sRGB.
    public static func colorToken(for status: ThermostatThermalStatus) -> HassRGB {
        switch status {
        case .heat: heatToken
        case .cool: coolToken
        case .idle: neutralToken
        }
    }

    /// A handle's border: heat-to and cool-to are fixed; a single target follows the status.
    public static func color(for handle: ThermostatTargets.Handle, status: ThermostatThermalStatus) -> Color {
        switch handle {
        case .low: heat
        case .high: cool
        case .target: color(for: status)
        }
    }

    /// ``color(for:status:)`` as raw sRGB.
    public static func colorToken(for handle: ThermostatTargets.Handle, status: ThermostatThermalStatus) -> HassRGB {
        switch handle {
        case .low: heatToken
        case .high: coolToken
        case .target: colorToken(for: status)
        }
    }
}

extension Color {
    /// A dial tint as a SwiftUI color.
    public init(_ tint: DialTint) {
        self.init(.sRGB, red: tint.red / 255, green: tint.green / 255, blue: tint.blue / 255, opacity: tint.opacity)
    }
}

extension ThermostatDialConfiguration {
    /// What decides the marker's and handles' colours: the thermal status (heating, cooling, idle) and any value style.
    public var colorKey: [AnyHashable] { [thermalStatus, valueStyle] }
}
