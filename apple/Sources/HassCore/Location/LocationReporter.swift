import Foundation
import Observation
#if os(iOS)
import UIKit
#endif

/// Reports this phone's location to Home Assistant through `mobile_app` (`.agents/platforms/apple/location.md`).
///
/// - Permission: While Using the App first, then the upgrade to Always, with Precise Location.
/// - With Always and Precise: watches the nearest zones (``ZonePlanner``) and significant changes, and sends the
///   zone result with each crossing (``ZoneEventResolver``). With While Using only: a fix on each app open.
/// - Every fix passes ``LocationFixFilter`` first.
/// - Every iOS device reports to its own `device_tracker`. Only a phone is also linked to the signed-in person
///   (``linksPresence``): an iPad left at home and tied to a person would mark them home while they are away, so for
///   now an iPad reports but never follows anyone. The reporter itself does not link; the app's `LocationCoordinator`
///   reads ``linksPresence`` and decides.
///
/// The app's `LocationCoordinator` starts it once the shared `mobile_app` registration exists.
@MainActor
@Observable
public final class LocationReporter {
    /// The current permission, kept in step with the platform.
    public private(set) var permission: LocationPermission
    /// Whether reporting is on.
    public private(set) var isRunning = false
    /// The regions being watched.
    public private(set) var monitoredRegions: [PlannedRegion] = []
    /// Why the last update was sent (the Last Update Trigger sensor's state).
    public private(set) var lastTrigger: LocationTrigger?
    /// When the last update was accepted by Home Assistant.
    public private(set) var lastReportDate: Date?
    /// The last webhook failure; cleared by the next success.
    public private(set) var lastError: MobileAppWebhookError?
    /// Whether this device's tracker is put on the signed-in person (phones yes, iPads no). Reporting does not depend on it.
    public let linksPresence: Bool
    /// Called after each permission change, running or not, so the owner can start reporting once allowed.
    @ObservationIgnored public var onPermissionChange: (@MainActor (LocationPermission) -> Void)?

    @ObservationIgnored private let platform: any LocationPlatform
    @ObservationIgnored private let client: MobileAppWebhookClient
    @ObservationIgnored private let batteryLevel: @MainActor () -> Int?
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private let zoneStore: any ZoneStore
    @ObservationIgnored private let backgroundTime: any BackgroundTime
    @ObservationIgnored private var filter = LocationFixFilter()
    @ObservationIgnored private var zones: [HAZone] = []
    @ObservationIgnored private var lastFix: LocationFix?
    @ObservationIgnored private let deviceInfo: @MainActor () -> [String: String]
    /// Registers and updates the phone's sensors with every update; nil sends none (``init(platform:client:linksPresence:batteryLevel:now:zoneStore:backgroundTime:deviceInfo:sensors:)``).
    @ObservationIgnored private let sensors: SensorReporter?
    /// Whether `start` left the zone refresh for the update that follows (see ``start(reportLaunch:deferZoneRefresh:)``).
    @ObservationIgnored private var zoneRefreshPending = false
    /// Sensor updates started beside location sends and not finished. A send never waits for them; the end of each
    /// background-time hold does (``awaitSensors()``).
    @ObservationIgnored private var sensorTasks: [UUID: Task<Void, Never>] = [:]
    /// The last zone event's handling; the next waits for it (see ``serializedZoneWork(_:)``).
    @ObservationIgnored private var zoneTail: Task<Void, Never>?
    /// Platform events being handled, so tests can wait for them (``awaitZoneWork()``).
    @ObservationIgnored private var eventTasks: [UUID: Task<Void, Never>] = [:]
    /// When an exit of one of a small zone's circles was last reported with the phone outside the zone, by zone.
    @ObservationIgnored private var reportedSubRegionExits: [String: Date] = [:]
    /// A second exit of a different circle of the same zone within this long (seconds) is the same departure.
    static let subRegionExitWindow: TimeInterval = 5 * 60
    /// When the last exit was answered with the zone's center for lack of a fresh reading. Until a reading taken
    /// after that moment has been sent, no other report may use an older one: a cached reading from before the
    /// crossing is still inside the zone and would put the person back home.
    @ObservationIgnored private var exitFallbackAt: Date?

