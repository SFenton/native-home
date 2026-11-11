import Foundation
@testable import HassCore
import HassTestSupport
import Testing

/// The forecast cache rules from `useWeatherForecasts.test.tsx`: TTL, retry, revision refetch, pruning,
/// never blanking, plus the native disk restore.
@MainActor
@Suite(.demoHouse)
struct WeatherForecastStoreTests {
    struct Harness {
        var store: WeatherForecastStore
        var caller: FakeWeatherCaller
        var scheduler: ManualWeatherScheduler
        var clock: WeatherTestClock
    }

    private func makeHarness(
        server: HassServer? = nil, cache: WeatherForecastDiskCache? = nil, timeout: TimeInterval = 20, clock: WeatherTestClock = WeatherTestClock(),
        entityId: @escaping @MainActor () -> String = { HomeConfig.weatherEntityId }
    ) -> Harness {
        let scheduler = ManualWeatherScheduler()
        let store = WeatherForecastStore(
            entityId: entityId(), server: server, cache: cache, timeZone: TimeZone(identifier: "UTC")!, requestTimeout: timeout,
            scheduler: scheduler, clock: { clock.now }
        )
        return Harness(store: store, caller: FakeWeatherCaller(), scheduler: scheduler, clock: clock)
    }

    private func temperature(_ feed: WeatherForecastFeed) -> Double? { feed.forecasts.first?.temperature }

    @Test func refreshesBothKindsAtTheTTLAndOncePerRevision() async {
        let h = makeHarness()
        var temp = 60.0
        h.caller.respond = { _ in WeatherFixtures.response(temperature: temp) }
        h.store.activate(caller: h.caller, revision: "initial")
        await h.store.settle()
        #expect(h.caller.calls == [.daily, .hourly])
        #expect(h.caller.lastData["entity_id"] as? String == "weather.demo_weather_1")
        #expect(h.scheduler.armedCount == 1)
        #expect(h.store.daily.phase == .ready)

        temp = 71
        h.clock.advance(WeatherForecastStore.timeToLive)
        h.scheduler.fire()
        await h.store.settle()
        #expect(h.caller.calls.count == 4)
        #expect(temperature(h.store.hourly) == 71)
        #expect(temperature(h.store.daily) == 71)

        temp = 82
        h.store.update(revision: "new-source")
        await h.store.settle()
        #expect(h.caller.calls.count == 6)
        #expect(temperature(h.store.hourly) == 82)

        h.store.update(revision: "new-source")
        await h.store.settle()
        #expect(h.caller.calls.count == 6)
    }

    @Test func aSecondConsumerSharesFreshDataAndInFlightWork() async {
        let h = makeHarness()
        h.caller.holds = true
        h.store.activate(caller: h.caller, revision: "a")
        h.store.activate(caller: h.caller, revision: "a")
        await h.caller.waitForCalls(2)
        #expect(h.caller.calls.count == 2)

        h.store.deactivate()
        h.caller.resolve(.daily, with: WeatherFixtures.response(temperature: 66))
        h.caller.resolve(.hourly, with: WeatherFixtures.response(temperature: 67))
        await h.store.settle()
        #expect(temperature(h.store.daily) == 66)
        #expect(temperature(h.store.hourly) == 67)

        h.store.deactivate()
        #expect(h.scheduler.armedCount == 0)
        h.store.activate(caller: h.caller, revision: "a")
        await h.store.settle()
        #expect(h.caller.calls.count == 2)
        #expect(h.scheduler.armedCount == 1)
    }

    @Test func coalescesSourceChangesWhileARequestIsInFlight() async {
        let h = makeHarness()
        h.caller.holds = true
        h.store.activate(caller: h.caller, revision: "a")
        await h.caller.waitForCalls(2)
        #expect(h.store.hourly.phase == .loading)
        h.store.update(revision: "b")
        h.store.update(revision: "c")
        #expect(h.caller.calls.count == 2)

        h.caller.resolve(.daily, with: WeatherFixtures.response(temperature: 61))
        h.caller.resolve(.hourly, with: WeatherFixtures.response(temperature: 62))
        await h.caller.waitForCalls(4)
        #expect(h.caller.calls.count == 4)
        #expect(temperature(h.store.daily) == 61)
        #expect(temperature(h.store.hourly) == 62)
        #expect(h.store.hourly.refreshing)

        h.caller.resolve(.hourly, with: WeatherFixtures.response(temperature: 82))
        h.caller.resolve(.daily, with: WeatherFixtures.response(temperature: 81))
        await h.store.settle()
        #expect(h.caller.calls.count == 4)
        #expect(temperature(h.store.daily) == 81)
        #expect(temperature(h.store.hourly) == 82)
        #expect(!h.store.hourly.refreshing)
    }

