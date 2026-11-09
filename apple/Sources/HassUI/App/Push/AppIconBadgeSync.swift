import Foundation
import HassCore
#if os(iOS)
import UserNotifications
#endif

/// Keeps the app icon's badge equal to the Profile button's attention count (`.agents/platforms/apple/badge.md`).
///
/// The count is computed in the app from entity states (``ShellAttention``), so the badge is set while the app runs and
/// whenever the count changes; it is cleared on sign-out. The system setter is injectable for tests.
@MainActor
public final class AppIconBadgeSync {
    /// UserDefaults key for Settings → Appearance → Show count on app icon (default on).
    public static let enabledKey = "showAppIconBadge"

    /// The app's shared instance, which sets the real badge.
    public static let shared = AppIconBadgeSync()

    private let setter: @Sendable (Int) async -> Void
    private let defaults: UserDefaults
    private var lastApplied: Int?

    /// Creates a sync.
    /// - Parameters:
    ///   - defaults: Where the on/off setting lives.
    ///   - setter: Sets the badge count; defaults to `UNUserNotificationCenter.setBadgeCount`.
    public init(defaults: UserDefaults = .standard, setter: (@Sendable (Int) async -> Void)? = nil) {
        self.defaults = defaults
        self.setter = setter ?? Self.systemSetter
    }

    /// Whether the person wants the count on the icon.
    public var isEnabled: Bool { defaults.object(forKey: Self.enabledKey) as? Bool ?? true }

    /// Applies the attention count: the count when enabled, else 0. Skips repeats.
    public func update(count: Int) async {
        let target = isEnabled ? max(0, count) : 0
        guard target != lastApplied else { return }
        lastApplied = target
        await setter(target)
    }

    /// Clears the badge (sign-out). Always sets, even when the last value was already 0.
    public func clear() async {
        lastApplied = 0
        await setter(0)
    }

    private static let systemSetter: @Sendable (Int) async -> Void = { count in
        #if os(iOS)
        try? await UNUserNotificationCenter.current().setBadgeCount(count)
        #endif
    }
}
