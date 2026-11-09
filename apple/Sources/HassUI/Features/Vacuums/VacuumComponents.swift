import HassCore
import HassDesign
import SwiftUI

// MARK: - Style

/// Colours and shapes local to the vacuum surfaces, all drawn from direction G's tokens
/// (`.agents/design/direction-g.md`, Colour; vacuums are the ``ColorFamily/cleaning`` family).
enum VacuumStyle {
    /// A status tone's glyph colour.
    static func color(_ tone: VacuumTone) -> Color { Color(colorToken(tone)) }

    /// ``color(_:)-(VacuumTone)`` as raw sRGB.
    static func colorToken(_ tone: VacuumTone) -> HassRGB {
        switch tone {
        case .active: ColorFamily.cleaning.glyphToken
        case .ok: HassTokens.RGB.Ink.success
        case .returning: HassTokens.RGB.Ink.action
        case .warning: HassTokens.RGB.Ink.warning
        case .danger: HassTokens.RGB.Ink.danger
        case .neutral: HassTokens.RGB.Ink.secondary
        case .unavailable: HassTokens.RGB.Ink.unavailable
        }
    }

    /// A command button's glyph colour: white on the primary capsule, the tone on the grey one.
    static func color(_ tone: VacuumController.ActionTone) -> Color { Color(colorToken(tone)) }

    /// ``color(_:)-(VacuumController.ActionTone)`` as raw sRGB.
    static func colorToken(_ tone: VacuumController.ActionTone) -> HassRGB {
        switch tone {
        case .primary: .white
        case .neutral: HassTokens.RGB.Ink.primary
        case .warning: HassTokens.RGB.Ink.warning
        case .danger: HassTokens.RGB.Ink.danger
        }
    }

    /// The SF Symbol for an MDI name.
    static func symbol(_ mdi: String) -> String { SymbolMap.symbol(for: mdi) }

    /// A selected room (map, room cards, order chips): the label's opposite, white with dark ink in a dark sheet the way
    /// the mockups draw a chosen room (direction G, Controls: Vacuum map), and `#1C1C1E` with white ink on a light
    /// sheet, where white would vanish on the cell.
    static let selectedFill = Color.adaptive(light: HassTokens.Palette.sheetGround, dark: 0xFFFFFF)
    /// Ink on ``selectedFill`` and the order badge's disc: `#1C1C1E` in a dark sheet, white in a light one.
    static let selectedInk = Color.adaptive(light: 0xFFFFFF, dark: HassTokens.Palette.sheetGround)

    /// The secondary capsule's fill (Pause, Stop, Edit Area): the system's grey control fill.
    static var secondaryFill: AnyShapeStyle { AnyShapeStyle(.fill.secondary) }
}