    /// Creates a reporter.
    /// - Parameters:
    ///   - platform: Core Location, or a fake in tests.
    ///   - client: Sends the webhook commands.
    ///   - linksPresence: Whether this device's tracker follows the signed-in person; defaults to false on iPad.
    ///   - batteryLevel: The battery percentage sent with each update.
    ///   - now: The clock, for ``lastReportDate`` and the filter's age checks.
    ///   - zoneStore: Remembers the last `get_zones` result for offline relaunches.
    ///   - backgroundTime: Keeps the app awake while an event is reported.
    ///   - deviceInfo: The `sourceDevice…` fields sent with the zone events fired to Home Assistant.
    ///   - sensors: Sends the phone's sensors with each location update, and alone (``updateSensorsOnly(_:)``).
    public init(platform: any LocationPlatform, client: MobileAppWebhookClient,
                linksPresence: Bool = LocationReporter.deviceLinksPresence,
                batteryLevel: @escaping @MainActor () -> Int? = { nil }, now: @escaping @MainActor () -> Date = { .now },
                zoneStore: any ZoneStore = UserDefaultsZoneStore(),
                backgroundTime: any BackgroundTime = NoBackgroundTime(),
                deviceInfo: @escaping @MainActor () -> [String: String] = { [:] }, sensors: SensorReporter? = nil) {
        self.sensors = sensors
        self.deviceInfo = deviceInfo
        self.zoneStore = zoneStore
        self.backgroundTime = backgroundTime
        self.platform = platform
        self.client = client
        self.linksPresence = linksPresence
        self.batteryLevel = batteryLevel
        self.now = now
        permission = platform.permission
        platform.onEvent = { [weak self] event in
            guard let self else { return }
            let id = UUID()
            eventTasks[id] = Task { [weak self] in
                await self?.handle(event)
                self?.eventTasks[id] = nil
            }
        }
    }

    // MARK: - Presence linking

    /// Whether a device of this kind is linked to the signed-in person: phones are, iPads are not (interim rule,
    /// owner 2026-10-27; any-device-away presence is a future item in `.agents/platforms/apple/location.md`).
    public nonisolated static func linksPresence(isPad: Bool) -> Bool { !isPad }

    /// Whether this device is linked to the signed-in person.
    public static var deviceLinksPresence: Bool {
        #if os(iOS)
        linksPresence(isPad: UIDevice.current.userInterfaceIdiom == .pad)
        #else
        false
        #endif
    }

    // MARK: - Permission

    /// Asks for the next permission step: While Using the App, then Always. Other states need Settings.
    public func requestPermission() {
        switch permission.authorization {
        case .notDetermined: platform.requestWhenInUse()
        case .whenInUse: platform.requestAlways()
        case .always, .denied, .restricted: break
        }
    }

    // MARK: - Running

    /// Starts reporting: the zone monitor and significant changes first, with no network, so a background
    /// relaunch for a crossing receives it at once (the cached zones resolve it offline); then fresh zones and a
    /// fix for the app opening. Does nothing without permission or when already running.
    /// - Parameters:
    ///   - reportLaunch: Whether to send the app-open update (trigger Launch). The app's coordinator passes
    ///     false and sends it once per foreground session (`LocationCoordinator`); a background relaunch has none.
    ///   - deferZoneRefresh: Leave the `get_zones` call for the update that follows (``requestUpdate(_:inBackground:)``
    ///     runs it after the fix and send, inside its background time hold). A relaunch for a push must not wait on
    ///     the network before it takes background time and a fix.
    public func start(reportLaunch: Bool = true, deferZoneRefresh: Bool = false) async {
        guard permission.isAuthorized, !isRunning else { return }
        isRunning = true
        zones = zoneStore.load()
        if permission.allowsBackgroundReporting {
            platform.startSignificantChanges()
            await platform.openZoneMonitor()
            await replan()
        }
        if deferZoneRefresh { zoneRefreshPending = true } else { await refreshZones() }
        if reportLaunch { await report(.launch) }
    }