    @Test func doesNothingWithoutAConsumerAndNeverStartsQueuedWorkOnceHidden() async {
        let h = makeHarness()
        h.store.refresh()
        #expect(h.caller.calls.isEmpty)
        #expect(h.scheduler.armedCount == 0)

        h.store.activate(caller: h.caller, revision: "a")
        h.store.setForeground(false)
        await h.store.settle()
        #expect(h.caller.calls.isEmpty)
        #expect(h.scheduler.armedCount == 0)
        #expect(h.store.hourly.phase == .idle)

        h.store.setForeground(true)
        await h.store.settle()
        #expect(h.caller.calls.count == 2)
        #expect(h.store.hourly.phase == .ready)
    }

    @Test func manyBackgroundAndForegroundCyclesLeaveOneTimerAndNoFetchesBehind() async {
        let h = makeHarness()
        h.store.activate(caller: h.caller, revision: "a")
        await h.store.settle()
        let launch = h.store.liveResources
        #expect(launch["Weather.consumers"] == 1)
        #expect(launch["Weather.timer"] == 1)
        for _ in 0..<10 {
            h.store.setForeground(false)
            #expect(h.store.liveResources["Weather.timer"] == 0, "No timer runs in the background")
            h.store.setForeground(true)
            await h.store.settle()
            #expect(h.scheduler.armedCount == 1)
        }
        #expect(h.store.liveResources == launch)
        h.store.deactivate()
        #expect(h.store.liveResources["Weather.timer"] == 0)
    }

    @Test func pausesInTheBackgroundAndRefreshesOnceOnReturn() async {
        let h = makeHarness()
        h.store.activate(caller: h.caller, revision: "a")
        await h.store.settle()
        h.store.setForeground(false)
        #expect(h.scheduler.armedCount == 0)
        h.clock.advance(7 * 60)
        h.store.update(revision: "b")
        #expect(h.caller.calls.count == 2)
        h.store.setForeground(true)
        h.store.setForeground(true)
        await h.store.settle()
        #expect(h.caller.calls.count == 4)
        #expect(h.scheduler.armedCount == 1)
    }

    @Test(arguments: [false, true])
    func exposesErrorsAndRetriesWithoutATightLoop(cached: Bool) async {
        let h = makeHarness()
        struct Offline: LocalizedError { var errorDescription: String? { "HA offline" } }
        if !cached { h.caller.respond = { _ in throw Offline() } }
        h.store.activate(caller: h.caller, revision: "a")
        await h.store.settle()
        if cached {
            h.caller.respond = { _ in throw Offline() }
            h.clock.advance(WeatherForecastStore.timeToLive)
            h.scheduler.fire()
            await h.store.settle()
        }
        for (kind, feed) in [(WeatherForecastKind.daily, h.store.daily), (.hourly, h.store.hourly)] {
            #expect(feed.phase == .error)
            #expect(feed.error == WeatherCopy.forecastFailure(kind), "the server's words never reach the card")
            #expect(!feed.refreshing)
            #expect(feed.forecasts.count == (cached ? 1 : 0))
            #expect((feed.updatedAt != nil) == cached)
        }
        let attempts = h.caller.calls.count
        h.clock.advance(WeatherForecastStore.timeToLive - 1)
        h.store.refresh()
        await h.store.settle()
        #expect(h.caller.calls.count == attempts)

        h.caller.respond = { _ in WeatherFixtures.response(temperature: 99) }
        h.clock.advance(1)
        h.store.refresh()
        await h.store.settle()
        #expect(h.caller.calls.count == attempts + 2)
        #expect(h.store.hourly.phase == .ready)
        #expect(h.store.hourly.error == nil)
        #expect(temperature(h.store.hourly) == 99)
    }

    /// A mutable weather id standing in for the house document arriving after the store is built.
    @MainActor private final class LateID { var value = "" }

