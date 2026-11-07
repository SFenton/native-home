import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Design tokens shared by every Apple surface. Values follow the web dashboard's density
/// (`src/styles/tokens.css`) adapted to HIG spacing.
public enum HassTokens {
    // MARK: - Spacing

    public enum Spacing {
        public static let xs: CGFloat = 4
        public static let s: CGFloat = 8
        public static let m: CGFloat = 12
        public static let l: CGFloat = 16
        public static let xl: CGFloat = 24
    }

    // MARK: - Radii

    public enum Radius {
        /// Tiles (direction G, Controls: 22 pt).
        public static let tile: CGFloat = 22
        /// Modules, cards and inset lists on the wallpaper (direction G, Layers: 26 pt).
        public static let module: CGFloat = 26
        public static let chip: CGFloat = 16
        public static let media: CGFloat = 16
    }

    // MARK: - State colors

    /// Tints for active entity states, from the web's card colors.
    public enum Tint {
        public static let light = Color(RGB.Tint.light)
        public static let security = Color(RGB.Tint.security)
        public static let climate = Color(RGB.Tint.climate)
        public static let presence = Color(RGB.Tint.presence)
        public static let contact = Color(RGB.Tint.contact)
        public static let neutral = Color.secondary
        /// Air quality and fans.
        public static let air = Color(RGB.Tint.air)
        /// Vacuums.
        public static let vacuum = Color(RGB.Tint.vacuum)
        /// A room's warning tone.
        public static let warning = Color(RGB.Tint.warning)
        /// A room's neutral tone: a slate gray.
        public static let slate = Color(RGB.Tint.slate)
        /// Heating and a heat-to handle: the web's thermostat orange (`#cd5401`).
        public static let heat = Color(RGB.Tint.heat)
        /// Cooling and a cool-to handle: the web's thermostat teal (`#2c8e98`).
        public static let cool = Color(RGB.Tint.cool)
        /// Water (sprinklers); dark enough for white text at 4.5:1.
        public static let water = Color(RGB.Tint.water)
    }

    // MARK: - Direction G palette

    /// Direction G's fixed colours as `0xRRGGBB` sRGB, kept raw so tests can check contrast
    /// (`.agents/design/direction-g.md`, Colour). Views use the `Color`s on ``Ink`` and ``Surface``.
    public enum Palette {
        /// Tint for text and glyph actions on dark (system blue lifted for small text; `#007AFF` and `#0A84FF`
        /// fail 4.5:1 on dark).
        public static let tintText: UInt32 = 0x409CFF
        /// Tint for filled controls with a white label (``PrimaryButton``, the sheet confirm check).
        public static let tintFill: UInt32 = 0x0071E3
        /// Destructive, error and overdue text and glyphs on dark.
        public static let red: UInt32 = 0xFF6961
        /// Soon and warning text and glyphs on dark.
        public static let orange: UInt32 = 0xFFB340
        /// Count badges (Chores overdue), under white numerals.
        public static let badge: UInt32 = 0xD93025
        /// Sheet ground in dark appearance (`systemGray6` dark).
        public static let sheetGround: UInt32 = 0x1C1C1E
        /// Cells and tiles inside a sheet (`systemGray5` dark).
        public static let sheetCell: UInt32 = 0x2C2C2E
        /// The thin module on the wallpaper: `#1C1C1E` at 66% (G's 55% over a background blur, without the live blur
        /// the pre-blurred wallpaper makes redundant).
        public static let moduleThin: UInt32 = 0x1C1C1E
        /// The dense module that carries red or orange text over the lit windows: `#141416` at 78%.
        public static let moduleDense: UInt32 = 0x141416
        /// Secondary label: `rgba(235,235,245,.68)` on modules and `.6` in sheets.
        public static let secondaryLabel: UInt32 = 0xEBEBF5

        // MARK: Light appearance (sheets only)

