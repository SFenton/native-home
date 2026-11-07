#if os(iOS)
import HassDesign
import UIKit

// MARK: - Fonts

/// Dynamic Type fonts the way SwiftUI's `.font(.subheadline.bold())` draws them: the text style's preferred font at the view's
/// content size category, with a weight and tabular digits added. Views rebuild their fonts when the category changes
/// (``UIView/ukOnContentSizeChange(_:)``) rather than relying on `adjustsFontForContentSizeCategory`, which does not follow a
/// weight added through a descriptor on every iOS version.
extension UKFont {
    /// `HassTokens.Typography.tileTitle`: subheadline, bold.
    static func tileTitle(_ traits: UITraitCollection? = nil) -> UIFont { preferred(.subheadline, weight: .bold, traits: traits) }
    /// `HassTokens.Typography.rowTitle`: subheadline, semibold.
    static func rowTitle(_ traits: UITraitCollection? = nil, monospacedDigit: Bool = false) -> UIFont {
        preferred(.subheadline, weight: .semibold, monospacedDigit: monospacedDigit, traits: traits)
    }
    /// `HassTokens.Typography.bodyEmphasis`: body, semibold.
    static func bodyEmphasis(_ traits: UITraitCollection? = nil) -> UIFont { preferred(.body, weight: .semibold, traits: traits) }
    /// `HassTokens.Typography.footnoteEmphasis`: footnote, semibold.
    static func footnoteEmphasis(_ traits: UITraitCollection? = nil) -> UIFont { preferred(.footnote, weight: .semibold, traits: traits) }
    /// `HassTokens.Typography.sectionTitle`: title3, bold.
    static func sectionTitle(_ traits: UITraitCollection? = nil) -> UIFont { preferred(.title3, weight: .bold, traits: traits) }

    /// A metric scaled with Dynamic Type relative to a text style (`@ScaledMetric(relativeTo:)`).
    static func scaled(_ value: CGFloat, relativeTo style: UIFont.TextStyle, traits: UITraitCollection? = nil) -> CGFloat {
        UIFontMetrics(forTextStyle: style).scaledValue(for: value, compatibleWith: traits)
    }

    /// An SF Symbol image at a text style's font, the way `Image(systemName:).font(style)` draws it.
    static func symbol(_ name: String, style: UIFont.TextStyle, weight: UIFont.Weight? = nil, filled: Bool = false,
                       traits: UITraitCollection? = nil) -> UIImage? {
        let font = preferred(style, weight: weight, traits: traits)
        let configuration = UIImage.SymbolConfiguration(font: font)
        if filled, let image = UIImage(systemName: name + ".fill", withConfiguration: configuration) { return image }
        return UIImage(systemName: name, withConfiguration: configuration)
    }
}

extension UITraitCollection {
    /// An accessibility Dynamic Type size (`DynamicTypeSize.isAccessibilitySize`).
    var ukIsAccessibilitySize: Bool { preferredContentSizeCategory.isAccessibilityCategory }
}

extension UIView {
    /// Runs `change` now and again whenever the content size category changes.
    func ukOnContentSizeChange(_ change: @escaping @MainActor () -> Void) {
        change()
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (_: Self, _) in change() }
    }
}

// MARK: - Colour

extension UIColor {
    /// A colour with a different dynamic value in light and dark user interface styles.
    static func ukDynamic(light: UIColor, dark: UIColor) -> UIColor {
        UIColor { $0.userInterfaceStyle == .dark ? dark : light }
    }

    /// Red, green, blue and alpha in sRGB.
    var ukRGBA: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b, a)
    }

    /// This colour drawn over `background`, flattened to one colour that composites the same way (`FinishColor.flatten`): fewer
    /// layers per tile, since a layer is real cost on a page of 120 tiles.
    func ukOver(_ background: UIColor) -> UIColor {
        let top = ukRGBA, bottom = background.ukRGBA
        let alpha = top.a + bottom.a * (1 - top.a)
        guard alpha > 0 else { return .clear }
        func channel(_ t: CGFloat, _ b: CGFloat) -> CGFloat { (t * top.a + b * bottom.a * (1 - top.a)) / alpha }
        return UIColor(red: channel(top.r, bottom.r), green: channel(top.g, bottom.g), blue: channel(top.b, bottom.b), alpha: alpha)
    }

    /// The `0xRRGGBB` colour at `opacity`.
    static func ukRGB(_ rgb: UInt32, _ opacity: CGFloat = 1) -> UIColor { UIColor(rgb: rgb, alpha: opacity) }

    /// This colour with its alpha multiplied by `opacity` (SwiftUI's `.opacity`).
    func ukOpacity(_ opacity: CGFloat) -> UIColor {
        UIColor { traits in
            let resolved = self.resolvedColor(with: traits)
            return resolved.withAlphaComponent(resolved.ukRGBA.a * opacity)
        }
    }
}

