#if os(iOS)
import HassDesign
import UIKit

// MARK: - Fonts

extension UIFont {
    /// A SwiftUI text style as UIKit draws it: the preferred font of `style` at the default size, scaled with Dynamic Type
    /// (`adjustsFontForContentSizeCategory` keeps it current), with SwiftUI's `.weight(_:)` and `.monospacedDigit()`.
    /// - Parameters:
    ///   - style: `.body` for `.font(.body)`, `.footnote` for `.font(.footnote)` …
    ///   - weight: `.font(.body.weight(.medium))`; `.bold` for `.bold()`.
    ///   - monospacedDigit: `.monospacedDigit()`.
    static func ukFont(_ style: UIFont.TextStyle, weight: UIFont.Weight = .regular, monospacedDigit: Bool = false) -> UIFont {
        let base = UIFont.preferredFont(forTextStyle: style, compatibleWith: UITraitCollection(preferredContentSizeCategory: .large))
        var attributes: [UIFontDescriptor.AttributeName: Any] = [.traits: [UIFontDescriptor.TraitKey.weight: weight]]
        if monospacedDigit {
            attributes[.featureSettings] = [[
                UIFontDescriptor.FeatureKey.type: kNumberSpacingType,
                UIFontDescriptor.FeatureKey.selector: kMonospacedNumbersSelector,
            ]]
        }
        let descriptor = base.fontDescriptor.addingAttributes(attributes)
        return UIFontMetrics(forTextStyle: style).scaledFont(for: UIFont(descriptor: descriptor, size: base.pointSize))
    }
}

extension UILabel {
    /// A label that follows Dynamic Type, wraps, and draws `style` in `ink` (SwiftUI `Text(…).font(style).foregroundStyle(ink)`
    /// with `fixedSize(horizontal: false, vertical: true)`).
    static func uk(_ style: UIFont.TextStyle, weight: UIFont.Weight = .regular, monospacedDigit: Bool = false, ink: UIColor,
                   lines: Int = 0, alignment: NSTextAlignment = .natural) -> UILabel {
        let label = UILabel()
        label.font = .ukFont(style, weight: weight, monospacedDigit: monospacedDigit)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = ink
        label.numberOfLines = lines
        label.textAlignment = alignment
        label.lineBreakMode = .byWordWrapping
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        return label
    }
}

// MARK: - Ink and surface tokens as UIKit colours

/// ``HassTokens/Ink`` and ``HassTokens/Surface`` as dynamic `UIColor`s, built from the same ``HassTokens/Palette`` values and
/// the same Increase Contrast rule, so a sheet resolves light or dark from its own trait collection exactly as the SwiftUI
/// tokens do. (``UIColor/init(_:)-(HassRGB)`` builds them from HassDesign's raw tokens; these are built from the raw values so they are
/// dynamic by construction.)
enum UKDesignInk {
    private static func components(_ rgb: UInt32) -> (Double, Double, Double) {
        (Double((rgb >> 16) & 0xFF) / 255, Double((rgb >> 8) & 0xFF) / 255, Double(rgb & 0xFF) / 255)
    }

    /// `HassTokens.Ink.dynamic(light:dark:)`: a light and a dark triple, stepped toward the extreme with Increase Contrast.
    private static func dynamic(light: (Double, Double, Double), dark: UInt32) -> UIColor {
        UIColor { traits in
            let isDark = traits.userInterfaceStyle == .dark
            var rgb = isDark ? components(dark) : light
            if traits.accessibilityContrast == .high { rgb = HassTokens.Ink.increasedContrast(rgb, isDark: isDark) }
            return UIColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        }
    }

    private static func adaptive(light: UInt32, lightAlpha: Double = 1, dark: UInt32, darkAlpha: Double = 1) -> UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(rgb: dark, alpha: darkAlpha)
                : UIColor(rgb: light, alpha: lightAlpha)
        }
    }

    /// Titles and values: the label colour.
    static let primary = UIColor.label
    /// Supporting text: the label at 72%, 92% with Increase Contrast.
    static let secondary = UIColor { traits in
        UIColor.label.resolvedColor(with: traits).withAlphaComponent(traits.accessibilityContrast == .high ? 0.92 : 0.72)
    }
    static let onDark = UIColor.white
    static let error = dynamic(light: (0.70, 0.11, 0.11), dark: HassTokens.Palette.red)
    static let danger = dynamic(light: (0.76, 0.09, 0.09), dark: HassTokens.Palette.red)
    static let warning = dynamic(light: (0.60, 0.33, 0.0), dark: HassTokens.Palette.orange)
    static let action = dynamic(light: (0.0, 0.40, 0.80), dark: HassTokens.Palette.tintText)
    static let success = adaptive(light: HassTokens.Palette.successLight, dark: HassTokens.Palette.success)
    static let actionFill = UIColor(rgb: HassTokens.Palette.tintFill)
}

