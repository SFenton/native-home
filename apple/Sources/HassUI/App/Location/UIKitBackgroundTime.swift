#if os(iOS)
import HassCore
import UIKit

/// ``BackgroundTime`` on `UIApplication.beginBackgroundTask`: a relaunched app is suspended again after about ten
/// seconds unless a task holds it, which could cut a location send short. Released on completion or, at the latest,
/// when iOS calls the expiration handler.
@MainActor
final class UIKitBackgroundTime: BackgroundTime {
    /// In the foreground (or when iOS reports "no limit", which it does as `DBL_MAX`) there is no limit: `.infinity`.
    var remaining: TimeInterval {
        let app = UIApplication.shared
        guard app.applicationState == .background else { return .infinity }
        let left = app.backgroundTimeRemaining
        return left >= .greatestFiniteMagnitude / 2 ? .infinity : left
    }

    func begin(_ name: String) -> @MainActor () -> Void {
        let hold = Hold()
        // iOS calls the expiration handler on the main thread and expects the task ended before it returns.
        hold.identifier = UIApplication.shared.beginBackgroundTask(withName: name) { MainActor.assumeIsolated { hold.end() } }
        return { hold.end() }
    }

    @MainActor
    private final class Hold {
        var identifier = UIBackgroundTaskIdentifier.invalid

        func end() {
            guard identifier != .invalid else { return }
            UIApplication.shared.endBackgroundTask(identifier)
            identifier = .invalid
        }
    }
}
#endif