/// Inks for the Settings-style pages. One token so a footer on the wallpaper cannot drift to another ink.
enum UKSettingsInk {
    /// A section footer drawn straight over the shared wallpaper. Full white: the photo is mid-grey in places and the system's
    /// secondary label (3.9:1) and the 85% wallpaper ink (4.0:1) both failed the contrast audit; white clears 4.5:1 over its
    /// darkest-to-lightest range. Sheets keep the system secondary ink.
    static let wallpaperFooter = UIColor.white
}

/// Palette colours that HassDesign keeps as SwiftUI dynamic `Color`s, rebuilt as UIKit dynamic colours from the same raw values.
enum UKInk {
    /// Titles and values (`HassTokens.Ink.primary`).
    static let primary = UIColor.label
    /// Supporting text (`HassTokens.Ink.secondary`): the label colour at 72%, 92% with Increase Contrast.
    static let secondary = UIColor { traits in
        UIColor.label.resolvedColor(with: traits).withAlphaComponent(traits.accessibilityContrast == .high ? 0.92 : 0.72)
    }
    /// `HassTokens.Ink.onDarkSecondary`: white at 85%.
    static let onDarkSecondary = UIColor.white.withAlphaComponent(0.85)
    /// The sheet's cell: `#2C2C2E` dark, white light (`HassTokens.Surface.sheetCell`).
    static let sheetCell = UIColor.ukDynamic(light: .ukRGB(HassTokens.Palette.sheetCellLight), dark: .ukRGB(HassTokens.Palette.sheetCell))
    /// The sheet's ground (`HassTokens.Surface.sheetGround`).
    static let sheetGround = UIColor.ukDynamic(light: .ukRGB(HassTokens.Palette.sheetGroundLight), dark: .ukRGB(HassTokens.Palette.sheetGround))
    /// Hairlines (`HassTokens.Surface.separator`).
    static let separator = UIColor.ukDynamic(
        light: .ukRGB(HassTokens.Palette.secondaryLabelLight, HassTokens.Palette.separatorLightOpacity),
        dark: .ukRGB(0xFFFFFF, HassTokens.Palette.separatorDarkOpacity))
    /// Secondary text in sheets (`HassTokens.Surface.secondaryInSheet`).
    static let secondaryInSheet = UIColor.ukDynamic(
        light: .ukRGB(HassTokens.Palette.secondaryLabelLight, HassTokens.Palette.secondaryInSheetLightOpacity),
        dark: .ukRGB(HassTokens.Palette.secondaryLabel, HassTokens.Palette.secondaryInSheetDarkOpacity))
    /// The thin module tint on the wallpaper: `#1C1C1E` at 66%.
    static let moduleThin = UIColor.ukRGB(HassTokens.Palette.moduleThin, 0.66)
    /// The dense module: `#141416` at 78%.
    static let moduleDense = UIColor.ukRGB(HassTokens.Palette.moduleDense, 0.78)
    /// A running timer's orange (`HassTokens.Ink.timer`).
    static let timer = UIColor.ukDynamic(light: .ukRGB(HassTokens.Palette.timerLight), dark: .ukRGB(HassTokens.Palette.timer))
    /// `HassTokens.Ink.danger`.
    static let danger = UIColor(HassTokens.RGB.Ink.danger)
    /// `HassTokens.Ink.warning`.
    static let warning = UIColor(HassTokens.RGB.Ink.warning)
    /// `HassTokens.Ink.action`.
    static let action = UIColor(HassTokens.RGB.Ink.action)

    /// The module tint for a density, opaque with Reduce Transparency (`ModuleBackground.tint`).
    static func module(_ density: ModuleDensity, reduceTransparency: Bool) -> UIColor {
        switch (density, reduceTransparency) {
        case (.thin, false): moduleThin
        case (.dense, false): moduleDense
        case (.thin, true): .ukRGB(HassTokens.Palette.moduleThin)
        case (.dense, true): .ukRGB(HassTokens.Palette.moduleDense)
        }
    }
}

// MARK: - Environment the SwiftUI views read

/// The values tiles read from the SwiftUI environment, made explicit. A grid sets one on every tile it draws; the defaults are a
/// tile on a page.
struct UKTileEnvironment: Equatable {
    /// Where tiles are drawn (`EnvironmentValues.tileSurface`).
    var surface: TileSurface = .page
    /// The preferred finish (`.tileFinish(_:)`).
    var finish: TileFinish = .standard
    /// The arrangement (`.tileLayout(_:)`).
    var layout: TileLayout = .standard
    /// Lines of title to keep room for (`.tileTitleLines(_:)`).
    var titleLines = 0
    /// Tiles stretch to the height their cell gives them (`.equalHeightTiles()`). A UIKit cell always does; this only keeps the
    /// SwiftUI name.
    var fillsHeight = true
    /// Subtitles stay on one line, shrinking to 85% (`.tileSingleLineSubtitle()`).
    var singleLineSubtitle = false
    /// The first values have not arrived: tiles draw a soft bar for their value (`EnvironmentValues.valuesPending`).
    var valuesPending = false

    init() {}

    /// The environment for a screen context.
    @MainActor init(context: UKContext) {
        surface = context.surface
        valuesPending = context.valuesPending
    }
}

