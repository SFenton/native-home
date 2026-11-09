#if os(iOS)
import HassCore
import HassDesign
import UIKit

/// The page's chip rail: the chips of one page in a ``UKChipRailView`` (scrolls in compact width, wraps in regular, stops short of a
/// hinge).
@MainActor
enum UKSecurityStatusRail {
    /// The Security and Contact Sensors chips (`SECURITY_STATUS_CHIPS`).
    static var chips: [HomeConfig.StatusChip] { HomeConfig.statusChips.filter { [.security, .contacts].contains($0.sheet) } }

    static func make(context: UKContext, bag: UKObservationBag, idPrefix: String = "security",
                     onOpen: @escaping (HomeConfig.ChipSheet) -> Void) -> UKChipRailView {
        UKStatusRail.make(chips: chips, idPrefix: idPrefix, context: context, bag: bag, onOpen: onOpen)
    }
}
#endif
