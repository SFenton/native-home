#if os(iOS)
import CoreLocation
import Foundation

/// ``LocationPlatform`` on Core Location: `CLLocationManager` for permission and significant changes, one
/// ``OneShotLocation`` request (its own manager, like the official app's) for each fix, and iOS 17's `CLMonitor`
/// circular conditions for zones.
///
/// The `CLMonitor` is kept, where the official app uses legacy `CLCircularRegion`s: it is the system API from iOS 17
/// and reports the same crossings; the official app's small-zone circles (``ZonePlanner``) are used on it.
///
/// Zones are added assuming the phone is outside them, so the first evaluation reports an entry only for the zone
/// the phone is in and never a burst of exits. `CLMonitor` keeps its conditions across launches under one name, and
/// a relaunch for a zone event delivers that event once the monitor is opened again.
@MainActor
public final class CoreLocationPlatform: NSObject, LocationPlatform {
    public var onEvent: (@MainActor (LocationPlatformEvent) -> Void)?

    /// Read off the main thread only for `location` and `accuracyAuthorization`, which ask the location daemon
    /// synchronously and have hung the main thread when it was slow.
    private nonisolated(unsafe) let manager = CLLocationManager()
    private var zoneEvents: Task<Void, Never>?
    /// Opens the one `CLMonitor` for ``monitorName`` and starts its event subscription, both exactly once. Core
    /// Location aborts on a second monitor with the same name, so concurrent callers must share the first open
    /// (see ``OpenOnce``).
    private lazy var zoneMonitor = OpenOnce<CLMonitor> { [weak self] in
        let monitor = await CLMonitor(Self.monitorName)
        self?.startZoneEvents(monitor)
        return monitor
    }
    private var newRegions = NewRegionGuard()

    /// The `CLMonitor` name; conditions persist under it.
    static let monitorName = "FentonHomeZones"

    /// Creates the platform; create it on the main thread, as `CLLocationManager` needs a run loop.
    public override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        // Significant changes and zone crossings wake the app; it must be allowed to take a fix then.
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
    }

    public var permission: LocationPermission {
        Self.permission(manager.authorizationStatus, accuracy: manager.accuracyAuthorization)
    }

    public func requestWhenInUse() { manager.requestWhenInUseAuthorization() }

    public func requestAlways() { manager.requestAlwaysAuthorization() }

    public func currentFix(timeout: TimeInterval, notBefore: Date?) async throws -> LocationFix {
        try await OneShotLocation(timeout: timeout, notBefore: notBefore).run()
    }

    public func lastKnownFix() async -> LocationFix? {
        await OneShotLocation.cachedReading(of: .init(manager))?.fix
    }

    public func startSignificantChanges() {
        guard CLLocationManager.significantLocationChangeMonitoringAvailable() else { return }
        manager.startMonitoringSignificantLocationChanges()
    }

    public func stopSignificantChanges() { manager.stopMonitoringSignificantLocationChanges() }

    public func openZoneMonitor() async { _ = await openMonitor() }

    public func satisfiedRegions() async -> Set<String> {
        let monitor = await openMonitor()
        var ids = Set<String>()
        for id in await monitor.identifiers {
            if await monitor.record(for: id)?.lastEvent.state == .satisfied { ids.insert(id) }
        }
        return ids
    }

    public func monitor(_ regions: [PlannedRegion]) async {
        let monitor = await openMonitor()
        let wanted = Dictionary(uniqueKeysWithValues: regions.map { ($0.id, $0) })
        for id in await monitor.identifiers where wanted[id] == nil {
            await monitor.remove(id)
        }
        for region in regions {
            let condition = CLMonitor.CircularGeographicCondition(
                center: CLLocationCoordinate2D(latitude: region.latitude, longitude: region.longitude), radius: region.radius
            )
            // Re-adding an unchanged condition would reset its state; leave it alone.
            if let existing = await monitor.record(for: region.id)?.condition as? CLMonitor.CircularGeographicCondition,
               existing.center.latitude == region.latitude, existing.center.longitude == region.longitude,
               existing.radius == region.radius {
                continue
            }
            newRegions.added(region.id, at: .now)
            await monitor.add(condition, identifier: region.id, assuming: .unsatisfied)
        }
    }

    public func stopMonitoring() async {
        guard let monitor = zoneMonitor.value else { return }
        for id in await monitor.identifiers { await monitor.remove(id) }
    }

    // MARK: - Monitor

    private func openMonitor() async -> CLMonitor { await zoneMonitor.get() }

    private func startZoneEvents(_ monitor: CLMonitor) {
        zoneEvents = Task { [weak self] in
            do {
                for try await event in await monitor.events {
                    switch event.state {
                    case .satisfied, .unsatisfied:
                        guard let self, !self.newRegions.isInitialState(event.identifier, at: .now) else { continue }
                        self.onEvent?(.zone(event.state == .satisfied ? .entered(event.identifier) : .exited(event.identifier)))
                    default: break
                    }
                }
            } catch {
                // The sequence ends only when the monitor is torn down.
            }
        }
    }

    /// Maps Core Location's permission onto ``LocationPermission``.
    nonisolated static func permission(_ status: CLAuthorizationStatus, accuracy: CLAccuracyAuthorization) -> LocationPermission {
        let authorization: LocationPermission.Authorization = switch status {
        case .authorizedAlways: .always
        case .authorizedWhenInUse: .whenInUse
        case .denied: .denied
        case .restricted: .restricted
        default: .notDetermined
        }
        return LocationPermission(authorization: authorization, isPrecise: accuracy == .fullAccuracy)
    }
}