    /// Stops reporting and forgets the fix history (sign-out, permission withdrawn, registration gone).
    public func stop() async {
        guard isRunning else { return }
        isRunning = false
        platform.stopSignificantChanges()
        await platform.stopMonitoring()
        monitoredRegions = []
        filter.reset()
        lastFix = nil
        reportedSubRegionExits = [:]
        exitFallbackAt = nil
        zoneRefreshPending = false
        // Sensor work that is running or queued must not send after permission is withdrawn or the phone signs out.
        for task in sensorTasks.values { task.cancel() }
        sensorTasks = [:]
        await sensors?.cancelPending()
    }

    /// Reads the zones again and re-plans the watched regions. A failure keeps the cached zones.
    public func refreshZones() async {
        guard isRunning else { return }
        do {
            zones = try await client.zones()
            zoneStore.save(zones)
        } catch {
            await record(error)
            return
        }
        await replan()
    }

    /// Reads the zones again if ``start(reportLaunch:deferZoneRefresh:)`` left that for later.
    public func refreshPendingZones() async {
        guard zoneRefreshPending else { return }
        zoneRefreshPending = false
        await refreshZones()
    }

    /// Takes a fix and sends it.
    /// - Returns: Whether Home Assistant accepted an update.
    @discardableResult
    public func report(_ trigger: LocationTrigger) async -> Bool {
        let notBefore = exitFallbackAt
        guard isRunning, let fix = try? await platform.currentFix(timeout: timeout(for: trigger), notBefore: notBefore),
              fix.timestamp >= (notBefore ?? .distantPast) else { return false }
        return await send(fix, trigger: trigger, locationName: nil)
    }

    /// Whether location may be reported now: in the background only with Always and Precise Location (the app
    /// cannot take a fix there otherwise), in the foreground with any allowed permission.
    /// - Parameter inBackground: Whether the app is in the background.
    public func canReport(inBackground: Bool) -> Bool {
        isRunning && (inBackground ? permission.allowsBackgroundReporting : permission.isAuthorized)
    }

    /// Takes a fix and sends it for a trigger the system or Home Assistant started (a push request, a background
    /// refresh), holding background time from the start of the fix to the end of the send.
    /// - Parameters:
    ///   - trigger: Why the update is sent.
    ///   - inBackground: Whether the app is in the background (see ``canReport(inBackground:)``).
    ///   - prepare: Runs inside the hold, before the permission check: starting the reporter for a relaunch (without
    ///     the zone refresh, which follows the send inside the hold).
    /// - Returns: Whether Home Assistant accepted an update; false when location is not allowed here.
    @discardableResult
    public func requestUpdate(_ trigger: LocationTrigger, inBackground: Bool,
                              startingWith prepare: @MainActor () async -> Void = {}) async -> Bool {
        let release = backgroundTime.begin(trigger.rawValue)
        defer { release() }
        await prepare()
        guard canReport(inBackground: inBackground) else {
            await refreshPendingZones()
            return false
        }
        let sent = await report(trigger)
        await refreshPendingZones()
        await awaitSensors()
        return sent
    }

    /// Sends the sensors alone, for a trigger that cannot use location (a Background App Refresh without Always, as the
    /// official app does). Holds background time. Needs only a webhook, not location permission.
    /// - Returns: Whether the update reached Home Assistant (or had nothing new to send).
    @discardableResult
    public func updateSensorsOnly(_ trigger: LocationTrigger) async -> Bool {
        guard let sensors else { return false }
        let release = backgroundTime.begin("\(trigger.rawValue) sensors")
        defer { release() }
        var succeeded = true
        do {
            try await sensors.update(SensorContext(trigger: trigger, permission: permission, zones: zones))
        } catch {
            succeeded = false
            await sensorFailed(error)
        }
        await awaitSensors()
        await refreshPendingZones()
        return succeeded
    }

    // MARK: - Events

    /// Waits until every platform event received so far, and the zone work queued behind them, has finished.
    /// For tests: a fixed number of `Task.yield()` calls does not bound how long the queue takes under load.
    func awaitZoneWork() async {
        while let task = eventTasks.values.first { await task.value }
        await zoneTail?.value
    }