        /// Sheet ground in light appearance (`systemGroupedBackground` light).
        public static let sheetGroundLight: UInt32 = 0xF2F2F7
        /// An applied control's light fill (system gray 6): the floating bar's active circle, under a black glyph.
        public static let activeControlFill: UInt32 = 0xF2F2F7
        /// Cells and tiles inside a light sheet (`secondarySystemGroupedBackground` light).
        public static let sheetCellLight: UInt32 = 0xFFFFFF
        /// Secondary label in a light sheet (`secondaryLabel` light's colour; see ``secondaryInSheetLightOpacity``).
        public static let secondaryLabelLight: UInt32 = 0x3C3C43
        /// Secondary text in a light sheet: ``secondaryLabelLight`` at 76%, 5:1 or better on the sheet ground and
        /// cells (the system's own 60% is 3.3:1 on white).
        public static let secondaryInSheetLightOpacity = 0.76
        /// Secondary text in a dark sheet: ``secondaryLabel`` at 60%.
        public static let secondaryInSheetDarkOpacity = 0.6
        /// Hairlines in a light sheet: `separator` light, `#3C3C43` at 29%.
        public static let separatorLightOpacity = 0.29
        /// Hairlines on dark: white at 14%.
        public static let separatorDarkOpacity = 0.14
        /// Tint for text and glyph actions on a light sheet (5.6:1 on white, 5:1 on the sheet ground).
        public static let tintTextLight: UInt32 = 0x0066CC
        /// Destructive, error and overdue text and glyphs on a light sheet (6:1 on white).
        public static let redLight: UInt32 = 0xC21717
        /// Soon and warning text on a light sheet (a dark amber, 5:1 on white).
        public static let orangeLight: UInt32 = 0x995400
        /// Success text and glyphs on dark (the system's dark-mode green).
        public static let success: UInt32 = 0x30D158
        /// Success text and glyphs on a light sheet (5.6:1 on white).
        public static let successLight: UInt32 = 0x1E7B34
        /// "Unavailable" glyphs and text on a light sheet: `systemGray` darkened to 5.99:1 on white (system gray is 3.3:1).
        public static let unavailableLight: UInt32 = 0x636366
        /// "Unavailable" glyphs and text on dark: the system gray (`#8E8E93`), 4.3:1 on a dark sheet cell.
        public static let unavailable: UInt32 = 0x8E8E93
        /// A control's track (the thermostat ring) in the label colour: 43% is the smallest that clears 3:1 on both appearances (2.99:1 at 42% on the light sheet ground).
        public static let trackOpacity = 0.43
        /// ``trackOpacity`` with Increase Contrast.
        public static let trackOpacityIncreased = 0.60
    }

    // MARK: - Text

    /// Text colors for content on materials. Plain `Color`s rather than the hierarchical `.primary` /
    /// `.secondary` styles, which pick up vibrancy on a material and fail the contrast audit there.
    public enum Ink {
        /// Titles and values.
        public static let primary = Color(RGB.Ink.primary)
        /// Supporting text (summaries, states): still at least 4.5:1 on the light and dark materials.
        public static let secondary = Color(RGB.Ink.secondary)

        /// The Increase Contrast variant of a text color: dark-appearance text moves toward white, light-appearance text
        /// toward black, by ``increasedContrastStep``.
        /// - Parameters:
        ///   - rgb: The color's components (0...1).
        ///   - isDark: Whether the appearance is dark.
        public static func increasedContrast(_ rgb: (Double, Double, Double), isDark: Bool) -> (Double, Double, Double) {
            let target = isDark ? 1.0 : 0.0
            let step = increasedContrastStep
            return (rgb.0 + (target - rgb.0) * step, rgb.1 + (target - rgb.1) * step, rgb.2 + (target - rgb.2) * step)
        }

        /// How far Increase Contrast moves a text color toward the extreme (35%).
        public static let increasedContrastStep = 0.35

        /// Text on an always-dark backdrop (the weather card and sheet gradients): white, at least 5.6:1 on the
        /// lightest backdrop color, in light and dark mode alike.
        public static let onDark = Color(RGB.Ink.onDark)
        /// Supporting text on an always-dark backdrop: white at 85%, at least 4.5:1 on the lightest backdrop color.
        public static let onDarkSecondary = Color(RGB.Ink.onDarkSecondary)

