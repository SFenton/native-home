import Foundation
import HassCore

/// A scripted ``LocationPlatform``: records what the reporter asked for and hands out queued fixes.
@MainActor
public final class FakeLocationPlatform: LocationPlatform {
    public var permission: LocationPermission
    public var onEvent: (@MainActor (LocationPlatformEvent) -> Void)?
    public var fixes: [LocationFix] = []
    public var calls: [String] = []
    public var monitored: [PlannedRegion] = []

    public init(_ permission: LocationPermission) { self.permission = permission }

    public func requestWhenInUse() { calls.append("whenInUse") }
    public func requestAlways() { calls.append("always") }
    public var satisfied: Set<String> = []
    public var timeouts: [TimeInterval] = []
    public var onOpenMonitor: (() -> Void)?
    public var lastKnown: LocationFix?
    public func lastKnownFix() async -> LocationFix? { lastKnown }

    public var notBefores: [Date?] = []
    /// While set, every fix request waits at the gate before answering.
    public var gate: AsyncGate?
    /// How many requests the gate holds; later ones answer at once. Defaults to all of them.
    public var gatedRequests = Int.max

    public func currentFix(timeout: TimeInterval, notBefore: Date?) async throws -> LocationFix {
        timeouts.append(timeout)
        notBefores.append(notBefore)
        if let gate, gatedRequests > 0 {
            gatedRequests -= 1
            await gate.wait()
        }
        guard !fixes.isEmpty else { throw LocationPlatformError.unavailable }
        return fixes.removeFirst()
    }
    public func startSignificantChanges() { calls.append("startSignificant") }
    public func stopSignificantChanges() { calls.append("stopSignificant") }
    public func openZoneMonitor() async {
        calls.append("open")
        onOpenMonitor?()
    }
    public func satisfiedRegions() async -> Set<String> { satisfied }
    public func monitor(_ regions: [PlannedRegion]) async {
        calls.append("monitor \(regions.count)")
        monitored = regions
    }
    public func stopMonitoring() async {
        calls.append("stopMonitoring")
        monitored = []
    }
}

/// Records background-time holds: `begun` names, and how many are still held.
@MainActor
public final class RecordingBackgroundTime: BackgroundTime {
    public private(set) var begun: [String] = []
    public private(set) var held = 0
    public var remaining: TimeInterval = .infinity

    public init() {}

    public func begin(_ name: String) -> @MainActor () -> Void {
        begun.append(name)
        held += 1
        var released = false
        return { [self] in
            guard !released else { return }
            released = true
            held -= 1
        }
    }
}

/// Holds a fix request until a test opens it, and tells the test when a request has arrived.
@MainActor
public final class AsyncGate {
    private var opened = false
    private var entered = false
    private var waiter: CheckedContinuation<Void, Never>?
    private var arrival: CheckedContinuation<Void, Never>?

    public init() {}

    /// Called by the platform: suspends until ``open()``.
    public func wait() async {
        entered = true
        arrival?.resume()
        arrival = nil
        guard !opened else { return }
        await withCheckedContinuation { waiter = $0 }
    }

    /// Suspends until a request is waiting at the gate.
    public func untilEntered() async {
        guard !entered else { return }
        await withCheckedContinuation { arrival = $0 }
    }

    /// Lets the waiting request, and every later one, through.
    public func open() {
        opened = true
        waiter?.resume()
        waiter = nil
    }
}
