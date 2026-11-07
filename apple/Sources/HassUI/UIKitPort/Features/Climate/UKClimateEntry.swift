#if os(iOS)
import HassCore
import UIKit

// Owned by the Climate lane: the Climate tab (`ClimateScreen`).
extension UKScreens {
    static func climate(_ context: UKContext) -> UIViewController { UKClimateViewController(context: context) }
}
#endif
