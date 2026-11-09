import Foundation

/// Which app icon the person picked, shared with the widget extension through the app group so the card's corner mark
/// follows it (`.agents/platforms/apple/live-activities-per-job.md` §8, "Corner mark").
///
/// The app writes the `AppIconChoice` raw value at launch and whenever the icon changes; the widget only reads it, and
/// falls back to the default (Navy + Sky) when nothing is there. A change shows on the card's next update.
public struct ActivityAppIconStore: @unchecked Sendable {
    /// The app group the app and the extension share (`com.apple.security.application-groups`).
    public static let appGroup = "group.com.sfenton.home"
    /// The key inside the group's defaults.
    public static let key = "appIconChoice"
    /// What the widget uses when the app has not written a choice (the app's own icon).
    public static let fallback = "navySky"

    private let defaults: UserDefaults?

    /// A store over `defaults`; nil reads and writes nothing (an app group that is not available).
    public init(defaults: UserDefaults?) {
        self.defaults = defaults
    }

    /// The store over the real app group.
    public static var shared: ActivityAppIconStore { ActivityAppIconStore(defaults: UserDefaults(suiteName: appGroup)) }

    /// The stored choice (an `AppIconChoice` raw value), or ``fallback``.
    public var choice: String {
        guard let raw = defaults?.string(forKey: Self.key), !raw.isEmpty else { return Self.fallback }
        return raw
    }

    /// Stores the choice.
    public func write(_ rawValue: String) {
        defaults?.set(rawValue, forKey: Self.key)
    }
}
