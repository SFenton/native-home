#if os(iOS)
import HassCore
import UIKit

// Owned by the Rooms lane (`.agents/platforms/apple/uikit-port.md`).
extension UKScreens {
    static func room(_ id: String, _ context: UKContext) -> UIViewController {
        guard let page = RoomsConfig.page(id: id) else { return UKPlaceholderViewController(title: id, symbol: "house") }
        return UKRoomViewController(page: page, context: context)
    }

    /// The Quick Links header sheet; `choose` pushes a route after the sheet closes.
    static func quickLinks(_ context: UKContext, choose: @escaping (HomeRoute) -> Void) -> UIViewController {
        UKQuickLinks.make(context: context, choose: choose)
    }

    static func media(_ context: UKContext) -> UIViewController { UKMediaViewController(context: context) }
    static func customLights(_ context: UKContext) -> UIViewController { UKCustomLightsViewController(context: context) }
    static func sprinklers(_ context: UKContext) -> UIViewController { UKSprinklersViewController(context: context) }
}
#endif
