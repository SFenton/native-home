import Foundation
import HassTelemetry
import Observation

/// The app's one source of weather forecasts, shared by the Home card and the Weather sheet.
///
/// Port of the web `WeatherForecastCache`: daily and hourly forecasts are fetched through `weather.get_forecasts`,
/// reused for five minutes, refetched at once when the weather entity changes, retried quietly after a dropped
/// connection (5 s, doubling up to the TTL) and never cleared while a refresh runs. Hourly entries whose hour has
/// passed are dropped on schedule. The last good data is written to disk and restored on launch, so reopening the
/// app never shows an empty carousel (`.agents/platforms/apple/connection-lifecycle.md`).
/// Source: `ha-sfenton-react-dash@f5a7bf9:src/components/hass/useWeatherForecasts.ts:121`.
@MainActor
@Observable
public final class WeatherForecastStore {
    // MARK: - Constants

    /// How long a response is reused (`WEATHER_FORECAST_TTL_MS`).
    public static let timeToLive: TimeInterval = 5 * 60
    /// The first retry delay after a dropped connection (`WEATHER_FORECAST_RETRY_MS`).
    public static let retryInterval: TimeInterval = 5
    private static let hour: TimeInterval = 3600

    // MARK: - State

    /// Seven daily forecasts.
    public private(set) var daily = WeatherForecastFeed()
    /// Up to 24 hourly forecasts, starting with the current hour.
    public private(set) var hourly = WeatherForecastFeed()
    /// Today's frozen briefing.
    public private(set) var briefing: WeatherDayBriefing?

    // MARK: - Private

    private struct Request {
        var completedRevision = -1
        var failures = 0
        var inFlight = false
        var nextRefresh: Date = .distantPast
        var retryAt: Date = .distantPast
    }

    @ObservationIgnored private let entityId: String
    @ObservationIgnored private let server: HassServer?
    @ObservationIgnored private let cache: WeatherForecastDiskCache?
    @ObservationIgnored private let timeZone: TimeZone
    @ObservationIgnored private let requestTimeout: TimeInterval
    @ObservationIgnored private let scheduler: any WeatherRefreshScheduling
    @ObservationIgnored private let clock: @MainActor () -> Date
    @ObservationIgnored private var requests: [WeatherForecastKind: Request] = [.daily: Request(), .hourly: Request()]
    @ObservationIgnored private var fetchTasks: [WeatherForecastKind: Task<Void, Never>] = [:]
    @ObservationIgnored private var cancelTimer: (@MainActor () -> Void)?
    @ObservationIgnored private var caller: (any WeatherForecastCalling)?
    @ObservationIgnored private var consumers = 0
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var sourceRevision: String?
    @ObservationIgnored private var connected = true
    /// When each hourly entry ends, by its ``WeatherForecast/datetime``: parsing the ISO 8601 text on every ``refresh()`` cost
    /// about 7 ms of main thread per connection status change (`.agents/testing/apple/performance.md`, Round 5).
    @ObservationIgnored private var expiries: [String: Date] = [:]
    @ObservationIgnored private var foreground = true
    @ObservationIgnored private var census: ResourceCensus.Registration?

    // MARK: - Init

    /// Creates a store and restores the disk snapshot, if any, before any network work.
    /// - Parameters:
    ///   - entityId: The weather entity to ask about.
    ///   - server: The signed-in server; with `cache`, keys the disk snapshot.
    ///   - cache: Disk snapshot of the last good forecasts.
    ///   - timeZone: Where "today" is for the briefing.
    ///   - requestTimeout: A request that never answers (HAKit drops unanswered requests across a reconnect) is
    ///     treated as a dropped connection after this long.
    ///   - scheduler: Starts the refresh timer.
    ///   - clock: The current time.
    public init(
        entityId: String = HomeConfig.weatherEntityId, server: HassServer? = nil, cache: WeatherForecastDiskCache? = nil,
        timeZone: TimeZone = .current, requestTimeout: TimeInterval = 20,
        scheduler: any WeatherRefreshScheduling = WeatherTaskScheduler(), clock: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.entityId = entityId
        self.server = server
        self.cache = cache
        self.timeZone = timeZone
        self.requestTimeout = requestTimeout
        self.scheduler = scheduler
        self.clock = clock
        restore()
        census = ResourceCensus.shared.register { [weak self] in self?.liveResources ?? [:] }
    }

