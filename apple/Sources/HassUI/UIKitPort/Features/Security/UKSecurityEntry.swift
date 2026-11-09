#if os(iOS)
import HassCore
import UIKit

// Owned by the Security lane: the Security tab's root page (`SecurityScreen`).
extension UKScreens {
    static func security(_ context: UKContext) -> UIViewController {
        guard let caller = context.caller ?? context.connection else { return UKPlaceholderViewController(title: "Security", symbol: "lock.shield") }
        let connection = context.connection
        return UKSecurityViewController(
            context: context, caller: caller,
            // Whether a command can go out now (web `connectionCannotSend`: not while disconnected or suspended).
            canSend: { connection.map { SecurityScreen.canSend($0.status) } ?? true },
            showsCameras: true, showsVehicle: SecurityConfig.showsVehicleSection)
    }
}
#endif
