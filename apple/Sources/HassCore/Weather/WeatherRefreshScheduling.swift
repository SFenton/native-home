import Foundation

/// Starts and cancels the store's refresh timer; tests drive it by hand.
@MainActor
public protocol WeatherRefreshScheduling: AnyObject {
    /// Runs `action` once after `interval` seconds.
    /// - Returns: A closure that cancels it.
    func schedule(after interval: TimeInterval, _ action: @escaping @MainActor () -> Void) -> @MainActor () -> Void
}
