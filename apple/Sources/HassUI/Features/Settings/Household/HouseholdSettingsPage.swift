import HassCore
import HassDesign
import SwiftUI

// MARK: - Pages

/// The household Settings topics ported in this lane, in the web's order (`portedDashboard.ts`
/// `SETTINGS_PAGE_ITEMS`; copy from `settings.json` `items.*`). Raw values match the topic ids of the
/// Settings navigation shell, so `settings.topic.<id>` identifies the row everywhere.
enum HouseholdSettingsPage: String, CaseIterable, Identifiable, Hashable, Codable, Sendable {
    case admin, specialDeviceModes, guests, machE

    var id: String { rawValue }

    /// The Settings row title.
    var rowTitle: String {
        switch self {
        case .admin: "Admin Controls"
        case .specialDeviceModes: "Special Device Modes"
        case .guests: "Guest Controls"
        case .machE: "Mach-E"
        }
    }

    /// The Settings row subtitle.
    var subtitle: String {
        switch self {
        case .admin: "Presence-Based Toggles, Automation Overrides, and More"
        case .specialDeviceModes: "Allows enabling special device modes, such as High AQI Mode."
        case .guests: "Toggle automations when guests stay over."
        case .machE: "Controls for the Mustang Mach-E."
        }
    }

    /// The page's navigation title (web route titles: Admin, Special Device Modes, Guest Controls, Mach-E).
    var pageTitle: String {
        switch self {
        case .admin: HouseholdSettingsConfig.Admin.pageTitle
        case .specialDeviceModes: HouseholdSettingsConfig.SpecialDeviceModes.pageTitle
        case .guests: HouseholdSettingsConfig.Guests.pageTitle
        case .machE: HouseholdSettingsConfig.MachE.pageTitle
        }
    }

    /// The row's SF Symbol (web `mdi:shield-account`, `mdi:tune-vertical`, `mdi:account-multiple`, `mdi:car-estate`).
    var symbol: String {
        switch self {
        case .admin: "person.badge.shield.checkmark"
        case .specialDeviceModes: "slider.vertical.3"
        case .guests: "person.2"
        case .machE: "car.side"
        }
    }
}

// MARK: - Shared pieces

extension HassTokens.Tint {
    /// Toggle tiles' active tint (web `SWITCH_ACTIVE_COLOR`, 67/160/71).
    static let settingsSwitch = Color(HassTokens.RGB.Tint.settingsSwitch)
    /// Read-only control tiles (web `CONTROL_COLOR`, 75/126/210).
    static let settingsControl = Color(HassTokens.RGB.Tint.settingsControl)
}

extension HassTokens.RGB.Tint {
    /// ``HassTokens/Tint/settingsSwitch`` as raw sRGB.
    static let settingsSwitch = HassRGB(red: 67 / 255, green: 160 / 255, blue: 71 / 255)
    /// ``HassTokens/Tint/settingsControl`` as raw sRGB.
    static let settingsControl = HassRGB(red: 75 / 255, green: 126 / 255, blue: 210 / 255)
}

extension PresenceOverrideState {
    /// The web card color.
    var tint: Color { Color(tintToken) }

    /// ``tint`` as raw sRGB.
    var tintToken: HassRGB { HassRGB(red: Double(rgb.red) / 255, green: Double(rgb.green) / 255, blue: Double(rgb.blue) / 255) }
}

// MARK: - Read-only tile

/// An entity tile that only shows state (web `EntityActionCard` with no action): a ``GlassTile`` of the `.state`
/// kind, which is not a button and is never dimmed as disabled (the subtitle carries "Unavailable").
///
/// A tile whose entity shows no state text still speaks On or Off, and draws the word when Differentiate Without Color
/// is on, so the active fill and glyph are never the only signal.
struct GlassStateTile {
    var title: String
    var subtitle: String?
    var symbol: String
    var tint: Color
    var isActive: Bool
    var isUnavailable = false

    /// What VoiceOver says: the state text, else Unavailable, On or Off.
    static func spokenValue(subtitle: String?, isActive: Bool, isUnavailable: Bool) -> String {
        if let subtitle { return subtitle }
        return isUnavailable ? "Unavailable" : (isActive ? "On" : "Off")
    }

}
