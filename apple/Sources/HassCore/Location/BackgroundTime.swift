import Foundation

/// Holds the app awake while a location event is being reported. iOS gives a relaunched app about ten seconds and
/// may suspend it mid-send otherwise. The app's implementation wraps `UIApplication.beginBackgroundTask`
/// (`HassUI`, which is app-only); tests record the calls.
@MainActor
public protocol BackgroundTime: AnyObject {
    /// Starts holding time for `name`.
    /// - Returns: A closure that releases the hold; calling it twice is harmless.
    func begin(_ name: String) -> @MainActor () -> Void
    /// Seconds of background time left; `.infinity` while the app is in the foreground. Whatever a conformer returns,
    /// callers clamp it with ``OneShotFix/waitLimit(backgroundRemaining:maximum:)`` before sleeping.
    var remaining: TimeInterval { get }
}

/// Holds nothing.
@MainActor
public final class NoBackgroundTime: BackgroundTime {
    public init() {}
    public func begin(_ name: String) -> @MainActor () -> Void { {} }
    public var remaining: TimeInterval { .infinity }
}
