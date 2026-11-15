#if os(iOS)
import HassCore
import HassDesign

// MARK: - Read-only shell projection

/// Closures read the existing account/connection models inside native observation; no session or service is exposed.
@MainActor
struct UKServerUIShellHeaderSource {
    let state: @MainActor () -> UKShellHeaderItems.State
    let avatar: @MainActor () -> AvatarBox?

    init(state: @escaping @MainActor () -> UKShellHeaderItems.State, avatar: @escaping @MainActor () -> AvatarBox? = { nil }) {
        self.state = state; self.avatar = avatar
    }
}
#endif