    func handle(_ event: LocationPlatformEvent) async {
        switch event {
        case .permissionChanged(let new):
            let old = permission
            permission = new
            onPermissionChange?(new)
            guard isRunning else { return }
            if !new.isAuthorized {
                await stop()
            } else if new.allowsBackgroundReporting != old.allowsBackgroundReporting {
                if new.allowsBackgroundReporting { platform.startSignificantChanges() } else { platform.stopSignificantChanges() }
                await replan()
            }
        case .significantChange(let fix):
            guard isRunning else { return }
            let release = backgroundTime.begin("significant change")
            defer { release() }
            await handleSignificantChange(fix)
            // The nearest zones change as the phone moves.
            await replan()
            await awaitSensors()
        case .zone(let zoneEvent):
            guard isRunning else { return }
            let release = backgroundTime.begin("zone event")
            defer { release() }
            let receivedAt = now()
            await serializedZoneWork { [self] in await handleZone(zoneEvent, receivedAt: receivedAt) }
            // Outside the queue: the next zone event never waits for this one's sensors.
            await awaitSensors()
        }
    }

    /// A significant change (about 500 m) is a prompt to look, not a position: iOS can deliver a cached reading.
    /// Ignored when an update succeeded under 30 s ago or the reading is over 180 s old (the official app's rules);
    /// otherwise a fresh one-shot fix is taken. If none arrives, the reading itself is sent unless it grades invalid.
    private func handleSignificantChange(_ fix: LocationFix) async {
        guard fix.isValid, now().timeIntervalSince(fix.timestamp) <= OneShotFix.significantChangeMaxAge else { return }
        if let last = lastReportDate, now().timeIntervalSince(last) < OneShotFix.significantChangeCooldown { return }
        let trigger = LocationTrigger.significantLocationChange
        let notBefore = exitFallbackAt
        if let own = try? await platform.currentFix(timeout: timeout(for: trigger), notBefore: notBefore),
           own.timestamp >= (notBefore ?? .distantPast) {
            await send(own, trigger: trigger, locationName: nil)
        } else if OneShotFix.grade(fix, now: now()) != .invalid, fix.timestamp >= (notBefore ?? .distantPast) {
            await send(fix, trigger: trigger, locationName: nil)
        }
    }

    private func timeout(for trigger: LocationTrigger) -> TimeInterval {
        OneShotFix.timeout(for: trigger, backgroundRemaining: backgroundTime.remaining)
    }

    /// A region crossing: reported with a fresh fix, then fired to Home Assistant as an event. A crossing of a
    /// region no zone owns (a zone since deleted) is ignored.
    private func handleZone(_ event: ZoneEvent, receivedAt: Date) async {
        guard let zone = zones.first(where: { $0.entityID == event.zoneID }) else { return }
        await reportZone(event, zone: zone, receivedAt: receivedAt)
        await fireEvent(for: event)
    }

    /// Runs zone-event work one event at a time, in arrival order. Leaving a small zone crosses two of its
    /// circles together; the second must see whether the first was already reported, which is only known after
    /// the first's fix and send.
    private func serializedZoneWork(_ work: @escaping @MainActor () async -> Void) async {
        let previous = zoneTail
        let task = Task { @MainActor [self] in
            await previous?.value
            // Stopped while queued: nothing more is reported.
            guard isRunning else { return }
            await work()
        }
        zoneTail = task
        await task.value
    }

    private func reportZone(_ event: ZoneEvent, zone: HAZone, receivedAt: Date) async {
        if case .entered = event {
            reportedSubRegionExits[zone.entityID] = nil
            exitFallbackAt = nil
        }
        if case .exited = event, event.isSubRegion, let reported = reportedSubRegionExits[zone.entityID],
           now().timeIntervalSince(reported) < Self.subRegionExitWindow {
            return
        }
        // An exit is answered only by a reading taken after the crossing: a cached one from before it is still
        // inside the zone and would keep the person home.
        let notBefore: Date? = if case .exited = event { receivedAt } else { nil }
        var fix = (try? await platform.currentFix(timeout: timeout(for: event.trigger), notBefore: notBefore))
            .flatMap { $0.isValid && ($0.timestamp >= (notBefore ?? .distantPast)) ? $0 : nil }
        var outcome = SendOutcome.rejected
        var outside = true
        if let reading = fix {
            var toSend = reading
            if case .entered = event {
                let regions = ZonePlanner().regions(for: zone)
                // A region persisted by an older version has no match: its padded circle stands in.
                let region = regions.first { $0.id == event.regionID } ?? PlannedRegion(
                    id: event.regionID, latitude: zone.latitude, longitude: zone.longitude,
                    radius: max(zone.radius, ZonePlanner.minimumRadius))
                toSend = ZoneEntryFuzzer.fuzz(reading, entering: region, of: zone, zoneRegions: regions)
            }
            let name = ZoneEventResolver(zones: zones).locationName(for: event, fix: reading)
            outcome = await attemptSend(toSend, trigger: event.trigger, locationName: name)
            outside = zone.distanceOutside(toSend) - toSend.horizontalAccuracy > 0
            // The filter refusing an exit's fix must not lose the departure iOS reported.
            if outcome == .rejected, case .exited = event { fix = nil }
        }
        if fix == nil, outcome != .failed {
            guard let center = await fallbackFix(for: event, zone: zone) else { return }
            outcome = await attemptSend(center.fix, trigger: event.trigger, locationName: center.name, synthetic: true)
            outside = true
            if outcome == .sent, case .exited = event { exitFallbackAt = receivedAt }
        }
        if outcome == .sent, case .exited = event, event.isSubRegion, outside {
            reportedSubRegionExits[zone.entityID] = now()
        }
    }

