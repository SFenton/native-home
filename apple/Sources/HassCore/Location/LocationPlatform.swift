import Foundation

/// Something the location platform reports to ``LocationReporter``.
public enum LocationPlatformEvent: Equatable, Sendable {
    /// The person changed the permission (or Settings did).
    case permissionChanged(LocationPermission)
    /// iOS reported a significant location change.
    case significantChange(LocationFix)
    /// The phone crossed a monitored zone boundary.
    case zone(ZoneEvent)
}

/// Why the platform could not produce a fix.
public enum LocationPlatformError: Error, Equatable, Sendable {
    /// No permission, Location Services off, or no fix in time.
    case unavailable
}

/// The Apple location frameworks behind one seam, so ``LocationReporter``'s rules run in tests without Core
/// Location. The app's implementation is ``CoreLocationPlatform`` (iOS); tests use a fake.
@MainActor
public protocol LocationPlatform: AnyObject {
    /// The current permission.
    var permission: LocationPermission { get }
    /// Receives the platform's events; the reporter sets it.
    var onEvent: (@MainActor (LocationPlatformEvent) -> Void)? { get set }
    /// Asks for While Using the App.
    func requestWhenInUse()
    /// Asks to upgrade to Always.
    func requestAlways()
    /// A one-shot fix, graded like the official app's (``OneShotFix``): a perfect reading (100 m, 30 s) answers at
    /// once, an invalid one (over 600 s old, 1500 m, or at 0,0) is never used, and at `timeout` the best other
    /// reading answers. The cached reading is a candidate like any other.
    /// - Parameters:
    ///   - timeout: Seconds to wait.
    ///   - notBefore: Readings taken before this are ignored (a region exit must not be answered by a cached
    ///     reading from before the crossing).
    /// - Throws: ``LocationPlatformError/unavailable`` when nothing usable arrives within `timeout` seconds.
    func currentFix(timeout: TimeInterval, notBefore: Date?) async throws -> LocationFix
    /// The last position Core Location knows (its cached reading), if any: a reference for choosing zones when no
    /// fix has been taken yet, e.g. after a background relaunch. It may be old; never report it.
    func lastKnownFix() async -> LocationFix?
    /// Starts significant-change monitoring (wakes the app after about 500 m).
    func startSignificantChanges()
    /// Stops significant-change monitoring.
    func stopSignificantChanges()
    /// Opens the zone monitor so crossings iOS has queued (or detects next) are delivered, before any network call.
    /// Idempotent; watches nothing new by itself.
    func openZoneMonitor() async
    /// The ids of watched regions the phone is inside right now.
    func satisfiedRegions() async -> Set<String>
    /// Watches exactly `regions`, replacing any others.
    func monitor(_ regions: [PlannedRegion]) async
    /// Stops watching every region.
    func stopMonitoring() async
}

public extension LocationPlatform {
    /// A one-shot fix with no lower bound on the reading's time.
    func currentFix(timeout: TimeInterval) async throws -> LocationFix {
        try await currentFix(timeout: timeout, notBefore: nil)
    }
}
