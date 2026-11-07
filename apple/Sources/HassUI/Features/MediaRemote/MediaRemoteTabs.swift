import HassCore
import HassDesign
import SwiftUI

/// One app tile (direction G, n4 remote apps and room Quick App Launch): the artwork on a rounded square, the app's
/// name under it, and a media-pink ring while it runs (no "Playing" line, owner 2026-10-30; VoiceOver still says it). Unavailable dims only the artwork, so the
/// name keeps its contrast.
struct AppTile {
    var app: MediaRemoteApp
    var display: MediaRemoteController.AppDisplay
    var imageURL: URL?
    var action: () -> Void

    /// The artwork grows with its track up to this (was 168 before the "Playing" line went, owner 2026-10-30).
    static let maximumArtwork: CGFloat = 200

    private let shape = RoundedRectangle(cornerRadius: HassTokens.Radius.chip, style: .continuous)





    /// The placeholder glyph is large enough that the audit reads it as text (4.5:1), so a light sheet gets a deeper
    /// media pink (4.9:1 on white) and a grey (6:1) where the family glyphs are 3.8:1 and 4.3:1. Dark is the family's.
    private static let activeFallback = Color.adaptive(light: 0xC0436F, dark: ColorFamily.media.spec.glyph)
    private static let idleFallback = Color.adaptive(light: 0x636366, dark: ColorFamily.media.offGlyphRGB(.dark))
}

// MARK: - Hue Sync

/// Sync Box power and light sync, sync mode, intensity and brightness, and HDMI input (web `HueSyncTab`), as an
/// inset grouped list (direction G, n4 remote Hue Sync): switches in rows, segmented controls for the short mode
/// and intensity choices, and a checkmark list for the inputs.
///
/// Departure from the web: tapping the selected sync mode again while not syncing no longer restarts syncing (a
/// segmented control does not report a tap on its selected segment). Light Sync starts it.
struct HueSyncTab {
    var controller: MediaRemoteController
    var hue: HueSyncConfig

    static let help = "Light Sync turns on the Sync Box and starts syncing. Choosing a mode does the same. Presence lighting pauses until syncing stops."





}
