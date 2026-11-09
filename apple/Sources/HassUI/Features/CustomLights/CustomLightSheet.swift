import HassCore
import HassDesign
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// One custom light's sheet (web `LightMoreInfoSheet.tsx`): its brightness tile (an action tile with a `power` disc) and, for color lights, the color,
/// Reset to Warm White and Apply to All Lights rows, and one swatch per other light to copy that light's color
/// (direction G, n4 custom light sheet).
///
/// The web draws a hue wheel and RGB sliders; the app uses the system color picker instead (HIG: Color wells),
/// which offers the same wheel, sliders and eyedropper and is familiar to VoiceOver users.
enum CustomLightSheet {
    /// "On · 80%", "Off" or "Unavailable".
    static func subtitle(_ state: EntityState?) -> String {
        guard let state, !state.isUnavailable else { return "Unavailable" }
        let percent = LightControl.percent(of: state)
        return percent > 0 ? "On · \(percent)%" : "Off"
    }
}

extension HassServiceCalling {
    /// Fire-and-forget call for view actions; failures surface through the entity's state.
    func fire(_ serviceCall: ServiceCall) {
        Task { try? await call(serviceCall) }
    }
}

extension CustomLightsConfig.RGB {
    #if canImport(UIKit)
    /// ``init(color:)`` for a UIKit picker, so the UIKit port needs no SwiftUI `Color`.
    init?(uiColor: UIColor) { self.init(color: Color(uiColor: uiColor)) }
    #endif

    /// A picked color in sRGB, rounded to 0...255 per channel; `nil` when it can't be converted.
    init?(color: Color) {
        // `Color.resolve(in:)` is SwiftUI's own conversion; its CGColor is converted to sRGB for the 0...255 channels.
        let resolved = color.resolve(in: EnvironmentValues()).cgColor
        guard let srgb = CGColorSpace(name: CGColorSpace.sRGB),
              let converted = resolved.converted(to: srgb, intent: .defaultIntent, options: nil),
              let components = converted.components, components.count >= 3 else { return nil }
        let (red, green, blue) = (components[0], components[1], components[2])
        func channel(_ value: CGFloat) -> Int { Int((min(1, max(0, value)) * 255).rounded()) }
        self.init(channel(red), channel(green), channel(blue))
    }
}
