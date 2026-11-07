import SwiftUI

/// The tone and surface vocabulary of a labeled status value with a tone (web `StatusPill`, `src/components/core/StatusPill.tsx`;
/// pattern: `.agents/patterns/status-pill.md`).
///
/// Drawn by `UKStatusPillView`: VoiceOver reads the label, then the value and detail, as one element.
public enum StatusPill {
    /// The icon's color (web `StatusPillTone`).
    public enum Tone: Sendable { case neutral, ok, active, warning, danger, unavailable }

    /// What the pill is drawn on.
    public enum Surface: Sendable {
        /// A page: a material, like the tiles around it.
        case page
        /// A grouped list in a sheet: a solid row fill. A material over the sheet's glass smeared the
        /// content behind it.
        case groupedList
        /// A cell inside a direction G module on the wallpaper (``SwiftUICore/View/module(_:cornerRadius:)``), which
        /// draws the ground: no fill of its own.
        case module
    }

    /// What VoiceOver reads for the value while the first state is on its way.
    public nonisolated static let pendingValue = "Loading"

    /// `value, detail`, or just the value.
    public nonisolated static func accessibilityValue(value: String, detail: String?) -> String {
        [value, detail].compactMap { $0 }.formatted(.list(type: .and, width: .narrow))
    }

    /// The icon color for a tone.
    public static func color(_ tone: Tone) -> Color {
        switch tone {
        case .neutral: HassTokens.Ink.secondary
        case .ok: HassTokens.Ink.success
        case .active: HassTokens.Tint.water
        case .warning: HassTokens.Ink.warning
        case .danger: HassTokens.Ink.danger
        case .unavailable: HassTokens.Ink.unavailable
        }
    }

    /// ``color(_:)`` as raw sRGB.
    public static func colorToken(_ tone: Tone) -> HassRGB {
        switch tone {
        case .neutral: HassTokens.RGB.Ink.secondary
        case .ok: HassTokens.RGB.Ink.success
        case .active: HassTokens.RGB.Tint.water
        case .warning: HassTokens.RGB.Ink.warning
        case .danger: HassTokens.RGB.Ink.danger
        case .unavailable: HassTokens.RGB.Ink.unavailable
        }
    }
}
