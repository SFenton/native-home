import Foundation

/// The eight tinted-glass app icons (owner, 2026-10-17): the same house and heart on full-bleed tinted glass, each in a
/// matching pair of colours. ``navySky`` is the app's own icon (`AppIcon` in the asset catalog); the other seven are alternate
/// icons the user picks in Settings → App Icon (`AppIconPickerModel`).
///
/// The colours here are the single source for both the icon art and its previews: `tools/render_app_icons.sh` renders
/// the catalog's PNGs from this table through `AppIconArtwork`, and the picker draws the same view, so the preview
/// cannot drift from the icon. Mockups: `Pairs.dc.html` ("Paired tile and house colours").
public enum AppIconChoice: String, CaseIterable, Identifiable, Sendable {
    case navySky, tealMint, plumLilac, forestGreen, burgundyRose, indigoPeriwinkle, espressoAmber, midnightGold

    public var id: String { rawValue }

    /// The icon the app ships with, installed as `AppIcon`; ``alternateIconName`` is nil for it.
    public static let `default`: AppIconChoice = .navySky

    /// Whether this is the app's own icon (the picker marks it "Default").
    public var isDefault: Bool { self == .default }

    /// The name on screen, "Navy + Sky".
    public var displayName: String {
        switch self {
        case .navySky: "Navy + Sky"
        case .tealMint: "Teal + Mint"
        case .plumLilac: "Plum + Lilac"
        case .forestGreen: "Forest + Green"
        case .burgundyRose: "Burgundy + Rose"
        case .indigoPeriwinkle: "Indigo + Periwinkle"
        case .espressoAmber: "Espresso + Amber"
        case .midnightGold: "Midnight + Gold"
        }
    }

    /// The name VoiceOver reads: "Navy and Sky" (a plus sign is read inconsistently).
    public var spokenName: String { displayName.replacing(" + ", with: " and ") }

    /// The value for `UIApplication.setAlternateIconName(_:)`: nil restores the default icon.
    public var alternateIconName: String? {
        isDefault ? nil : assetName
    }

    /// The icon set in the asset catalog (`AppIcon`, `AppIcon-TealMint`, …). Stable: an installed build remembers it.
    public var assetName: String {
        switch self {
        case .navySky: "AppIcon"
        case .tealMint: "AppIcon-TealMint"
        case .plumLilac: "AppIcon-PlumLilac"
        case .forestGreen: "AppIcon-ForestGreen"
        case .burgundyRose: "AppIcon-BurgundyRose"
        case .indigoPeriwinkle: "AppIcon-IndigoPeriwinkle"
        case .espressoAmber: "AppIcon-EspressoAmber"
        case .midnightGold: "AppIcon-MidnightGold"
        }
    }

    /// The choice for the name `UIApplication.alternateIconName` reports; nil (the default icon) or a name this build
    /// does not know (an icon removed by an update) is the default.
    public init(alternateIconName: String?) {
        self = Self.allCases.first { $0.alternateIconName == alternateIconName } ?? .default
    }

    /// The opacity of ``tint`` over the glow: 0.86 for all eight (the dark icon uses a deeper 0.92).
    public static let tintOpacity = 0.86

    /// The glass's tint as `0xRRGGBB`, drawn across the whole icon at ``tintOpacity`` over the dusk glow.
    public var tint: UInt32 {
        switch self {
        case .navySky: 0x0E1E46
        case .tealMint: 0x063A3E
        case .plumLilac: 0x3A1648
        case .forestGreen: 0x10301E
        case .burgundyRose: 0x48101E
        case .indigoPeriwinkle: 0x221C5A
        case .espressoAmber: 0x342014
        case .midnightGold: 0x101630
        }
    }

    /// The house and heart colour as `0xRRGGBB`.
    public var glyph: UInt32 {
        switch self {
        case .navySky: 0x7CC4FF
        case .tealMint: 0x6EE7C8
        case .plumLilac: 0xD3A8FF
        case .forestGreen: 0x9BE29B
        case .burgundyRose: 0xFF9EB0
        case .indigoPeriwinkle: 0xA8B4FF
        case .espressoAmber: 0xFFB35C
        case .midnightGold: 0xFFD36B
        }
    }
}
