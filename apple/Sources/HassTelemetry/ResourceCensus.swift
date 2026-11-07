import Foundation
import os
#if canImport(Darwin)
import Darwin
#endif

/// A census of the live resources the app's lifecycle objects hold: notification observers, subscriptions, tasks,
/// display links, players. Pattern: `.agents/patterns/resume-lifecycle.md`.
///
/// **Why it exists.** Owner report 2026-10-16: scrolling got worse after every background and foreground. That
/// pattern means something is added on each resume and never removed, and none of those things (an observer
/// token dropped without `removeObserver`, a task that outlives its screen) show up as a failure. Each lifecycle
/// object registers a gauge for what it holds; a test or a journey takes the census after the first launch and again
/// after every resume, and the two must be equal. The numbers are plain counts, never entity ids or values.
///
/// Gauges are read on the main actor, where the objects that register them live. A registration ends when its
/// token is released, so an object that goes away takes its gauges with it. Several objects can register one
/// name (two connections in a test); the census sums them. Tests of one object read its own `liveResources`.
///
/// Usage:
/// ```swift
/// // In the object's init:
/// census = ResourceCensus.shared.register { [weak self] in self?.liveResources ?? [:] }
/// ```
public final class ResourceCensus: Sendable {
    /// The app's census.
    public static let shared = ResourceCensus()

    /// Holds a gauge in the census until it is released.
    public final class Registration: Sendable {
        private let census: ResourceCensus
        fileprivate let id: Int

        fileprivate init(census: ResourceCensus, id: Int) {
            self.census = census
            self.id = id
        }

        deinit { census.remove(id) }
    }

    private struct Gauge: Sendable {
        var read: @MainActor @Sendable () -> [String: Int]
    }

    private struct Storage: Sendable {
        var nextID = 0
        var gauges: [Int: Gauge] = [:]
    }

    private let storage = OSAllocatedUnfairLock(initialState: Storage())

    /// Creates a census (tests make their own; the app uses ``shared``).
    public init() {}

    // MARK: - Registering

    /// Adds a gauge. Keep the returned token for as long as the gauge should count.
    /// - Parameter read: The owner's current counts by name, `Owner.thing` (`Connection.statesSubscription`). Capture
    ///   the owner weakly and answer an empty dictionary once it is gone.
    /// - Returns: The token; releasing it removes the gauge.
    public func register(_ read: @escaping @MainActor @Sendable () -> [String: Int]) -> Registration {
        let id = storage.withLock { storage in
            storage.nextID += 1
            storage.gauges[storage.nextID] = Gauge(read: read)
            return storage.nextID
        }
        return Registration(census: self, id: id)
    }

    fileprivate func remove(_ id: Int) {
        storage.withLock { $0.gauges[id] = nil }
    }

    // MARK: - Reading

    /// Every gauge's count, summed by name.
    @MainActor
    public func counts() -> [String: Int] {
        let gauges = storage.withLock { Array($0.gauges.values) }
        var counts: [String: Int] = [:]
        for gauge in gauges {
            for (name, count) in gauge.read() { counts[name, default: 0] += count }
        }
        return counts
    }

    /// The counts as one line, `name=count` pairs sorted by name: the text a debug probe exposes and a journey compares.
    @MainActor
    public func summary() -> String {
        Self.summary(of: counts())
    }

    /// Formats counts as ``summary()`` does.
    public static func summary(of counts: [String: Int]) -> String {
        counts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
    }

    /// Parses a ``summary()`` line back into counts.
    public static func counts(fromSummary text: String) -> [String: Int] {
        var counts: [String: Int] = [:]
        for pair in text.split(separator: " ") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            if parts.count == 2, let value = Int(parts[1]) { counts[String(parts[0])] = value }
        }
        return counts
    }

    // MARK: - The process

    /// The process' thread count (a thread that never exits is a leak the gauges above can't name). nil where the
    /// system can't say.
    public static func threadCount() -> Int? {
        #if canImport(Darwin)
        var threads: thread_act_array_t?
        var count: mach_msg_type_number_t = 0
        guard task_threads(mach_task_self_, &threads, &count) == KERN_SUCCESS, let threads else { return nil }
        // The call hands back a send right per thread and the array itself; give both back.
        for index in 0..<Int(count) { mach_port_deallocate(mach_task_self_, threads[index]) }
        let size = vm_size_t(Int(count) * MemoryLayout<thread_t>.stride)
        vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: threads)), size)
        return Int(count)
        #else
        return nil
        #endif
    }
}