    @Test func anEmptyWeatherIdSendsNothingAndStaysPending() async {
        let late = LateID()
        let h = makeHarness(entityId: { late.value })
        h.store.activate(caller: h.caller, revision: nil)
        await h.store.settle()
        h.store.update(revision: "r")
        h.store.setConnected(false)
        h.store.setConnected(true)
        await h.store.settle()
        #expect(h.caller.calls.isEmpty, "no weather.get_forecasts with entity_id \"\"")
        for feed in [h.store.daily, h.store.hourly] {
            #expect(feed.showsPlaceholders, "pending: the card shows placeholders")
            #expect(feed.error == nil)
            #expect(!feed.refreshing)
        }
        #expect(h.scheduler.armedCount == 0, "nothing is due, so no timer spins")
    }

    @Test func anIdThatArrivesLaterMakesTheFirstCallCarryIt() async {
        let late = LateID()
        let h = makeHarness(entityId: { late.value })
        h.store.activate(caller: h.caller, revision: nil)
        await h.store.settle()
        #expect(h.caller.calls.isEmpty)

        late.value = WeatherFixtures.entityId
        h.store.update(revision: nil)
        await h.store.settle()
        #expect(h.caller.calls == [.daily, .hourly])
        #expect(h.caller.lastData["entity_id"] as? String == WeatherFixtures.entityId)
        #expect(h.store.daily.phase == .ready)
    }

    @Test func aSchemaRejectShowsDeckCopyNotTheServersText() async {
        struct Schema: LocalizedError { var errorDescription: String? { "expected 'all' or 'none' at 'entity_id'" } }
        let h = makeHarness()
        h.caller.respond = { _ in throw Schema() }
        h.store.activate(caller: h.caller, revision: "a")
        await h.store.settle()
        #expect(h.store.daily.error == WeatherCopy.forecastFailure(.daily))
        #expect(h.store.hourly.error == WeatherCopy.forecastFailure(.hourly))
        #expect(h.store.daily.phase == .error)
    }

    @Test func emptyResponsesClearPreviousValues() async {
        let h = makeHarness()
        h.store.activate(caller: h.caller, revision: "a")
        await h.store.settle()
        h.caller.respond = { _ in WeatherFixtures.response(entries: []) }
        h.store.update(revision: "b")
        await h.store.settle()
        for feed in [h.store.daily, h.store.hourly] {
            #expect(feed.phase == .empty)
            #expect(feed.forecasts.isEmpty)
            #expect(feed.error == nil)
            #expect(!feed.refreshing)
        }
    }

    @Test(arguments: [JSONValue.null, .object([:]), .object([WeatherFixtures.entityId: .object([:])]), .string("nope")])
    func malformedEnvelopesAreFailuresNotEmptySuccess(value: JSONValue) async {
        let h = makeHarness()
        h.caller.respond = { _ in value }
        h.store.activate(caller: h.caller, revision: nil)
        await h.store.settle()
        #expect(h.store.daily.phase == .error)
        #expect(h.store.daily.updatedAt == nil)
        #expect(h.store.hourly.error == "Unable to load Pirate Weather hourly forecast.")
        #expect(h.store.daily.error == "Unable to load Pirate Weather forecast.")
    }

    @Test func readsWrappedServiceResponsesAndRecoversFromThrows() async {
        let h = makeHarness()
        h.caller.respond = { _ in throw WeatherForecastError(message: "Disconnected") }
        h.store.activate(caller: h.caller, revision: "a")
        await h.store.settle()
        #expect(h.store.hourly.error == WeatherCopy.forecastFailure(.hourly))
        h.caller.respond = { _ in WeatherFixtures.response(temperature: 75, wrapped: true) }
        h.store.update(revision: "b")
        await h.store.settle()
        #expect(temperature(h.store.hourly) == 75)
    }

    @Test func expiresPastHourlyBucketsExactlyAtTheirEndWhileARefreshIsPending() async {
        let clock = WeatherTestClock(HassDates.iso8601("2026-09-05T12:59:00Z")!)
        let h = makeHarness(clock: clock)
        let entries = [
            WeatherFixtures.entry("2026-09-05T11:00:00Z", 50),
            WeatherFixtures.entry("2026-09-05T12:00:00Z", 60),
            WeatherFixtures.entry("2026-09-05T13:00:00Z", 70),
        ]
        h.caller.respond = { _ in WeatherFixtures.response(entries: entries) }
        h.store.activate(caller: h.caller, revision: "a")
        await h.store.settle()
        #expect(h.store.hourly.forecasts.map(\.temperature) == [60, 70])
        // The timer is armed for the first bucket's end: one minute away.
        #expect(h.scheduler.armed?.interval == 60)

        h.caller.holds = true
        h.store.update(revision: "b")
        await h.caller.waitForCalls(4)
        clock.advance(60)
        h.scheduler.fire()
        #expect(h.store.hourly.forecasts.map(\.temperature) == [70])
        #expect(h.store.hourly.refreshing)
        #expect(h.caller.calls.count == 4)
        h.caller.reject(.daily, with: WeatherForecastError.connectionLost)
        h.caller.reject(.hourly, with: WeatherForecastError.connectionLost)
        await h.store.settle()
    }