        /// Inline error text (``InlineAlert`` error severity): a red dark enough for 4.5:1 on light materials and
        /// light enough on dark ones (tuned on the Vacation and Solo Trip pages).
        public static let error = Color(RGB.Ink.error)

        /// Destructive actions ("Stop watering"): system red is 3.6:1 on a light grouped row, this is at least
        /// 6:1 on light rows and G's `#FF6961` on dark (HIG: Color; WCAG 1.4.3).
        public static let danger = Color(RGB.Ink.danger)

        /// Soon and warning text ("Due Tomorrow"): G's `#FFB340` on dark, a dark amber at 4.5:1 or better on light.
        public static let warning = Color(RGB.Ink.warning)

        /// Tint for text buttons, links and glyph actions: 5.6:1 on light rows, and G's `#409CFF` on dark.
        public static let action = Color(RGB.Ink.action)

        /// Success and "ok" text and glyphs (a running device, a green status): the system's dark-mode green
        /// (`#30D158`) on dark, a deeper green (`#1E7B34`, 5.6:1) on a light sheet where system green is 2.3:1.
        public static let success = Color(RGB.Ink.success)

        /// A glyph on a filled ``success`` disc: white on the light sheet's deep green (5.3:1), the sheet ground on
        /// dark's bright green (7.9:1).
        public static let onSuccessFill = Color(RGB.Ink.onSuccessFill)

        /// An unavailable device's glyph and status: a gray at 4.5:1 or better on light and dark sheets and modules
        /// (`#636366` light, `#8E8E93` dark). It is never the only signal: the word "Unavailable" travels with it.
        public static let unavailable = Color(RGB.Ink.unavailable)

        /// A control's track (the thermostat ring): the label colour at ``Palette/trackOpacity`` (3:1 as a control
        /// boundary), ``Palette/trackOpacityIncreased`` with Increase Contrast.
        /// - Parameter increased: Whether Increase Contrast is on.
        public static func track(increasedContrast increased: Bool) -> Color {
            Color(RGB.Ink.track(increasedContrast: increased))
        }

        /// Fill for controls with a white label (``PrimaryButton``, the sheet confirm check): G's `#0071E3`, 4.6:1
        /// under white in both appearances.
        public static let actionFill = Color(RGB.Ink.actionFill)

        /// Label on an owner's colour-family fill (``PrimaryButton`` with a family): the sheet ground, dark in both
        /// appearances because the family's glyph colour it sits on is fixed.
        public static let onFamilyFill = Color(RGB.Ink.onFamilyFill)

        /// Count badges under white numerals: `#D93025`.
        public static let badge = Color(RGB.Ink.badge)

        /// The platform label color as a plain dynamic color (`Color.primary` resolves to the vibrant
        /// hierarchical style inside a material).
        private static var label: Color {
            #if os(watchOS)
            Color.white
            #elseif canImport(UIKit)
            Color(uiColor: .label)
            #else
            Color(nsColor: .labelColor)
            #endif
        }
    }

    // MARK: - Surfaces