    /// What the store holds right now (`ResourceCensus`): consumers, the refresh timer and fetches in flight.
    var liveResources: [String: Int] {
        ["Weather.consumers": consumers, "Weather.timer": cancelTimer == nil ? 0 : 1, "Weather.fetches": fetchTasks.count]
    }

    // MARK: - Lifecycle

    /// A view that shows weather appeared. Starts fetching (the first consumer) and refetches if stale.
    /// - Parameters:
    ///   - caller: The connection to ask.
    ///   - revision: A value that changes when the weather entity updates (web `last_updated`).
    ///   - connected: Whether the websocket is ready.
    public func activate(caller: any WeatherForecastCalling, revision: String?, connected: Bool = true) {
        consumers += 1
        self.caller = caller
        self.connected = connected
        updateRevision(revision)
        refresh()
    }

    /// A view that shows weather went away. The last consumer stops the timer; fetches in flight still finish.
    public func deactivate() {
        consumers = max(0, consumers - 1)
        guard consumers == 0 else { return }
        clearTimer()
    }

    /// The weather entity changed: refetch both kinds now.
    public func update(revision: String?) {
        updateRevision(revision)
        refresh()
    }

    /// The websocket became ready or dropped. Becoming ready clears retry backoff and fetches at once.
    public func setConnected(_ isConnected: Bool) {
        guard connected != isConnected else { return }
        connected = isConnected
        if isConnected {
            for kind in WeatherForecastKind.allCases {
                requests[kind]?.failures = 0
                requests[kind]?.retryAt = .distantPast
            }
        }
        refresh()
    }

    /// The app moved to or from the foreground (web `visibilitychange`). Nothing is fetched while hidden.
    public func setForeground(_ isForeground: Bool) {
        foreground = isForeground
        refresh()
    }

    /// Fetches anything due, drops hourly entries whose hour passed and re-arms the timer.
    public func refresh() {
        clearTimer()
        guard isActive else { return }
        let now = clock()
        pruneHourly(now)
        for kind in WeatherForecastKind.allCases {
            let request = requests[kind] ?? Request()
            if connected, !request.inFlight, now >= dueAt(request) { fetch(kind) }
        }
        // While disconnected, the connection's ready event resumes fetching.
        var deadlines: [Date] = connected
            ? WeatherForecastKind.allCases.compactMap { kind in
                let request = requests[kind] ?? Request()
                return request.inFlight ? nil : dueAt(request)
            }
            : []
        deadlines += hourly.forecasts.map(cachedExpiry)
        if let next = deadlines.min(), next < .distantFuture {
            cancelTimer = scheduler.schedule(after: max(0.001, next.timeIntervalSince(now))) { [weak self] in self?.refresh() }
        }
    }

    /// Writes today's briefing when it is due (once per local day, at or after 00:01).
    public func updateBriefing(_ context: WeatherBriefingContext) {
        let now = clock()
        guard WeatherBriefingPlanner.shouldGenerate(
            current: briefing, now: now, timeZone: timeZone, hourly: hourly.forecasts, daily: daily.forecasts
        ) else { return }
        briefing = WeatherDayBriefingGenerator.generate(WeatherDayBriefingInput(
            aqi: context.aqi, daily: daily.forecasts, generatedAt: now, hourly: hourly.forecasts,
            precipitationUnit: context.precipitationUnit, sunrise: context.sunrise, sunset: context.sunset,
            temperatureUnit: context.temperatureUnit, timeZone: timeZone, windSpeedUnit: context.windSpeedUnit
        ))
        persist()
    }

