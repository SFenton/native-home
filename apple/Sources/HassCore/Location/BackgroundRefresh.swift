import Foundation

/// Submits Background App Refresh requests to the system. The app's implementation wraps `BGTaskScheduler`
/// (`HassUI`, app only); tests record the requests.
@MainActor
public protocol BackgroundRefreshScheduler: AnyObject {
    /// Asks the system to run the refresh task `identifier` no earlier than `earliestBeginDate`. A request with the
    /// same identifier replaces the pending one.
    /// - Throws: When the system refuses (Background App Refresh off, the simulator, too many requests).
    func submit(identifier: String, earliestBeginDate: Date) throws
}

/// The system's handle on one running refresh (`BGAppRefreshTask`), reduced to what the controller needs.
@MainActor
public protocol BackgroundRefreshTask: AnyObject {
    /// Set by the controller; the system calls it when time runs out.
    var onExpire: (@MainActor () -> Void)? { get set }
    /// Tells the system the work is over (`setTaskCompleted(success:)`). Called exactly once.
    func complete(success: Bool)
}

/// Background App Refresh, as the official app does it (`home-assistant/iOS` `BackgroundRefreshManager`): a
/// `BGAppRefreshTask` requested for 15 minutes ahead at launch, whenever the app enters the background and again
/// inside every run, whose work is a location update with the Background Fetch trigger
/// (`.agents/platforms/apple/location.md`). iOS decides when, and whether, it actually runs: usually a few times a
/// day for an app the person opens often, never after a force quit or with Background App Refresh off.
@MainActor
public final class BackgroundRefresh {
    /// The task identifier: the bundle id plus `.backgroundfetch`. It must be listed under
    /// `BGTaskSchedulerPermittedIdentifiers` in `apple/project.yml`, and the task must be registered before launch finishes.
    public static let identifier = "com.sfenton.home.backgroundfetch"
    /// How far ahead each request asks to run (seconds).
    public static let interval: TimeInterval = 15 * 60

    /// The last error from submitting a request, nil after a success.
    public private(set) var lastScheduleError: (any Error)?
    /// Runs scheduled so far, for diagnostics and tests.
    public private(set) var runCount = 0

    private let scheduler: any BackgroundRefreshScheduler
    private let now: @MainActor () -> Date
    private let work: @MainActor () async -> Bool

    /// Creates the controller.
    /// - Parameters:
    ///   - scheduler: Submits requests to the system.
    ///   - now: The clock.
    ///   - work: The refresh itself; returns whether it succeeded. Cancelled when the system expires the task.
    public init(scheduler: any BackgroundRefreshScheduler, now: @escaping @MainActor () -> Date = { .now },
                work: @escaping @MainActor () async -> Bool) {
        self.scheduler = scheduler
        self.now = now
        self.work = work
    }

    /// Requests the next refresh for ``interval`` seconds from now. A refusal is remembered, not thrown: the next
    /// launch, background transition or run asks again.
    public func schedule() {
        do {
            try scheduler.submit(identifier: Self.identifier, earliestBeginDate: now().addingTimeInterval(Self.interval))
            lastScheduleError = nil
        } catch {
            lastScheduleError = error
        }
    }

    /// Runs the refresh the system started: requests the next one first (so a failure or an expiry cannot end the
    /// chain), runs ``work``, and completes the task exactly once, with failure if the system expires it first.
    /// - Returns: The running work, for tests to await.
    @discardableResult
    public func handle(_ task: some BackgroundRefreshTask) -> Task<Void, Never> {
        runCount += 1
        schedule()
        var finished = false
        let finish: @MainActor (Bool) -> Void = { success in
            guard !finished else { return }
            finished = true
            task.onExpire = nil
            task.complete(success: success)
        }
        let running = Task { @MainActor [work] in
            let succeeded = await work()
            finish(succeeded && !Task.isCancelled)
        }
        task.onExpire = {
            running.cancel()
            finish(false)
        }
        return running
    }
}