extension CoreLocationPlatform: CLLocationManagerDelegate {
    public nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let permission = Self.permission(manager.authorizationStatus, accuracy: manager.accuracyAuthorization)
        Task { @MainActor in self.onEvent?(.permissionChanged(permission)) }
    }

    public nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let fix = LocationFix(location)
        Task { @MainActor in self.onEvent?(.significantChange(fix)) }
    }

    public nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        // Only significant changes run on this manager; a failed one has nothing to report.
    }
}

public extension LocationFix {
    /// A fix from a Core Location reading.
    init(_ location: CLLocation) {
        self.init(
            latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
            horizontalAccuracy: location.horizontalAccuracy, altitude: location.altitude,
            verticalAccuracy: location.verticalAccuracy, speed: location.speed, course: location.course,
            timestamp: location.timestamp
        )
    }
}
/// One fix request on its own `CLLocationManager`, as the official app does: updates at the best accuracy start,
/// the cached reading joins as a candidate, and ``OneShotSelector`` decides when to answer (a perfect reading
/// at once; at the timeout the best other one). A separate manager keeps these readings out of the significant-change
/// stream, where a late or cached one used to be mistaken for a move.
@MainActor
private final class OneShotLocation: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let timeout: TimeInterval
    private var selector: OneShotSelector
    private var continuation: CheckedContinuation<LocationFix, any Error>?
    /// Keeps the request alive until it answers (the delegate is weak).
    private var selfRetain: OneShotLocation?

    init(timeout: TimeInterval, notBefore: Date?) {
        self.timeout = timeout
        selector = OneShotSelector(notBefore: notBefore)
        super.init()
    }

    func run() async throws -> LocationFix {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            selfRetain = self
            manager.allowsBackgroundLocationUpdates = true
            manager.desiredAccuracy = kCLLocationAccuracyBest
            manager.delegate = self
            manager.startUpdatingLocation()
            Task { [weak self, timeout] in
                try? await Task.sleep(for: .seconds(OneShotFix.waitLimit(backgroundRemaining: .infinity, maximum: timeout)))
                self?.evaluate(outOfTime: true)
            }
            let box = UnsafeManager(manager)
            Task { [weak self] in
                let cached = await Self.cachedReading(of: box)
                self?.seed(cached)
            }
        }
    }

    /// The manager's cached reading and whether Approximate Location is on, read off the main thread.
    nonisolated static func cachedReading(of box: UnsafeManager) async -> (fix: LocationFix, reduced: Bool)? {
        return await Task.detached(priority: .userInitiated) {
            guard let location = box.manager.location else { return nil }
            return (LocationFix(location), box.manager.accuracyAuthorization == .reducedAccuracy)
        }.value
    }

    struct UnsafeManager: @unchecked Sendable {
        let manager: CLLocationManager
        init(_ manager: CLLocationManager) { self.manager = manager }
    }

    private func seed(_ cached: (fix: LocationFix, reduced: Bool)?) {
        guard continuation != nil, let cached else { return }
        selector.reduced = cached.reduced
        selector.add(cached.fix, now: .now)
        evaluate(outOfTime: false)
    }

    private func consider(_ fixes: [LocationFix]) {
        guard continuation != nil else { return }
        for fix in fixes { selector.add(fix, now: .now) }
        evaluate(outOfTime: false)
    }

    private func evaluate(outOfTime: Bool) {
        guard let continuation else { return }
        switch selector.verdict(outOfTime: outOfTime) {
        case .wait: return
        case .done(let fix): continuation.resume(returning: fix)
        case .fail: continuation.resume(throwing: LocationPlatformError.unavailable)
        }
        finish()
    }

    private func finish() {
        manager.stopUpdatingLocation()
        manager.delegate = nil
        continuation = nil
        selfRetain = nil
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let fixes = locations.map(LocationFix.init)
        Task { @MainActor in self.consider(fixes) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        // "Location unknown" is transient: Core Location keeps trying, and the timeout decides.
        if (error as? CLError)?.code == .locationUnknown { return }
        // Anything else is final: take what has arrived, or give up when nothing has.
        Task { @MainActor in self.evaluate(outOfTime: true) }
    }
}
#endif
