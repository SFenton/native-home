#if os(iOS)
import HassCore
import UIKit

extension UKScreens {
    /// The Home tab's root (`HomeScreen`).
    static func home(_ context: UKContext) -> UIViewController { UKHomeViewController(context: context) }
}
#endif
