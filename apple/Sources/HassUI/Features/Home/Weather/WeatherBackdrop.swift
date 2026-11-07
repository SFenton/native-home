import HassCore
import HassDesign
import SwiftUI

/// The condition-aware gradient behind the weather card and sheet (web `WeatherAtmosphere`).
///
/// Every scene is dark enough for white text at 4.5:1 or better (the lightest stop is at least 5.6:1), so text keeps
/// its contrast whatever the condition. Decoration (stars, cloud banks, rain, snow) is drawn at low opacity and only
/// animates when Reduce Motion is off; with Reduce Transparency on, it is left out and the gradient stays solid.
/// HIG: Color (contrast), Motion, Accessibility (Reduce Motion, Reduce Transparency).
struct WeatherBackdrop {
    var scene: WeatherScene



    /// Top and bottom gradient stops for a scene.
    static func colors(for scene: WeatherScene) -> (top: Color, bottom: Color) {
        let tokens = colorTokens(for: scene)
        return (Color(tokens.top), Color(tokens.bottom))
    }

    /// ``colors(for:)`` as raw sRGB.
    static func colorTokens(for scene: WeatherScene) -> (top: HassRGB, bottom: HassRGB) {
        switch scene {
        case .sunny: (HassRGB(red: 0.13, green: 0.40, blue: 0.78), HassRGB(red: 0.05, green: 0.17, blue: 0.40))
        case .night: (HassRGB(red: 0.07, green: 0.09, blue: 0.27), HassRGB(red: 0.02, green: 0.03, blue: 0.10))
        case .clouds: (HassRGB(red: 0.28, green: 0.36, blue: 0.46), HassRGB(red: 0.11, green: 0.15, blue: 0.22))
        case .fog: (HassRGB(red: 0.34, green: 0.39, blue: 0.44), HassRGB(red: 0.15, green: 0.18, blue: 0.22))
        case .rain: (HassRGB(red: 0.20, green: 0.28, blue: 0.40), HassRGB(red: 0.07, green: 0.11, blue: 0.19))
        case .storm: (HassRGB(red: 0.19, green: 0.16, blue: 0.33), HassRGB(red: 0.06, green: 0.05, blue: 0.13))
        case .snow: (HassRGB(red: 0.30, green: 0.40, blue: 0.52), HassRGB(red: 0.12, green: 0.18, blue: 0.28))
        case .wind: (HassRGB(red: 0.14, green: 0.40, blue: 0.46), HassRGB(red: 0.05, green: 0.16, blue: 0.20))
        case .exceptional: (HassRGB(red: 0.45, green: 0.25, blue: 0.12), HassRGB(red: 0.17, green: 0.09, blue: 0.05))
        case .neutral: (HassRGB(red: 0.22, green: 0.30, blue: 0.42), HassRGB(red: 0.08, green: 0.11, blue: 0.18))
        }
    }
}
