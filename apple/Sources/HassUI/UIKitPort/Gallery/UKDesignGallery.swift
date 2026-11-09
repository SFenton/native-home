#if os(iOS) && DEBUG
import HassCore
import HassDesign
import UIKit

// Owned by the design tiles lane. Pages: performance, direction-g.
//
// Page chrome (the wallpaper backdrop and the header fade) belongs to the shell lane and is not there yet: these pages sit in a
// `UINavigationController` on a dark ground (`UKGalleryGround`) until the shell provides it.
extension UKGallery {
    static func design(_ page: ComponentGallery.Page) -> UIViewController? {
        switch page {
        case .performance: UKPerformanceGallery.make()
        case .directionG: UKDirectionGGallery.make()
        default: nil
        }
    }
}

/// The ground a gallery page sits on until the shell's wallpaper lands: the web shell's `#111723`, the base of `HouseBackdropStyle`.
enum UKGalleryGround {
    static let color = UIColor(red: 17 / 255, green: 23 / 255, blue: 35 / 255, alpha: 1)

    /// A navigation controller with large titles on the dark ground, always dark like the pages of the app.
    @MainActor
    static func navigation(root: UIViewController) -> UINavigationController {
        let navigation = UINavigationController(rootViewController: root)
        navigation.overrideUserInterfaceStyle = .dark
        navigation.navigationBar.prefersLargeTitles = true
        return navigation
    }
}
#endif
