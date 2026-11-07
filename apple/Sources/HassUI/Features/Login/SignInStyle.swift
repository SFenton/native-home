import FentonActivityModel
import HassCore
import HassDesign
import SwiftUI

/// The sign-in screen's ground and its marks (owner, 2026-10-17; `.agents/design/direction-g.md`, "Sign-in").
enum SignInStyle {
    /// The plain dark ground: the launch screen's colour (`LaunchBackground`), so the first frame matches it, and the
    /// edge of the glow.
    static let base: UInt32 = 0x121722
    /// The glow's centre, then its middle ring (`#3A4E73` → `#1E2A44` → `#121722`).
    static let glowCentre: UInt32 = 0x3A4E73
    static let glowMiddle: UInt32 = 0x1E2A44
    /// Text-button blue on this ground: `#409CFF` read 3.8:1 over the glow's lighter middle, so this one is lifted to 4.5:1 there.
    static let link: UInt32 = 0x8AC4FF
    /// The red of an error on this ground: `#FF6961` is 5.9:1 on the base.
    static let error: UInt32 = 0xFF6961
    /// The failure card's corner radius.
    static let cardRadius: CGFloat = 20
    /// The failure card's red wash and outline, as opacities of ``error``.
    static let errorWash = 0.16
    static let errorOutline = 0.45
    /// Hairlines of the field module on this ground: white at the dark-sheet separator opacity.
    static let hairline = Color.white.opacity(HassTokens.Palette.separatorDarkOpacity)
    /// The widest the form column grows (iPad and the unfolded Duo, any orientation).
    static let columnWidth: CGFloat = 460

    /// The icon the person picked: the mark takes its house colour. The app group holds it (the Live Activity reads it
    /// too); the default icon is Navy + Sky.
    static func savedIcon(_ store: ActivityAppIconStore = .shared) -> AppIconChoice {
        AppIconChoice(rawValue: store.choice) ?? .default
    }
}
