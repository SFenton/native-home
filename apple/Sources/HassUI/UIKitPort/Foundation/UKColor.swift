#if os(iOS)
import HassDesign
import UIKit

extension UIColor {
    /// A colour from `0xRRGGBB` sRGB, as ``SwiftUI/Color/init(rgb:)`` draws it (``HassTokens/Palette``).
    convenience init(rgb: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: alpha
        )
    }
}
#endif
