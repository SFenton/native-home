import Foundation
import os

/// The in-app telemetry store: a bounded ring of samples, counters and per-page scroll stats.
///
/// Thread-safe; the image cache records from background decoding.
public final class TelemetryLog: Sendable {
    struct Storage {
        var records: [TelemetryRecord] = []
        var head = 0
        var counters: [String: Int] = [:]
        var scroll: [String: ScrollStats] = [:]
    }

    /// The most samples kept; older ones are overwritten.
    public let capacity: Int
    private let storage = OSAllocatedUnfairLock(initialState: Storage())

    /// Creates a log.
    public init(capacity: Int = 4000) {
        self.capacity = capacity
    }

    // MARK: Writing

    /// Adds a sample, overwriting the oldest when full.
    public func record(_ record: TelemetryRecord) {
        let capacity = capacity
        storage.withLock { storage in
            if storage.records.count < capacity {
                storage.records.append(record)
            } else {
                storage.records[storage.head] = record
                storage.head = (storage.head + 1) % capacity
            }
        }
    }

    /// Adds to a counter.
    public func increment(_ counter: String, by amount: Int = 1) {
        storage.withLock { $0.counters[counter, default: 0] += amount }
    }

    /// Adds frames from a scroll on `page`.
    /// - Parameters:
    ///   - page: The page that scrolled.
    ///   - frameMs: Each frame's duration in milliseconds.
    ///   - budgetMs: The display's frame budget (16.7 at 60 Hz, 8.3 at 120 Hz).
    public func addScroll(page: String, frameMs: [Double], budgetMs: Double) {
        guard !frameMs.isEmpty else { return }
        storage.withLock { storage in
            var stats = storage.scroll[page] ?? ScrollStats()
            for frame in frameMs {
                stats.frames += 1
                stats.scrollSeconds += frame / 1000
                stats.worstFrameMs = max(stats.worstFrameMs, frame)
                // A frame counts as a hitch once it runs past half a budget late, so jitter isn't counted.
                let late = frame - budgetMs
                if late > budgetMs / 2 {
                    stats.hitches += 1
                    stats.hitchMs += late
                }
            }
            storage.scroll[page] = stats
        }
    }

    /// Forgets everything.
    public func reset() {
        storage.withLock { $0 = Storage() }
    }

    // MARK: Reading

    /// Samples, oldest first.
    public var records: [TelemetryRecord] {
        storage.withLock { storage in
            Array(storage.records[storage.head...] + storage.records[..<storage.head])
        }
    }

    /// Counter totals.
    public var counters: [String: Int] { storage.withLock { $0.counters } }

    /// Scroll smoothness per page.
    public var scroll: [String: ScrollStats] { storage.withLock { $0.scroll } }

    /// Stats per kind, and per kind and page (`kind@page`).
    public var stats: [String: TelemetryStats] {
        var samples: [String: [Double]] = [:]
        for record in records {
            guard let sample = record.durationMs ?? record.value else { continue }
            samples[record.kind, default: []].append(sample)
            if let page = record.page { samples["\(record.kind)@\(page)", default: []].append(sample) }
        }
        return samples.compactMapValues(TelemetryStats.init)
    }

    /// Stats per transition phase: `<kind>.<phase>` and `<kind>.<phase>@<page>`, for the records ``Telemetry/lap(_:phase:)`` and
    /// ``Telemetry/record(_:page:phase:value:)`` write (`TabSwitch.firstFrame`, `Push.settled@Room`, `Push.worstTurn`).
    public var phaseStats: [String: TelemetryStats] {
        var samples: [String: [Double]] = [:]
        for record in records {
            guard let detail = record.detail, Telemetry.Phase(rawValue: detail) != nil,
                  let sample = record.durationMs ?? record.value else { continue }
            samples["\(record.kind).\(detail)", default: []].append(sample)
            if let page = record.page { samples["\(record.kind).\(detail)@\(page)", default: []].append(sample) }
        }
        return samples.compactMapValues(TelemetryStats.init)
    }

    /// Everything, for the export file.
    public func export(environment: [String: String] = [:], now: Date = .now) -> TelemetryExport {
        TelemetryExport(exportedAt: now, environment: environment, counters: counters, stats: stats, phases: phaseStats, scroll: scroll,
                        records: records)
    }

    /// The export as pretty-printed JSON.
    public func exportJSON(environment: [String: String] = [:], now: Date = .now) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(export(environment: environment, now: now))
    }
}
