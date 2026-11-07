#if os(iOS)
import HassCore
import UIKit

// Owned by the Settings lane (`.agents/platforms/apple/uikit-port.md`).
extension UKScreens {
    /// The Settings tab's root page (``SettingsTabRoot``).
    static func settings(_ context: UKContext) -> UIViewController { UKSettingsViewController(context: context) }

    /// A pushed Settings topic (``SettingsRouteDestination``).
    static func destination(for route: SettingsRoute, context: UKContext) -> UIViewController {
        switch route {
        case .vacation: UKScreens.vacation(context)
        case .adminTodo: UKSettingsHooks.adminTodo(context)
        case .performance: UKPerformanceViewController(context: context)
        }
    }
}

/// Pages the Settings list pushes that other lanes build: the Chores lane replaces `adminTodo` at
/// launch (a closure, like ``UKShellHooks``), so this lane never reaches into their folders.
@MainActor
enum UKSettingsHooks {
    static var adminTodo: (UKContext) -> UIViewController = { UKScreens.adminTodo($0) }
}
#endif