    @Test func aFullyExpiredHourlyListBecomesEmpty() async {
        let h = makeHarness()
        // The only bucket ends three minutes from now, before the five-minute refresh is due.
        h.caller.respond = { _ in WeatherFixtures.response(entries: [WeatherFixtures.entry("2026-09-05T11:33:00Z", 60)]) }
        h.store.activate(caller: h.caller, revision: "a")
        await h.store.settle()
        #expect(h.store.hourly.phase == .ready)
        #expect(h.scheduler.armed?.interval == 180)
        h.clock.advance(180)
        h.scheduler.fire()
        #expect(h.store.hourly.forecasts.isEmpty)
        #expect(h.store.hourly.phase == .empty)
        #expect(h.store.hourly.showsPlaceholders == false)
        #expect(h.caller.calls.count == 2)
    }

    @Test func keepsCachedForecastsQuietWhenTheConnectionDropsThenRetriesOnReconnect() async {
        let h = makeHarness()
        h.store.activate(caller: h.caller, revision: "a")
        await h.store.settle()
        h.caller.respond = { _ in throw WeatherForecastError.connectionLost }
        h.store.update(revision: "b")
        await h.store.settle()
        #expect(h.caller.calls.count == 4)
        for feed in [h.store.daily, h.store.hourly] {
            #expect(feed.error == nil)
            #expect(!feed.refreshing)
            #expect(feed.phase == .ready)
            #expect(temperature(feed) == 60)
        }

        h.store.setConnected(false)
        h.clock.advance(WeatherForecastStore.timeToLive)
        h.store.refresh()
        await h.store.settle()
        #expect(h.caller.calls.count == 4)

        h.caller.respond = { _ in WeatherFixtures.response(temperature: 88) }
        h.store.setConnected(true)
        await h.store.settle()
        #expect(h.caller.calls.count == 6)
        #expect(h.store.daily.phase == .ready)
        #expect(temperature(h.store.hourly) == 88)
    }

    @Test func staysLoadingWithoutAnErrorAfterADropAndBacksOffFiveThenTenSeconds() async {
        let h = makeHarness()
        h.caller.respond = { _ in throw URLError(.networkConnectionLost) }
        h.store.activate(caller: h.caller, revision: "a")
        await h.store.settle()
        #expect(h.caller.calls.count == 2)
        for feed in [h.store.daily, h.store.hourly] {
            #expect(feed.error == nil)
            #expect(feed.forecasts.isEmpty)
            #expect(!feed.refreshing)
            #expect(feed.phase == .loading)
            #expect(feed.showsPlaceholders)
        }
        #expect(h.scheduler.armed?.interval == WeatherForecastStore.retryInterval)

        h.clock.advance(WeatherForecastStore.retryInterval - 1)
        h.store.refresh()
        await h.store.settle()
        #expect(h.caller.calls.count == 2)

        h.clock.advance(1)
        h.scheduler.fire()
        await h.store.settle()
        #expect(h.caller.calls.count == 4)
        #expect(h.scheduler.armed?.interval == WeatherForecastStore.retryInterval * 2)

        h.caller.respond = { _ in WeatherFixtures.response(temperature: 64) }
        h.clock.advance(WeatherForecastStore.retryInterval * 2)
        h.scheduler.fire()
        await h.store.settle()
        #expect(h.caller.calls.count == 6)
        #expect(h.store.daily.phase == .ready)
        #expect(temperature(h.store.hourly) == 64)
        #expect(h.scheduler.armed?.interval == WeatherForecastStore.timeToLive)
    }