/// App-wide switches the SwiftUI environment carries.
@MainActor
enum UKDesign {
    /// Holds every continuous animation still (`EnvironmentValues.animationsPaused`): galleries and UI tests only.
    static var animationsPaused = false

    /// Reduce Motion is on.
    static var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }

    /// Tiles draw the solid finish: Reduce Transparency or Increase Contrast (`TileFinish.effective`).
    static func effectiveFinish(_ preferred: TileFinish, traits: UITraitCollection) -> TileFinish {
        TileFinish.effective(preferred, reduceTransparency: UIAccessibility.isReduceTransparencyEnabled,
                             increasedContrast: traits.accessibilityContrast == .high)
    }

    /// The light or dark appearance of a tile's neutral parts (`TileAppearance.resolve`).
    static func tileAppearance(surface: TileSurface, traits: UITraitCollection) -> TileAppearance {
        .resolve(surface: surface, scheme: traits.userInterfaceStyle == .light ? .light : .dark)
    }
}

// MARK: - Motion

/// The animation vocabulary of `MotionTokens` for UIKit and Core Animation.
@MainActor
extension UKMotion {
    /// The length of a state colour cross-fade: 0.6 s, or 0.2 s under Reduce Motion (`MotionTokens.state` / `stateReduced`).
    static var stateDuration: TimeInterval {
        UKDesign.reduceMotion ? MotionTokens.stateReducedDuration : MotionTokens.stateDuration
    }

    /// `MotionTokens.quick`: ease out, 0.2 s.
    static let quickDuration: TimeInterval = MotionTokens.quickDuration

    /// Runs `changes` to layer properties with the state cross-fade (an `easeInOut` of ``stateDuration``).
    static func stateFade(_ component: String, animated: Bool, _ changes: () -> Void) {
        MotionAudit.noteStateColor(component)
        CATransaction.begin()
        if animated {
            CATransaction.setAnimationDuration(stateDuration)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        } else {
            CATransaction.setDisableActions(true)
        }
        changes()
        CATransaction.commit()
    }

    /// Runs `changes` to layer properties with the quick ease-out (a band gliding, a bubble fading). Jumps with Reduce Motion
    /// when `jumpsWithReduceMotion` (`motionSafeAnimation(quick)` with no reduced animation).
    static func quick(animated: Bool = true, _ changes: () -> Void) {
        CATransaction.begin()
        if animated, !UKDesign.reduceMotion {
            CATransaction.setAnimationDuration(quickDuration)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        } else {
            CATransaction.setDisableActions(true)
        }
        changes()
        CATransaction.commit()
    }

    /// Cross-fades a view's colours (a label's text colour, a glyph's tint) while `changes` recolours it. Set any new text before
    /// calling, so only the colour fades, as `stateForeground` does.
    static func stateFade(_ component: String, view: UIView, animated: Bool, _ changes: @escaping () -> Void) {
        MotionAudit.noteStateColor(component)
        guard animated, view.window != nil else {
            changes()
            return
        }
        UIView.transition(with: view, duration: stateDuration, options: [.transitionCrossDissolve, .allowUserInteraction, .curveEaseInOut],
                          animations: changes)
    }
}

// MARK: - Haptics

/// The one haptic vocabulary (`TapFeedback`): a light impact for a tap, a selection tick per detent, an error haptic for a failed
/// call, a success haptic for a read.
@MainActor
enum UKTapFeedback {
    private static let impact = UIImpactFeedbackGenerator(style: .light)
    private static let selection = UISelectionFeedbackGenerator()
    private static let notification = UINotificationFeedbackGenerator()

    /// A tap on a switch, key or command (`TapFeedback.tap`).
    static func tap() { impact.impactOccurred() }
    /// One detent of a slider or dial (`TapFeedback.step`).
    static func step() { selection.selectionChanged() }
    /// A call that failed (`TapFeedback.failure`).
    static func failure() { notification.notificationOccurred(.error) }
    /// A scan or other input that was read (`TapFeedback.confirmation`).
    static func confirmation() { notification.notificationOccurred(.success) }
}

// MARK: - Notifications

/// Notification observers that end with their owner.
final class UKObserverTokens: @unchecked Sendable {
    private let tokens: [NSObjectProtocol]
    init(_ tokens: [NSObjectProtocol]) { self.tokens = tokens }
    deinit { for token in tokens { NotificationCenter.default.removeObserver(token) } }
}

extension NotificationCenter {
    /// Calls `handler` on the main actor whenever Reduce Motion, Reduce Transparency or Increase Contrast change, or the app returns
    /// to the foreground. Keep the result for as long as the observation should live.
    @MainActor
    func ukObserveAccessibility(_ handler: @escaping @MainActor () -> Void) -> UKObserverTokens {
        UKObserverTokens([UIAccessibility.reduceMotionStatusDidChangeNotification, UIAccessibility.reduceTransparencyStatusDidChangeNotification,
                          UIAccessibility.darkerSystemColorsStatusDidChangeNotification, UIApplication.didBecomeActiveNotification].map {
            addObserver(forName: $0, object: nil, queue: .main) { _ in MainActor.assumeIsolated { handler() } }
        })
    }
}
#endif
