import Foundation
import Observation

/// How soft the house photo behind every page is (Settings → Appearance → Background Blur; pattern:
/// `.agents/patterns/page-backdrop.md`).
///
/// The setting is a percentage of ``maxRadius``; 50 is the default, which equals the web dashboard's blur on screen:
/// `ha-sfenton-react-dash@f5a7bf9:src/components/shell/AppShell.module.css:58-65` blurs the photo by `16px` and then
/// scales the element by `1.05`, so the blur on screen is `16 × 1.05 = 16.8` CSS px, which is 16.8 pt (CSS px and
/// points are the same length; Core Image's `CIGaussianBlur.inputRadius` and CSS `blur()` are both the Gaussian's
/// standard deviation).
public enum BackdropBlur {
    /// The web's `filter: blur(16px)`.
    public static let webRadius = 16.0
    /// The web's `transform: scale(1.05)`, applied after the filter, so it magnifies the blur too.
    public static let webScale = 1.05
    /// The default blur on screen in points: the web's, `16 × 1.05`.
    public static let defaultRadius = webRadius * webScale
    /// The blur at 100%: twice the default, so the default sits in the middle of the slider.
    public static let maxRadius = defaultRadius * 2

    /// The slider's range, in percent.
    public static let percentRange = 0...100
    /// The default setting: ``defaultRadius`` is half of ``maxRadius``.
    public static let defaultPercent = 50
    /// The slider's step in percent (VoiceOver adjusts by one step).
    public static let step = 5
    /// The `UserDefaults` key holding the percentage.
    public static let defaultsKey = "backdropBlurPercent"

    /// `percent` forced into ``percentRange``.
    public static func clamp(_ percent: Int) -> Int {
        min(max(percent, percentRange.lowerBound), percentRange.upperBound)
    }

    /// The blur on screen in points for a setting (clamped first).
    public static func radius(forPercent percent: Int) -> Double {
        Double(clamp(percent)) / Double(percentRange.upperBound) * maxRadius
    }

    /// The setting a stored value means: missing or not a number is the default; out of range is clamped.
    public static func percent(fromStored stored: Any?) -> Int {
        guard let number = stored as? NSNumber else { return defaultPercent }
        return clamp(Int(number.doubleValue.rounded()))
    }

    /// How a setting reads: `50%`.
    public static func label(forPercent percent: Int) -> String { "\(clamp(percent))%" }

    /// How VoiceOver reads it: `50 percent`.
    public static func spokenValue(forPercent percent: Int) -> String { "\(clamp(percent)) percent" }
}

/// The saved Background Blur percentage, observable so the Settings slider and the backdrop share it.
///
/// ``onChange`` is how the backdrop store learns to re-render; the setting persists to `UserDefaults` at once.
@MainActor
@Observable
public final class BackdropBlurSettings {
    /// The setting in percent, always within ``BackdropBlur/percentRange``; change it with ``set(_:)``.
    public private(set) var percent: Int

    /// Called with the new percentage after a change.
    @ObservationIgnored public var onChange: (@MainActor (Int) -> Void)?
    @ObservationIgnored private let defaults: UserDefaults

    /// Creates the settings from what is saved.
    /// - Parameter defaults: Where the setting lives; tests pass a throwaway suite.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        percent = BackdropBlur.percent(fromStored: defaults.object(forKey: BackdropBlur.defaultsKey))
    }

    /// Saves a new setting (clamped) and calls ``onChange`` when it differs from the current one.
    public func set(_ newValue: Int) {
        let clamped = BackdropBlur.clamp(newValue)
        guard clamped != percent else { return }
        percent = clamped
        defaults.set(clamped, forKey: BackdropBlur.defaultsKey)
        onChange?(clamped)
    }

    /// The setting as a slider's value (0 to 100), so a view can bind to it directly.
    public var sliderValue: Double {
        get { Double(percent) }
        set { set(Int(newValue.rounded())) }
    }

    /// The blur on screen in points.
    public var radius: Double { BackdropBlur.radius(forPercent: percent) }

    /// Whether the setting is the default (the Reset button is disabled then).
    public var isDefault: Bool { percent == BackdropBlur.defaultPercent }

    /// Back to the web-matched default.
    public func reset() { set(BackdropBlur.defaultPercent) }
}

