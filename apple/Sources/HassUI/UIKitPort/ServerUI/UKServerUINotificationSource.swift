#if os(iOS)
import HassCore
import Observation

// MARK: - Native permission intent lifetime

/// Pins the canonical system request through its asynchronous completion. No authored permission grant.
@MainActor
@Observable
final class UKServerUINotificationSource {
    private(set) var pendingNode: String?
    @ObservationIgnored private weak var push: PushCoordinator?

    init(push: PushCoordinator?) { self.push = push }
    var visible: Bool { push?.showsPermissionBanner == true }

    func enable(nodeID: String) {
        guard pendingNode == nil, let push, push.showsPermissionBanner else { return }
        pendingNode = nodeID
        Task {
            await push.enableNotifications()
            pendingNode = nil
        }
    }

    func dismiss() {
        guard pendingNode == nil else { return }
        push?.dismissPermissionBanner()
    }
}
#endif
