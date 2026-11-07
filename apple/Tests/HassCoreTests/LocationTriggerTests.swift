import Foundation
@testable import HassCore
import HassTestSupport
import Testing

/// Updates Home Assistant or the system asks for (push, Background App Refresh) and the reading used after an exit
/// answered with the zone's center (location parity PR B).
@MainActor
@Suite("Location triggers")
struct LocationTriggerTests {
    let ticks = LocationTestClock()
    let store = InMemoryZoneStore()
    let background = RecordingBackgroundTime()

    func reporter(_ platform: FakeLocationPlatform, _ transport: StubHTTPTransport) -> LocationReporter {
        LocationReporter(
            platform: platform,
            client: MobileAppWebhookClient(source: FixedMobileAppWebhookSource(mobileAppWebhook), transport: transport),
            linksPresence: true, now: { [ticks] in ticks.date }, zoneStore: store, backgroundTime: background
        )
    }

    func always() -> FakeLocationPlatform { FakeLocationPlatform(LocationPermission(authorization: .always)) }

    // MARK: Requested updates

    @Test func aRequestedUpdateHoldsBackgroundTimeAndCarriesItsTrigger() async throws {
        let platform = always()
        platform.fixes = [fixNorth(of: 0), fixNorth(of: 500, at: 1)]
        let transport = StubHTTPTransport(okReplies(4))
        let subject = reporter(platform, transport)
        await subject.start()
        let before = background.begun.count
        ticks.advance(1)
        #expect(await subject.requestUpdate(.pushNotification, inBackground: true))
        #expect(subject.lastTrigger == .pushNotification)
        #expect(background.begun.dropFirst(before) == ["Push Notification"])
        #expect(background.held == 0, "Released after the send")
        #expect(platform.timeouts.last == 10)
        #expect(try updateLocations(transport).count == 2)
    }

    @Test func aRequestedUpdateWaitsNoLongerThanTheBackgroundTimeAllows() async {
        let platform = always()
        platform.fixes = [fixNorth(of: 0), fixNorth(of: 500, at: 1)]
        let subject = reporter(platform, StubHTTPTransport(okReplies(4)))
        await subject.start()
        background.remaining = 8
        ticks.advance(1)
        await subject.requestUpdate(.backgroundFetch, inBackground: true)
        #expect(platform.timeouts.last == 3, "max(8 - 5, 1)")
    }

    @Test func aRequestedUpdateIsRefusedWhereTheFixCannotBeTaken() async {
        let platform = FakeLocationPlatform(LocationPermission(authorization: .whenInUse))
        platform.fixes = [fixNorth(of: 0), fixNorth(of: 500, at: 1)]
        let transport = StubHTTPTransport(okReplies(4))
        let subject = reporter(platform, transport)
        #expect(!subject.canReport(inBackground: false), "Not running yet")
        await subject.start()
        #expect(subject.canReport(inBackground: false))
        #expect(!subject.canReport(inBackground: true), "While Using has no background fixes")
        let requests = transport.requests.count
        #expect(!(await subject.requestUpdate(.pushNotification, inBackground: true)))
        #expect(transport.requests.count == requests)
        #expect(platform.fixes.count == 1, "No fix was even requested")
        ticks.advance(1)
        #expect(await subject.requestUpdate(.pushNotification, inBackground: false))
    }

    @Test func approximateLocationCannotReportInTheBackground() {
        let platform = FakeLocationPlatform(LocationPermission(authorization: .always, isPrecise: false))
        let subject = reporter(platform, StubHTTPTransport([]))
        #expect(!subject.canReport(inBackground: true))
    }

    @Test func startingWithoutALaunchUpdateSendsNone() async throws {
        let platform = always()
        platform.fixes = [fixNorth(of: 0)]
        let transport = StubHTTPTransport(okReplies(4))
        let subject = reporter(platform, transport)
        await subject.start(reportLaunch: false)
        #expect(try updateLocations(transport).isEmpty)
        #expect(subject.isRunning)
    }

    // MARK: After an exit with no fresh fix

