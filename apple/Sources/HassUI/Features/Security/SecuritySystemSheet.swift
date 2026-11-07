import HassCore
import HassDesign
import SwiftUI

// MARK: - Alarm card

/// The security system card (direction G mockup n3; web `SecurityControls`): a badge filled with the mode's colour,
/// the mode as a fact with when it began, and the four mode buttons. On the Security page it sits on a module, in a
/// sheet on the sheet's cell colour. A triggered alarm reddens the card.
///
/// Arming sends at once; Disarm asks first. The tapped mode shows until Home Assistant reports a change (rolled back
/// if the call fails; `.agents/patterns/optimistic-actions.md`).
struct AlarmPanel {
    var caller: any HassServiceCalling

    /// Space between the mode buttons: 12 pt around bezelled controls, so a mis-tap on Disarm beside Home is less likely
    /// (HIG, Accessibility; owner-delegated, 2026-10-25).
    static let modeSpacing = HassTokens.Spacing.m


    /// What the card says for 4 s after Home Assistant rejects a mode change (the tapped mode rolls back).
    static let failureMessage = "Couldn't change the security system. Check the connection."


    /// The badge fill when the panel's state is unknown or hidden: `#636366`, 6:1 under the white glyph.
    private static let neutralBadge: UInt32 = 0x636366




}

struct AlarmModeButton {
    var mode: SecurityConfig.AlarmMode
    var isSelected: Bool
    var isUnavailable: Bool
    /// The alarm is sounding: unselected buttons sit on the card's red wash, so they lighten instead.
    var onAlarm = false
    var action: () -> Void

}

extension AlarmModeButton {
    /// The button's glyph (mockup n3): what each mode means for the people inside, where the card's badge keeps the
    /// web's shield for the panel.
    static func symbol(for mode: SecurityConfig.AlarmMode) -> String {
        switch mode.state {
        case "armed_home": "house"
        case "armed_away": "figure.walk"
        case "armed_night": "moon"
        case "disarmed": "shield.slash"
        default: SymbolMap.symbol(for: mode.icon)
        }
    }
}