    /// With no fresh fix the crossing iOS reported is still the news (a departure from the official app, which
    /// sends nothing when the fix fails).
    /// - Enter: the zone's center at its radius' accuracy, named.
    /// - Exit: the exited zone's center with the monitored region's radius as accuracy and `not_home`.
    ///   Home Assistant sets a tracker's state from its coordinates, and a circle that covers the region's edge
    ///   but not the real zone is the closest honest statement of "just left". Skipped when another monitored
    ///   non-passive zone is satisfied: then the phone is still somewhere known and the next fix says where.
    private func fallbackFix(for event: ZoneEvent, zone: HAZone) async -> (fix: LocationFix, name: String?)? {
        switch event {
        case .entered:
            let name = ZoneEventResolver(zones: zones).locationName(for: event, fix: nil)
            return (LocationFix(latitude: zone.latitude, longitude: zone.longitude, horizontalAccuracy: zone.radius,
                                timestamp: now()), name)
        case .exited:
            let satisfied = Set(await platform.satisfiedRegions().map(PlannedRegion.zoneID(of:))).subtracting([zone.entityID])
            guard satisfied.isDisjoint(with: zones.filter { !$0.isPassive }.map(\.entityID)) else { return nil }
            let radius = monitoredRegions.first { $0.id == event.regionID }?.radius ?? max(zone.radius, ZonePlanner.minimumRadius)
            return (LocationFix(latitude: zone.latitude, longitude: zone.longitude, horizontalAccuracy: radius,
                                timestamp: now()), "not_home")
        }
    }

    /// Fires `ios.zone_entered` / `ios.zone_exited` as the official app does, so automations that trigger on them
    /// port unchanged. Best effort: a failure other than a gone registration is not worth an error.
    private func fireEvent(for event: ZoneEvent) async {
        guard isRunning else { return }
        var data = deviceInfo()
        data["zone"] = event.zoneID
        if let sub = PlannedRegion.subRegionID(of: event.regionID) { data["multi_region_zone_id"] = sub }
        do {
            try await client.send(command: "fire_event", data: ["event_type": event.eventType, "event_data": data])
        } catch {
            if let failure = error as? MobileAppWebhookError, failure == .registrationGone || failure == .notRegistered {
                await record(failure)
            }
        }
    }

    // MARK: - Sending

    private func replan() async {
        guard permission.allowsBackgroundReporting else { return await applyPlan([]) }
        // After a background relaunch nothing has been sent yet: Core Location's cached position stands in.
        let reference = lastFix == nil ? await platform.lastKnownFix() : lastFix
        await applyPlan(ZonePlanner().plan(zones, near: reference))
    }

    private func applyPlan(_ plan: [PlannedRegion]) async {
        guard isRunning, plan != monitoredRegions else { return }
        monitoredRegions = plan
        if plan.isEmpty {
            await platform.stopMonitoring()
        } else {
            await platform.monitor(plan)
        }
    }