/// Everything that decides how one blurred render looks and how it is cached (the pure half of the backdrop store).
///
/// A render is the photo covering the window, magnified by ``scale`` (direction G), saturated and blurred by the
/// setting's radius in points. Where the blur is wide the render is made at a fraction of the window's pixel size
/// (``divisor``): a Gaussian of 8 px or more loses nothing visible when it is drawn at half or a quarter of the
/// resolution, and the view scales it back up, so the file and the Core Image pass shrink 4 to 16 times.
public struct BackdropRenderSpec: Hashable, Sendable {
    /// The photo's magnification over the window (direction G; the web's is 1.05).
    public static let scale = 1.06
    /// The longest side of a render's window in pixels; larger screens are rendered at a lower density.
    public static let maxPixels = 3072
    /// The smallest blur (in render pixels) at which a render may be made at a lower resolution.
    public static let minimumSigma = 8.0
    /// The largest ``divisor``.
    public static let maxDivisor = 4
    /// Names a recipe: changing the look (saturation, scale, color space, ordering) bumps it so an older file is
    /// never read for the new look.
    public static let recipe = "r3"

    /// The window's width in pixels.
    public let pixelWidth: Int
    /// The window's height in pixels.
    public let pixelHeight: Int
    /// Pixels per point after capping at ``maxPixels``.
    public let pixelsPerPoint: Double
    /// The Background Blur setting in percent.
    public let percent: Int

    /// Creates the spec for a window; nil while the window has no size.
    /// - Parameters:
    ///   - points: The window's size in points.
    ///   - displayScale: The screen's pixels per point.
    ///   - percent: The Background Blur setting (clamped).
    public init?(points: CGSize, displayScale: Double, percent: Int) {
        guard points.width >= 1, points.height >= 1, displayScale > 0 else { return nil }
        let longest = max(points.width, points.height) * displayScale
        let density = (min(longest, Double(Self.maxPixels)) / longest * displayScale * 1000).rounded() / 1000
        pixelsPerPoint = density
        pixelWidth = max(1, Int((points.width * density).rounded()))
        pixelHeight = max(1, Int((points.height * density).rounded()))
        self.percent = BackdropBlur.clamp(percent)
    }

    /// The blur's standard deviation in window pixels.
    public var sigmaPixels: Double { BackdropBlur.radius(forPercent: percent) * pixelsPerPoint }

    /// How many times smaller than the window the render is made: 1 for a sharp or lightly blurred render, up to
    /// ``maxDivisor`` for a wide one, keeping the blur at least ``minimumSigma`` render pixels.
    public var divisor: Int { min(Self.maxDivisor, max(1, Int(sigmaPixels / Self.minimumSigma))) }

    /// The render's width in pixels.
    public var renderWidth: Int { Int((Double(pixelWidth) / Double(divisor)).rounded(.up)) }
    /// The render's height in pixels.
    public var renderHeight: Int { Int((Double(pixelHeight) / Double(divisor)).rounded(.up)) }

    /// The blur's standard deviation in render pixels.
    public var renderSigma: Double { sigmaPixels / Double(divisor) }

    /// The cache file for this spec and a photo: the recipe, the photo's digest, the window's pixels and density, and
    /// the setting. Anything that changes the picture changes the name.
    public func cacheName(photo: String) -> String {
        "backdrop-\(Self.recipe)-\(photo)-\(pixelWidth)x\(pixelHeight)-d\(Int((pixelsPerPoint * 1000).rounded()))-b\(percent).jpg"
    }
}