    /// Writes the briefing when it is due and checks again every `interval` until cancelled (web `useWeatherDayBriefing`).
    /// - Parameter context: Builds the entity-derived context on each check, so the card holds no polling loop.
    public func keepBriefingCurrent(every interval: Duration = .seconds(30), context: @MainActor () -> WeatherBriefingContext) async {
        while !Task.isCancelled {
            updateBriefing(context())
            try? await Task.sleep(for: interval)
        }
    }

    /// Waits for fetches in flight (tests and previews).
    public func settle() async {
        while true {
            let tasks = Array(fetchTasks.values)
            if tasks.isEmpty { return }
            for task in tasks { await task.value }
            fetchTasks = fetchTasks.filter { !$0.value.isCancelled && requests[$0.key]?.inFlight == true }
        }
    }

    /// Forgets everything, including the disk copy (sign out).
    public func reset() {
        clearTimer()
        fetchTasks.values.forEach { $0.cancel() }
        fetchTasks = [:]
        daily = WeatherForecastFeed()
        hourly = WeatherForecastFeed()
        briefing = nil
        requests = [.daily: Request(), .hourly: Request()]
        cache?.clear()
    }

    // MARK: - Scheduling

    private var isActive: Bool { consumers > 0 && foreground }

    private func updateRevision(_ new: String?) {
        guard new != sourceRevision else { return }
        sourceRevision = new
        revision += 1
    }

    private func dueAt(_ request: Request) -> Date {
        max(request.retryAt, request.completedRevision != revision ? .distantPast : request.nextRefresh)
    }

    private func clearTimer() {
        cancelTimer?()
        cancelTimer = nil
    }

    private func cachedExpiry(_ forecast: WeatherForecast) -> Date {
        guard let key = forecast.datetime else { return Self.expiry(forecast) }
        if let known = expiries[key] { return known }
        if expiries.count > 200 { expiries.removeAll() }
        let date = Self.expiry(forecast)
        expiries[key] = date
        return date
    }

    private static func expiry(_ forecast: WeatherForecast) -> Date {
        forecast.start.map { $0.addingTimeInterval(hour) } ?? .distantFuture
    }

    private static func current(_ forecasts: [WeatherForecast], now: Date) -> [WeatherForecast] {
        forecasts.filter { expiry($0) > now }
    }

    private func pruneHourly(_ now: Date) {
        let remaining = hourly.forecasts.filter { cachedExpiry($0) > now }
        guard remaining.count != hourly.forecasts.count else { return }
        hourly.forecasts = remaining
        if hourly.phase == .ready, remaining.isEmpty { hourly.phase = .empty }
    }

    // MARK: - Fetching

    private func feed(_ kind: WeatherForecastKind) -> WeatherForecastFeed { kind == .daily ? daily : hourly }

    private func patch(_ kind: WeatherForecastKind, _ change: (inout WeatherForecastFeed) -> Void) {
        var feed = feed(kind)
        change(&feed)
        if kind == .daily { daily = feed } else { hourly = feed }
    }

    private func fetch(_ kind: WeatherForecastKind) {
        let revision = revision
        let previousPhase = feed(kind).phase
        requests[kind]?.inFlight = true
        patch(kind) { feed in
            feed.refreshing = true
            if feed.forecasts.isEmpty { feed.phase = .loading }
        }
        fetchTasks[kind] = Task { @MainActor [weak self] in
            guard let self else { return }
            var started = false
            var interrupted = false
            do {
                // Re-checked after the hop so a request queued just before backgrounding never starts.
                if let caller, isActive, connected {
                    started = true
                    let entityId = entityId
                    let response = try await Self.withTimeout(requestTimeout) {
                        try await caller.callServiceForResponse("weather", "get_forecasts", data: ["entity_id": entityId, "type": kind.rawValue])
                    }
                    let received = try WeatherForecast.extract(from: response, entityId: entityId, kind: kind)
                    let now = clock()
                    let forecasts = kind == .hourly ? Self.current(received, now: now) : received
                    requests[kind]?.failures = 0
                    requests[kind]?.retryAt = .distantPast
                    patch(kind) { feed in
                        feed.error = nil
                        feed.forecasts = forecasts
                        feed.phase = forecasts.isEmpty ? .empty : .ready
                        feed.updatedAt = now
                    }
                    persist()
                }
            } catch {
                if Self.isConnectionInterruption(error) {
                    interrupted = true
                } else {
                    let message = ServiceErrorText.message(for: error, fallback: WeatherCopy.forecastFailure(kind))
                    patch(kind) { feed in
                        feed.error = message
                        feed.phase = .error
                    }
                }
            }
            let now = clock()
            if interrupted {
                let delay = min(Self.timeToLive, Self.retryInterval * pow(2, Double(requests[kind]?.failures ?? 0)))
                requests[kind]?.retryAt = now.addingTimeInterval(delay)
                requests[kind]?.failures += 1
            } else if started {
                requests[kind]?.completedRevision = revision
                requests[kind]?.nextRefresh = now.addingTimeInterval(Self.timeToLive)
            }
            requests[kind]?.inFlight = false
            fetchTasks[kind] = nil
            // An interrupted request stays loading (or keeps cached data) until the reconnect retry lands.
            patch(kind) { feed in
                feed.refreshing = false
                if !started { feed.phase = previousPhase }
            }
            refresh()
        }
    }

