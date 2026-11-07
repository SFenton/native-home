#if os(iOS)
import BackgroundTasks
import HassCore
import UIKit

/// ``BackgroundRefresh`` on `BGTaskScheduler`: the app's Background App Refresh
/// (`.agents/platforms/apple/location.md`). iOS-only glue; the rules live in ``BackgroundRefresh``, which tests drive
/// with fakes. Not verifiable without a device: `BGTaskScheduler` refuses requests in the simulator, and iOS alone
/// decides when a refresh runs.
@MainActor
public final class SystemBackgroundRefresh {
    private let refresh: BackgroundRefresh
    private var backgroundObserver: (any NSObjectProtocol)?

    /// Creates the refresh and registers its launch handler, which iOS requires before the app finishes launching:
    /// call this from `application(_:didFinishLaunchingWithOptions:)`, before it returns.
    /// - Parameter work: The refresh itself; returns whether it succeeded.
    public init(work: @escaping @MainActor () async -> Bool) {
        refresh = BackgroundRefresh(scheduler: BGScheduler(), work: work)
        let refresh = refresh
        BGTaskScheduler.shared.register(forTaskWithIdentifier: BackgroundRefresh.identifier, using: .main) { task in
            MainActor.assumeIsolated { refresh.handle(AppRefreshTask(task)) }
        }
        // The SwiftUI scene life cycle does not call the app delegate's applicationDidEnterBackground.
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { refresh.schedule() }
        }
    }

    /// Requests the next refresh (launch).
    public func schedule() { refresh.schedule() }

    /// Submits requests to `BGTaskScheduler`.
    @MainActor private final class BGScheduler: BackgroundRefreshScheduler {
        func submit(identifier: String, earliestBeginDate: Date) throws {
            let request = BGAppRefreshTaskRequest(identifier: identifier)
            request.earliestBeginDate = earliestBeginDate
            try BGTaskScheduler.shared.submit(request)
        }
    }

    /// A running `BGAppRefreshTask`.
    @MainActor private final class AppRefreshTask: BackgroundRefreshTask {
        private let task: BGTask
        var onExpire: (@MainActor () -> Void)? {
            didSet {
                task.expirationHandler = onExpire.map { handler in { MainActor.assumeIsolated { handler() } } }
            }
        }

        init(_ task: BGTask) { self.task = task }

        func complete(success: Bool) { task.setTaskCompleted(success: success) }
    }
}
#endif