    /// Sends one update.
    /// - Parameter synthetic: The fix is made up from a zone's center (no reading could be taken), so it stays out
    ///   of the filter's history and the zone reference: its timestamp is the clock's, and a real reading taken
    ///   just before it would otherwise look out of order.
    @discardableResult
    private func send(_ fix: LocationFix, trigger: LocationTrigger, locationName: String?, synthetic: Bool = false) async -> Bool {
        await attemptSend(fix, trigger: trigger, locationName: locationName, synthetic: synthetic) == .sent
    }

    /// How an attempt to send an update ended.
    private enum SendOutcome {
        /// Home Assistant accepted it.
        case sent
        /// The filter (or the report's own validation) refused the fix; nothing was sent.
        case rejected
        /// The request failed.
        case failed
    }

    private func attemptSend(_ fix: LocationFix, trigger: LocationTrigger, locationName: String?,
                             synthetic: Bool = false) async -> SendOutcome {
        // Admit on a copy: a fix that fails to send must not count as the last one sent.
        var candidate = filter
        guard isRunning else { return .rejected }
        guard synthetic || candidate.admit(fix, trigger: trigger, now: now()),
              let report = LocationReport(fix: fix, batteryLevel: batteryLevel(), locationName: locationName)
        else { return .rejected }
        // A reading older than the exit that fell back to the zone's center is still inside the zone: a request that
        // was waiting for its fix when the exit happened must not put the person back home.
        if !synthetic, let since = exitFallbackAt, fix.timestamp < since { return .rejected }
        if !synthetic { lastFix = fix }
        // The sensors go in parallel with the location, with the same trigger and the same fix.
        if let sensors { startSensors(sensors, trigger: trigger, fix: synthetic ? nil : fix) }
        do {
            try await client.updateLocation(report)
        } catch {
            await record(error)
            return .failed
        }
        if !synthetic {
            filter = candidate
            // A reading taken after the exit that fell back to the zone's center has now been sent.
            if let since = exitFallbackAt, fix.timestamp >= since { exitFallbackAt = nil }
        }
        lastTrigger = trigger
        lastReportDate = now()
        lastError = nil
        return .sent
    }

    // MARK: - Sensors

    /// Starts a sensor update that runs beside the location send and returns at once: the device is read and the
    /// commands sent on the ``SensorReporter`` actor, never on the main thread, and nothing here waits for them (the
    /// zone event, the next queued event and the caller go on). The geocode is of `fix`; a made-up fix is not geocoded.
    private func startSensors(_ sensors: SensorReporter, trigger: LocationTrigger, fix: LocationFix?) {
        let context = SensorContext(trigger: trigger, fix: fix, permission: permission, zones: zones)
        let id = UUID()
        sensorTasks[id] = Task { [weak self] in
            do { try await sensors.update(context) } catch { await self?.sensorFailed(error) }
            self?.sensorTasks[id] = nil
        }
    }

    /// Only a gone registration is an error worth recording: a failed sensor update leaves the sensors unsent and the
    /// next update carries them.
    private func sensorFailed(_ error: any Error) async {
        if let failure = error as? MobileAppWebhookError, failure == .registrationGone || failure == .notRegistered {
            await record(failure)
        }
    }

    /// Waits for the sensor updates still running, at the end of a background-time hold, so iOS does not suspend the
    /// app mid-request. Gives up after the background time left minus 5 s (at least 1 s, at most
    /// ``OneShotFix/longestWait``). The updates carry on if they are not done.
    func awaitSensors() async {
        let pending = Array(sensorTasks.values)
        guard !pending.isEmpty else { return }
        // Clamped: iOS reports `DBL_MAX` with no limit, which `Duration` cannot hold.
        let limit = OneShotFix.waitLimit(backgroundRemaining: backgroundTime.remaining)
        // A race of two unstructured tasks: a task group would wait for the loser, and the sensors are not cancellable.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var resumed = false
            let finish: @MainActor () -> Void = {
                guard !resumed else { return }
                resumed = true
                continuation.resume()
            }
            Task { @MainActor in
                for task in pending { await task.value }
                finish()
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(limit))
                finish()
            }
        }
    }

    private func record(_ error: any Error) async {
        guard !(error is CancellationError) else { return }
        let failure = error as? MobileAppWebhookError ?? .network
        lastError = failure
        // Nothing to send to until the phone registers again.
        if failure == .registrationGone || failure == .notRegistered { await stop() }
    }
}