    /// Leaves home (700 m away, no reading arrives), so the zone center is sent as `not_home`.
    func exitedWithNoReading(_ subject: LocationReporter, _ platform: FakeLocationPlatform) async {
        await subject.start()
        ticks.advance(100)
        await subject.handle(.zone(.exited("zone.home")))
    }

    @Test func aCachedReadingFromBeforeTheExitCannotAnswerTheNextReport() async throws {
        let platform = always()
        platform.fixes = [fixNorth(of: 0)]
        let transport = StubHTTPTransport(okReplies(8))
        let subject = reporter(platform, transport)
        await exitedWithNoReading(subject, platform)
        #expect(subject.lastTrigger == .regionExited)
        let sentSoFar = try updateLocations(transport).count
        #expect(sentSoFar == 2, "The launch update and the zone-center exit")

        // The launch update after the exit gets the cached reading from before the crossing (at home).
        platform.fixes = [fixNorth(of: 5, at: 50)]
        #expect(!(await subject.report(.launch)))
        #expect(platform.notBefores.last == ticks.date, "The exit's receipt time is the earliest acceptable reading")
        #expect(try updateLocations(transport).count == sentSoFar, "The stale reading was not sent")

        // A reading taken after the crossing is used, and lifts the restriction.
        ticks.advance(10)
        platform.fixes = [fixNorth(of: 700, at: 110)]
        #expect(await subject.report(.launch))
        let last = try #require(try updateLocations(transport).last)
        #expect(last["gps"] as? [Double] != nil)
        platform.fixes = [fixNorth(of: 1400, at: 130)]
        ticks.advance(20)
        #expect(await subject.report(.pushNotification))
        #expect(platform.notBefores.last == .some(nil), "A real reading after the exit ended the restriction")
    }

    @Test func aSignificantChangeAfterTheExitIgnoresReadingsFromBeforeIt() async throws {
        let platform = always()
        platform.fixes = [fixNorth(of: 0)]
        let transport = StubHTTPTransport(okReplies(8))
        let subject = reporter(platform, transport)
        await exitedWithNoReading(subject, platform)
        let sentSoFar = try updateLocations(transport).count
        // Its own fix is stale (fixes from before the exit) and so is the reading it carries: nothing is sent.
        ticks.advance(40)
        platform.fixes = [fixNorth(of: 5, at: 50)]
        await subject.handle(.significantChange(fixNorth(of: 5, at: 60)))
        #expect(try updateLocations(transport).count == sentSoFar)
        // A reading from after the exit is accepted.
        platform.fixes = [fixNorth(of: 800, at: 141)]
        ticks.advance(1)
        await subject.handle(.significantChange(fixNorth(of: 800, at: 141)))
        #expect(try updateLocations(transport).count == sentSoFar + 1)
        #expect(subject.lastTrigger == .significantLocationChange)
    }

    @Test func enteringAgainEndsTheRestriction() async {
        let platform = always()
        platform.fixes = [fixNorth(of: 0)]
        let subject = reporter(platform, StubHTTPTransport(okReplies(10)))
        await exitedWithNoReading(subject, platform)
        platform.fixes = [fixNorth(of: 5, at: 101)]
        ticks.advance(1)
        await subject.handle(.zone(.entered("zone.home")))
        platform.fixes = [fixNorth(of: 6, at: 130)]
        ticks.advance(30)
        _ = await subject.report(.launch)
        #expect(platform.notBefores.last == .some(nil))
    }

    @Test func stoppingForgetsTheRestriction() async {
        let platform = always()
        platform.fixes = [fixNorth(of: 0)]
        let subject = reporter(platform, StubHTTPTransport(okReplies(10)))
        await exitedWithNoReading(subject, platform)
        await subject.stop()
        platform.fixes = [fixNorth(of: 0, at: 200)]
        ticks.advance(100)
        await subject.start()
        #expect(platform.notBefores.last == .some(nil))
    }
}

// MARK: - Background App Refresh