    @Test func notReadyMessagesCountAsInterruptions() async {
        struct NotReady: LocalizedError { var errorDescription: String? { "callService: connection not established or not ready" } }
        #expect(WeatherForecastStore.isConnectionInterruption(NotReady()))
        #expect(WeatherForecastStore.isConnectionInterruption(CancellationError()))
        #expect(WeatherForecastStore.isConnectionInterruption(URLError(.timedOut)))
        #expect(!WeatherForecastStore.isConnectionInterruption(URLError(.badURL)))
        #expect(!WeatherForecastStore.isConnectionInterruption(WeatherForecastError(message: "Unauthorized")))
    }

    @Test func defersTheFirstRequestWhileDisconnected() async {
        let h = makeHarness()
        h.store.activate(caller: h.caller, revision: "a", connected: false)
        await h.store.settle()
        #expect(h.caller.calls.isEmpty)
        #expect(h.store.daily.phase == .idle)
        #expect(h.scheduler.armedCount == 0)
        h.store.setConnected(true)
        await h.store.settle()
        #expect(h.caller.calls.count == 2)
        #expect(h.store.daily.phase == .ready)
    }

    @Test func aRequestThatNeverAnswersIsTreatedAsADroppedConnection() async {
        let h = makeHarness(timeout: 0.05)
        h.caller.holds = true
        h.store.activate(caller: h.caller, revision: "a")
        await h.store.settle()
        #expect(h.caller.calls.count == 2)
        #expect(h.store.daily.error == nil)
        #expect(h.store.daily.phase == .loading)
        #expect(h.scheduler.armed?.interval == WeatherForecastStore.retryInterval)
    }

    @Test func resetForgetsEverythingIncludingTheDiskCopy() async throws {
        let cache = WeatherFixtures.temporaryCache()
        let h = makeHarness(server: .example, cache: cache)
        h.store.activate(caller: h.caller, revision: "a")
        await h.store.settle()
        #expect(cache.load(for: .example) != nil)
        h.store.reset()
        #expect(cache.load(for: .example) == nil)
        #expect(h.store.daily == WeatherForecastFeed())
        #expect(h.store.briefing == nil)
        #expect(h.scheduler.armedCount == 0)
    }

    // MARK: - Disk

    @Test func persistsGoodForecastsAndRestoresThemBeforeAnyNetworkWork() async throws {
        let cache = WeatherFixtures.temporaryCache()
        let first = makeHarness(server: .example, cache: cache)
        first.caller.respond = { kind in
            WeatherFixtures.response(entries: kind == .daily
                ? [WeatherFixtures.entry("2026-09-05T00:00:00Z", 72)]
                : [WeatherFixtures.entry("2026-09-05T12:00:00Z", 68), WeatherFixtures.entry("2026-09-05T13:00:00Z", 69)])
        }
        first.store.activate(caller: first.caller, revision: "a")
        await first.store.settle()
        let snapshot = try #require(cache.load(for: .example))
        #expect(snapshot.daily.count == 1)
        #expect(snapshot.hourly.count == 2)

        // A cold launch: the new store has data immediately and has made no call yet.
        let second = makeHarness(server: .example, cache: cache)
        #expect(second.store.daily.phase == .ready)
        #expect(second.store.hourly.forecasts.map(\.temperature) == [68, 69])
        #expect(second.store.hourly.showsPlaceholders == false)
        #expect(second.caller.calls.isEmpty)

        // Activating refetches (the restored copy is never treated as fresh) without blanking.
        second.caller.holds = true
        second.store.activate(caller: second.caller, revision: "a")
        await second.caller.waitForCalls(2)
        #expect(second.store.hourly.refreshing)
        #expect(second.store.hourly.forecasts.count == 2)
        #expect(second.store.hourly.phase == .ready)
        second.caller.reject(.daily, with: WeatherForecastError.connectionLost)
        second.caller.reject(.hourly, with: WeatherForecastError.connectionLost)
        await second.store.settle()
        cache.clear()
    }

    @Test func restoreDropsHourlyBucketsThatAlreadyPassed() throws {
        let cache = WeatherFixtures.temporaryCache()
        let snapshot = WeatherForecastDiskCache.Snapshot(
            version: WeatherForecastDiskCache.currentVersion, server: HassServer.example.baseURL, savedAt: Date(),
            daily: [], dailyUpdatedAt: nil,
            hourly: [
                WeatherForecast(datetime: "2026-09-05T10:00:00Z", temperature: 50),
                WeatherForecast(datetime: "2026-09-05T12:00:00Z", temperature: 60),
            ],
            hourlyUpdatedAt: nil, briefing: nil
        )
        try cache.save(snapshot)
        let h = makeHarness(server: .example, cache: cache)
        #expect(h.store.hourly.forecasts.map(\.temperature) == [60])
        #expect(h.store.daily.phase == .idle)
        cache.clear()
    }