    /// Direction G's grounds (`.agents/design/direction-g.md`, Layers). Pages are always dark on the wallpaper; the
    /// sheet tokens (``sheetGround``, ``sheetCell``, ``separator``, ``secondaryInSheet``) are light and dark pairs that
    /// follow the sheet's appearance (``SwiftUICore/View/followsSystemAppearance()``).
    public enum Surface {
        /// Sheet ground: `#1C1C1E` in dark appearance, the system grouped background (`#F2F2F7`) in light.
        public static let sheetGround = Color(RGB.Surface.sheetGround)
        /// The system grouped background: the opaque ground of a modal sheet that follows the system appearance.
        /// The one place the shared views read it from UIKit (the macOS branch is the legacy test host).
        public static var systemGround: Color {
            #if os(watchOS)
            Color.black
            #elseif canImport(UIKit)
            Color(uiColor: .systemGroupedBackground)
            #else
            Color(nsColor: .windowBackgroundColor)
            #endif
        }
        /// Cells and tiles inside a sheet: `#2C2C2E` in dark appearance, white in light.
        public static let sheetCell = Color(RGB.Surface.sheetCell)
        /// The thin module tint (``SwiftUICore/View/module(_:cornerRadius:)``).
        public static let moduleThin = Color(RGB.Surface.moduleThin)
        /// ``moduleThin``, or the opaque module fill with Reduce Transparency, for list rows that cannot use `.module()`.
        public static func moduleThin(reduceTransparency: Bool) -> Color {
            reduceTransparency ? Color(rgb: Palette.moduleThin) : moduleThin
        }
        /// The dense module for red and orange text; also the opaque-enough fallback with Reduce Transparency.
        public static let moduleDense = Color(RGB.Surface.moduleDense)
        /// Hairline separators: white at 14% on dark, the system separator colour in a light sheet.
        public static let separator = Color(RGB.Surface.separator)
        /// Secondary labels on modules.
        public static let secondaryOnModule = Color(RGB.Surface.secondaryOnModule)
        /// Secondary labels on a module under a state wash (``GlassTileFace``), which lifts the ground.
        public static let secondaryOnWash = Color(RGB.Surface.secondaryOnWash)
        /// Secondary labels straight on the wallpaper, with no module under them (a titled spinner on a page): the photo's
        /// brightest part under only the scrim measured 3.1:1 for the system's `.secondary` (60%), so this is 85%.
        public static let secondaryOnWallpaper = Color(RGB.Surface.secondaryOnWallpaper)
        /// ``secondaryOnWallpaper``'s opacity.
        static let secondaryOnWallpaperOpacity = 0.85
        /// ``secondaryOnModule``'s opacity.
        static let secondaryOnModuleOpacity = 0.68
        /// ``secondaryOnWash``'s opacity.
        static let secondaryOnWashOpacity = 0.85
        /// Secondary labels in sheets: 60% light-grey on dark, 76% dark-grey on light (4.5:1 or better on both
        /// grounds and on the cells).
        public static let secondaryInSheet = Color(RGB.Surface.secondaryInSheet)
    }

    // MARK: - Typography

    /// The emphasised text styles that recur across the app, so a weight is set once and not per call site. Text
    /// styles keep Dynamic Type; the weight is the design's semibold (direction G, Typography).
    public enum Typography {
        /// A section heading: a page or settings section, a filter section (`title3`, bold). Bold is the one section-header
        /// weight (owner, 2026-10-24); set it here only.
        public static let sectionTitle = Font.title3.bold()
        /// A tile's title (`subheadline`, bold).
        public static let tileTitle = Font.subheadline.bold()
        /// A row, field or chip title (`subheadline`, semibold).
        public static let rowTitle = Font.subheadline.weight(.semibold)
        /// A control's or glyph's emphasised label (`body`, semibold).
        public static let bodyEmphasis = Font.body.weight(.semibold)
        /// A small trailing glyph or chevron, and a compact title (`footnote`, semibold).
        public static let footnoteEmphasis = Font.footnote.weight(.semibold)
        /// An overlay label on a picture (`caption`, semibold).
        public static let captionEmphasis = Font.caption.weight(.semibold)
    }

    // MARK: - Control states

    /// How a control dims, as opacities of its normal drawing.
    public enum ControlState {
        /// A disabled control.
        public static let disabledOpacity = 0.4
        /// A control while pressed.
        public static let pressedOpacity = 0.8
    }

    // MARK: - Washes

    /// Opacities of the tinted wash behind a notice, drawn in an ``Ink`` tone so it adapts to appearance and contrast.
    public enum Wash {
        /// ``InlineAlert``'s warning wash.
        public static let alert = 0.14
        /// ``InfoBox``'s wash.
        public static let notice = 0.16
    }

    /// Minimum hit target (HIG: Buttons).
    public static let minTarget: CGFloat = 44
}
