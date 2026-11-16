#if os(iOS)
import HassCore
import UIKit

// MARK: - Injected bedroom providers

/// Scene-owned providers. No ServerUI component discovers house configuration or creates a connection.
@MainActor
enum UKServerUIBedroomProvider {
    case bed(BedSideController)
    case wake(WakeLightController)
    case draft(ServerUIBedroomDraft)

    var identity: ObjectIdentifier {
        switch self {
        case .bed(let controller): ObjectIdentifier(controller)
        case .wake(let controller): ObjectIdentifier(controller)
        case .draft(let draft): ObjectIdentifier(draft)
        }
    }

    var available: Bool {
        switch self {
        case .bed(let controller): controller.sideAvailable
        case .wake(let controller): controller.live.available
        case .draft: true
        }
    }

    var kind: ServerUIBedroomControl.ProviderKind {
        switch self {
        case .bed: .bed
        case .wake: .wake
        case .draft(let draft):
            if case .bed = draft.value { .bedDraft } else { .wakeDraft }
        }
    }

    var protectsPublication: Bool {
        switch self {
        case .bed(let controller): controller.hasPendingCommands
        case .wake(let controller): controller.hasPendingCommands
        case .draft(let draft): draft.protectsPublication
        }
    }

    var error: String? {
        switch self {
        case .bed(let controller):
            controller.commandError ?? (controller.overlay.failures.isEmpty ? nil : "Home Assistant did not respond.")
        case .wake(let controller): controller.error
        case .draft(let draft): draft.error ?? draft.problems.first
        }
    }
}
#endif