    @Test func ignoresASnapshotFromAnotherServerOrAnOldFormat() throws {
        let cache = WeatherFixtures.temporaryCache()
        let other = HassServer(baseURL: URL(string: "https://other.example")!)
        let stale = WeatherForecastDiskCache.Snapshot(
            version: 99, server: other.baseURL, savedAt: Date(), daily: [WeatherForecast(temperature: 1)], dailyUpdatedAt: nil,
            hourly: [], hourlyUpdatedAt: nil, briefing: nil
        )
        try cache.save(stale)
        #expect(cache.load(for: other) == nil)
        var fresh = stale
        fresh.version = WeatherForecastDiskCache.currentVersion
        try cache.save(fresh)
        #expect(cache.load(for: .example) == nil)
        #expect(makeHarness(server: .example, cache: cache).store.daily.phase == .idle)
        #expect(cache.load(for: other)?.daily.first?.temperature == 1)
        cache.clear()
    }

    // MARK: - Briefing

    @Test func writesTheBriefingOncePerDayAndRestoresItFromDisk() async {
        let cache = WeatherFixtures.temporaryCache()
        let h = makeHarness(server: .example, cache: cache)
        let context = WeatherBriefingContext(temperatureUnit: "°F", windSpeedUnit: "mph")
        h.store.updateBriefing(context)
        #expect(h.store.briefing == nil)

        h.caller.respond = { kind in
            WeatherFixtures.response(entries: [
                ["datetime": .string("2026-09-05T12:00:00Z"), "condition": .string("sunny"), "temperature": .number(70), "templow": .number(55)],
            ])
        }
        h.store.activate(caller: h.caller, revision: "a")
        await h.store.settle()
        h.store.updateBriefing(context)
        let briefing = h.store.briefing
        #expect(briefing?.dateKey == "2026-09-05")
        #expect(briefing?.version == WeatherDayBriefingGenerator.version)

        // Frozen for the rest of the day, even if the forecast changes.
        h.caller.respond = { _ in WeatherFixtures.response(entries: [["datetime": .string("2026-09-05T12:00:00Z"), "condition": .string("rainy")]]) }
        h.store.update(revision: "b")
        await h.store.settle()
        h.store.updateBriefing(context)
        #expect(h.store.briefing == briefing)

        let reopened = makeHarness(server: .example, cache: cache)
        #expect(reopened.store.briefing == briefing)
        cache.clear()
    }

    @Test func keepBriefingCurrentAsksForContextEachCheckUntilCancelled() async {
        let h = makeHarness(server: .example, cache: WeatherFixtures.temporaryCache())
        var asked = 0
        let task = Task { @MainActor in
            await h.store.keepBriefingCurrent(every: .milliseconds(5)) {
                asked += 1
                return WeatherBriefingContext(temperatureUnit: "°F", windSpeedUnit: "mph")
            }
        }
        // Wait for the second check (bounded), not a fixed sleep: a loaded runner can starve the loop past any wall-clock guess.
        let deadline = ContinuousClock.now + .seconds(30)
        while asked < 2, ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(5)) }
        task.cancel()
        await task.value
        let final = asked
        #expect(final >= 2)
        try? await Task.sleep(for: .milliseconds(30))
        #expect(asked == final, "cancelling stops the polling")
    }

    @Test func discardsAStoredBriefingFromAnOlderVersion() throws {
        let cache = WeatherFixtures.temporaryCache()
        var briefing = WeatherDayBriefingGenerator.generate(WeatherDayBriefingInput(
            daily: [WeatherForecast(datetime: "2026-09-05T00:00:00Z", condition: "sunny", temperature: 70)],
            generatedAt: Date(), timeZone: TimeZone(identifier: "UTC")!
        ))
        briefing.version = 1
        try cache.save(.init(
            version: WeatherForecastDiskCache.currentVersion, server: HassServer.example.baseURL, savedAt: Date(),
            daily: [], dailyUpdatedAt: nil, hourly: [], hourlyUpdatedAt: nil, briefing: briefing
        ))
        #expect(makeHarness(server: .example, cache: cache).store.briefing == nil)
        cache.clear()
    }
}