enum UKDesignSurface {
    /// The sheet's opaque ground: the system grouped background.
    static let systemGround = UIColor.systemGroupedBackground
    /// A cell inside a sheet: `#2C2C2E` in dark, white in light.
    static let sheetCell = UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(rgb: HassTokens.Palette.sheetCell) : UIColor(rgb: HassTokens.Palette.sheetCellLight)
    }
    /// Hairlines: white at 14% on dark, `#3C3C43` at 29% on light.
    static let separator = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(rgb: 0xFFFFFF, alpha: HassTokens.Palette.separatorDarkOpacity)
            : UIColor(rgb: HassTokens.Palette.secondaryLabelLight, alpha: HassTokens.Palette.separatorLightOpacity)
    }
    /// Secondary text in a sheet: 60% light grey on dark, 76% dark grey on light.
    static let secondaryInSheet = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(rgb: HassTokens.Palette.secondaryLabel, alpha: HassTokens.Palette.secondaryInSheetDarkOpacity)
            : UIColor(rgb: HassTokens.Palette.secondaryLabelLight, alpha: HassTokens.Palette.secondaryInSheetLightOpacity)
    }
    /// Secondary text on a module (pages are always dark): `#EBEBF5` at 68%.
    static let secondaryOnModule = UIColor(rgb: HassTokens.Palette.secondaryLabel, alpha: 0.68)
    /// Secondary text straight on the wallpaper: `#EBEBF5` at 85%.
    static let secondaryOnWallpaper = UIColor(rgb: HassTokens.Palette.secondaryLabel, alpha: 0.85)

    /// The module tint, opaque with Reduce Transparency (``ModuleBackground/tint(_:reduceTransparency:)``).
    static func moduleTint(_ density: ModuleDensity, reduceTransparency: Bool) -> UIColor {
        switch (density, reduceTransparency) {
        case (.thin, false): UIColor(rgb: HassTokens.Palette.moduleThin, alpha: 0.66)
        case (.dense, false): UIColor(rgb: HassTokens.Palette.moduleDense, alpha: 0.78)
        case (.thin, true): UIColor(rgb: HassTokens.Palette.moduleThin)
        case (.dense, true): UIColor(rgb: HassTokens.Palette.moduleDense)
        }
    }

    /// ``TileSurface/secondaryInk`` for a surface.
    static func secondary(on surface: TileSurface) -> UIColor { surface == .sheet ? secondaryInSheet : secondaryOnModule }
    /// The title ink on a surface: white on a page, the label colour in a sheet.
    static func title(on surface: TileSurface) -> UIColor { surface == .sheet ? UKDesignInk.primary : .white }
}

// MARK: - Motion

/// The motion tokens as UIKit animations (`MotionTokens`): the same durations and curves, Reduce Motion honoured.
@MainActor
extension UKMotion {
    /// ``MotionTokens/state``: `easeInOut`, 0.6 s (0.2 s under Reduce Motion): a colour that follows state.
    static func state(_ changes: @escaping () -> Void) {
        let duration = UIAccessibility.isReduceMotionEnabled ? 0.2 : MotionTokens.stateDuration
        UIView.animate(withDuration: duration, delay: 0, options: [.curveEaseInOut, .allowUserInteraction], animations: changes)
    }

    /// Cross-fades a label's or image's colour change over ``MotionTokens/state`` when it is on screen.
    static func crossFade(_ view: UIView, _ changes: @escaping () -> Void) {
        guard view.window != nil else { changes(); return }
        let duration = UIAccessibility.isReduceMotionEnabled ? 0.2 : MotionTokens.stateDuration
        UIView.transition(with: view, duration: duration, options: [.transitionCrossDissolve, .allowUserInteraction], animations: changes)
    }
}
#endif
