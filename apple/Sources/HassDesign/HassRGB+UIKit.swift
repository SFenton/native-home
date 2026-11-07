#if canImport(UIKit) && !os(watchOS)
import UIKit

public extension UIColor {
    /// The UIKit colour for a ``HassRGB`` token, built without SwiftUI. A fixed token is a plain colour; an adaptive one is a
    /// dynamic colour that resolves with the view's trait collection (appearance and Increase Contrast).
    convenience init(_ rgb: HassRGB) {
        func plain(_ c: HassRGB.Components) -> UIColor { UIColor(red: c.red, green: c.green, blue: c.blue, alpha: c.alpha) }
        if rgb.isFixed {
            let c = rgb.light
            self.init(red: c.red, green: c.green, blue: c.blue, alpha: c.alpha)
        } else {
            self.init { traits in
                plain(rgb.components(isDark: traits.userInterfaceStyle == .dark,
                                     increasedContrast: traits.accessibilityContrast == .high))
            }
        }
    }
}
#endif