@MainActor
private final class RecordingScheduler: BackgroundRefreshScheduler {
    struct Request: Equatable {
        let identifier: String
        let date: Date
    }

    var requests: [Request] = []
    var failure: (any Error)?

    func submit(identifier: String, earliestBeginDate: Date) throws {
        if let failure { throw failure }
        requests.append(Request(identifier: identifier, date: earliestBeginDate))
    }
}

@MainActor
private final class FakeRefreshTask: BackgroundRefreshTask {
    var onExpire: (@MainActor () -> Void)?
    var completions: [Bool] = []

    func complete(success: Bool) { completions.append(success) }
}

/// Waits on the test's say-so, so the work can be held open while a test expires the task.
@MainActor
private final class WorkGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var started = false
    private var openNow = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        started = true
        startWaiters.forEach { $0.resume() }
        startWaiters = []
        guard !openNow else { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func untilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func open() {
        openNow = true
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
@Suite("Background app refresh")
struct BackgroundRefreshTests {
    let ticks = LocationTestClock()
    private let scheduler = RecordingScheduler()

    @Test func theIdentifierFollowsTheBundleIDAndTheIntervalIsFifteenMinutes() {
        #expect(BackgroundRefresh.identifier == "com.sfenton.home.backgroundfetch")
        #expect(BackgroundRefresh.interval == 15 * 60)
    }

    @Test func scheduleAsksForFifteenMinutesAhead() {
        let refresh = BackgroundRefresh(scheduler: scheduler, now: { [ticks] in ticks.date }, work: { true })
        refresh.schedule()
        ticks.advance(60)
        refresh.schedule()
        #expect(scheduler.requests == [
            .init(identifier: BackgroundRefresh.identifier, date: Date(timeIntervalSince1970: 1_000_000 + 900)),
            .init(identifier: BackgroundRefresh.identifier, date: Date(timeIntervalSince1970: 1_000_000 + 960)),
        ])
        #expect(refresh.lastScheduleError == nil)
    }

    @Test func aRefusedRequestIsRememberedAndTheNextOneClearsIt() {
        struct Refused: Error {}
        let refresh = BackgroundRefresh(scheduler: scheduler, now: { [ticks] in ticks.date }, work: { true })
        scheduler.failure = Refused()
        refresh.schedule()
        #expect(refresh.lastScheduleError is Refused)
        scheduler.failure = nil
        refresh.schedule()
        #expect(refresh.lastScheduleError == nil)
        #expect(scheduler.requests.count == 1)
    }

    @Test func aRunSchedulesTheNextOneThenWorksAndCompletesOnce() async {
        var runs = 0
        let refresh = BackgroundRefresh(scheduler: scheduler, now: { [ticks] in ticks.date }, work: { runs += 1; return true })
        let task = FakeRefreshTask()
        await refresh.handle(task).value
        #expect(runs == 1)
        #expect(refresh.runCount == 1)
        #expect(scheduler.requests.count == 1, "Rescheduled inside the handler")
        #expect(task.completions == [true])
        #expect(task.onExpire == nil, "Nothing left to expire")
    }

    @Test func failedWorkCompletesTheTaskAsFailed() async {
        let refresh = BackgroundRefresh(scheduler: scheduler, now: { [ticks] in ticks.date }, work: { false })
        let task = FakeRefreshTask()
        await refresh.handle(task).value
        #expect(task.completions == [false])
        #expect(scheduler.requests.count == 1, "A failure still keeps the chain going")
    }

    @Test func expiryCancelsTheWorkAndCompletesExactlyOnce() async {
        let gate = WorkGate()
        let refresh = BackgroundRefresh(scheduler: scheduler, now: { [ticks] in ticks.date }, work: {
            await gate.wait()
            return true
        })
        let task = FakeRefreshTask()
        let running = refresh.handle(task)
        await gate.untilStarted()
        #expect(task.completions.isEmpty)
        task.onExpire?()
        #expect(task.completions == [false])
        gate.open()
        await running.value
        #expect(task.completions == [false], "The work finishing late does not complete the task again")
    }
}