    /// A dropped or unanswered connection, as opposed to Home Assistant refusing the call.
    static func isConnectionInterruption(_ error: Error) -> Bool {
        if let error = error as? WeatherForecastError, error == .connectionLost { return true }
        if error is CancellationError { return true }
        if let error = error as? URLError {
            let codes: Set<URLError.Code> = [.networkConnectionLost, .notConnectedToInternet, .cannotConnectToHost, .timedOut, .cannotFindHost, .dnsLookupFailed]
            return codes.contains(error.code)
        }
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        return message.range(of: "connection not established or not ready", options: .caseInsensitive) != nil
    }

    // MARK: - Timeout

    @MainActor
    private final class Gate {
        var continuation: CheckedContinuation<JSONValue, Error>?
        var timer: Task<Void, Never>?
        var work: Task<Void, Never>?

        func finish(_ result: Result<JSONValue, Error>) {
            guard let continuation else { return }
            self.continuation = nil
            timer?.cancel()
            work?.cancel()
            continuation.resume(with: result)
        }
    }

    private static func withTimeout(_ seconds: TimeInterval, _ operation: @escaping @MainActor () async throws -> JSONValue) async throws -> JSONValue {
        let gate = Gate()
        return try await withCheckedThrowingContinuation { continuation in
            gate.continuation = continuation
            gate.work = Task { @MainActor in
                do { gate.finish(.success(try await operation())) } catch { gate.finish(.failure(error)) }
            }
            gate.timer = Task { @MainActor in
                try? await Task.sleep(for: .seconds(seconds))
                gate.finish(.failure(WeatherForecastError.connectionLost))
            }
        }
    }

    // MARK: - Persistence

    private func restore() {
        guard let server, let cache, let snapshot = cache.load(for: server) else { return }
        let now = clock()
        let restoredDaily = snapshot.daily
        let restoredHourly = Self.current(snapshot.hourly, now: now)
        if !restoredDaily.isEmpty {
            daily = WeatherForecastFeed(forecasts: restoredDaily, phase: .ready, updatedAt: snapshot.dailyUpdatedAt)
        }
        if !restoredHourly.isEmpty {
            hourly = WeatherForecastFeed(forecasts: restoredHourly, phase: .ready, updatedAt: snapshot.hourlyUpdatedAt)
        }
        if let stored = snapshot.briefing, stored.version == WeatherDayBriefingGenerator.version { briefing = stored }
    }

    private func persist() {
        guard let server, let cache else { return }
        let snapshot = WeatherForecastDiskCache.snapshot(server: server, savedAt: clock(), daily: daily, hourly: hourly, briefing: briefing)
        try? cache.save(snapshot)
    }
}

public extension WeatherForecastStore {
    /// A value that changes when the weather entity updates, standing in for the web's `last_updated`:
    /// the entity's state and attributes change whenever the provider publishes new data.
    nonisolated static func revision(of entity: EntityState?) -> String? {
        entity.map { String($0.hashValue) }
    }
}
