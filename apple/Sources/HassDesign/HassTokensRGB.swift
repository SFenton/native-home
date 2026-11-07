import Foundation

extension HassTokens {
    /// The colour tokens as raw ``HassRGB``: the single source of truth. The `Color`s on ``Tint``, ``Ink`` and ``Surface`` are
    /// derived from these (`Color(_:)`), and the UIKit port reads them as `UIColor(_:)`, so neither platform converts through the
    /// other.
    public enum RGB {
        /// ``HassTokens/Tint`` as sRGB.
        public enum Tint {
            public static let light = HassRGB(red: 1.0, green: 0.78, blue: 0.29)
            public static let security = HassRGB(red: 0.90, green: 0.22, blue: 0.21)
            public static let climate = HassRGB(red: 0.10, green: 0.33, blue: 0.51)
            public static let presence = HassRGB(red: 0.20, green: 0.76, blue: 0.57)
            public static let contact = HassRGB(red: 0.98, green: 0.55, blue: 0.20)
            public static let air = HassRGB(red: 0.26, green: 0.63, blue: 0.28)
            public static let vacuum = HassRGB(red: 0.40, green: 0.33, blue: 0.80)
            public static let warning = HassRGB(red: 0.81, green: 0.45, blue: 0.15)
            public static let slate = HassRGB(red: 0.45, green: 0.47, blue: 0.50)
            public static let heat = HassRGB(red: 205 / 255, green: 84 / 255, blue: 1 / 255)
            public static let cool = HassRGB(red: 44 / 255, green: 142 / 255, blue: 152 / 255)
            public static let water = HassRGB(red: 0.05, green: 0.40, blue: 0.70)
        }

        /// ``HassTokens/Ink`` as sRGB.
        public enum Ink {
            public static let primary = HassRGB.label
            /// The label at 72%, 92% with Increase Contrast.
            public static let secondary = HassRGB(
                light: .init(red: 0, green: 0, blue: 0, alpha: 0.72), dark: .init(red: 1, green: 1, blue: 1, alpha: 0.72),
                lightIncreased: .init(red: 0, green: 0, blue: 0, alpha: 0.92), darkIncreased: .init(red: 1, green: 1, blue: 1, alpha: 0.92))
            public static let onDark = HassRGB.white
            public static let onDarkSecondary = HassRGB.white.opacity(0.85)
            public static let error = dynamic(light: (0.70, 0.11, 0.11), dark: Palette.red)
            public static let danger = dynamic(light: (0.76, 0.09, 0.09), dark: Palette.red)
            public static let warning = dynamic(light: (0.60, 0.33, 0.0), dark: Palette.orange)
            public static let action = dynamic(light: (0.0, 0.40, 0.80), dark: Palette.tintText)
            public static let success = HassRGB.adaptive(light: Palette.successLight, dark: Palette.success)
            public static let onSuccessFill = HassRGB.adaptive(light: 0xFFFFFF, dark: Palette.sheetGround)
            public static let unavailable = HassRGB.adaptive(light: Palette.unavailableLight, dark: Palette.unavailable)
            public static let actionFill = HassRGB(rgb: Palette.tintFill)
            public static let onFamilyFill = HassRGB(rgb: Palette.sheetGround)
            public static let badge = HassRGB(rgb: Palette.badge)

            /// ``HassTokens/Ink/track(increasedContrast:)``: the label at the track opacity.
            public static func track(increasedContrast increased: Bool) -> HassRGB {
                primary.opacity(increased ? Palette.trackOpacityIncreased : Palette.trackOpacity)
            }

            /// Light and dark variants; Increase Contrast moves each toward its extreme (``HassTokens/Ink/increasedContrast(_:isDark:)``).
            private static func dynamic(light: (Double, Double, Double), dark: UInt32) -> HassRGB {
                let d = HassRGB.Components(rgb: dark)
                let darkRGB = (d.red, d.green, d.blue)
                func components(_ rgb: (Double, Double, Double)) -> HassRGB.Components { .init(red: rgb.0, green: rgb.1, blue: rgb.2) }
                return HassRGB(
                    light: components(light), dark: components(darkRGB),
                    lightIncreased: components(HassTokens.Ink.increasedContrast(light, isDark: false)),
                    darkIncreased: components(HassTokens.Ink.increasedContrast(darkRGB, isDark: true)))
            }
        }

        /// ``HassTokens/Surface`` as sRGB.
        public enum Surface {
            public static let sheetGround = HassRGB.adaptive(light: Palette.sheetGroundLight, dark: Palette.sheetGround)
            public static let sheetCell = HassRGB.adaptive(light: Palette.sheetCellLight, dark: Palette.sheetCell)
            public static let moduleThin = HassRGB(rgb: Palette.moduleThin).opacity(0.66)
            public static let moduleDense = HassRGB(rgb: Palette.moduleDense).opacity(0.78)
            public static let separator = HassRGB.adaptive(
                light: Palette.secondaryLabelLight, lightAlpha: Palette.separatorLightOpacity,
                dark: 0xFFFFFF, darkAlpha: Palette.separatorDarkOpacity)
            public static let secondaryOnModule = HassRGB(rgb: Palette.secondaryLabel).opacity(HassTokens.Surface.secondaryOnModuleOpacity)
            public static let secondaryOnWash = HassRGB(rgb: Palette.secondaryLabel).opacity(HassTokens.Surface.secondaryOnWashOpacity)
            public static let secondaryOnWallpaper = HassRGB(rgb: Palette.secondaryLabel).opacity(HassTokens.Surface.secondaryOnWallpaperOpacity)
            public static let secondaryInSheet = HassRGB.adaptive(
                light: Palette.secondaryLabelLight, lightAlpha: Palette.secondaryInSheetLightOpacity,
                dark: Palette.secondaryLabel, darkAlpha: Palette.secondaryInSheetDarkOpacity)
        }
    }
}
