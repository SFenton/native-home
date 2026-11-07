import HassCore
import HassDesign
import SwiftUI

/// The chip's capsule (web `GlassTile` `.headerPill`: `border-radius: 999px`, 48 px tall; owner, 2026-10-13:
/// "Page-level chips are not pills like they are in web or the Apple Home app, and need background colors").
///
/// Direction G: an active chip fills with its family's chip colour and a slight top highlight; a neutral one sits
/// on the thin module, like the cards around it.
enum StatusChipStyle {
    /// Web `.headerPill` height (48 px), above the 44 pt minimum target.
    static let minHeight: CGFloat = 48

    /// The family whose fill the chip draws, or nil for the neutral chip.
    static func fillFamily(_ family: ColorFamily?, isActive: Bool) -> ColorFamily? {
        guard isActive, let family, family.chipFillRGB != nil else { return nil }
        return family
    }

    /// The tint the chip draws: a computed `tint`, else its active family's, else nil for the neutral chip.
    static func fillTint(_ family: ColorFamily?, isActive: Bool, tint: ChipTint?) -> ChipTint? {
        tint ?? fillFamily(family, isActive: isActive).flatMap { ChipTint(family: $0) }
    }
}
