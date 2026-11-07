import Foundation
@testable import HassTelemetry
import Testing

/// ``Telemetry`` and ``TelemetryLog``: enablement, the ring buffer, stats, scroll hitches and export.
struct TelemetryTests {
    @Test func enabledFollowsEnvironmentThenSavedSwitchThenBuild() throws {
        let defaults = try #require(UserDefaults(suiteName: "telemetry.tests.\(UUID())"))
        #expect(Telemetry.defaultEnabled(environment: ["FENTON_TELEMETRY": "1"], defaults: defaults))
        #expect(!Telemetry.defaultEnabled(environment: ["FENTON_TELEMETRY": "0"], defaults: defaults))
        defaults.set(false, forKey: Telemetry.enabledDefaultsKey)
        #expect(!Telemetry.defaultEnabled(environment: [:], defaults: defaults))
        defaults.set(true, forKey: Telemetry.enabledDefaultsKey)
        #expect(Telemetry.defaultEnabled(environment: [:], defaults: defaults))
        defaults.removeObject(forKey: Telemetry.enabledDefaultsKey)
        #if DEBUG
        #expect(Telemetry.defaultEnabled(environment: [:], defaults: defaults))
        #endif
    }

    @Test func ringKeepsTheNewestRecordsInOrder() {
        let log = TelemetryLog(capacity: 3)
        for index in 0..<5 { log.record(TelemetryRecord(kind: "k", value: Double(index))) }
        #expect(log.records.map(\.value) == [2, 3, 4])
        log.reset()
        #expect(log.records.isEmpty)
    }

    @Test func statsGroupByKindAndPage() throws {
        let log = TelemetryLog()
        for ms in [10.0, 20, 30, 40] { log.record(TelemetryRecord(kind: "ContentReady", page: "Home", durationMs: ms)) }
        log.record(TelemetryRecord(kind: "Hitch", page: "Rooms", value: 12))
        log.record(TelemetryRecord(kind: "Note"))
        let stats = log.stats
        let ready = try #require(stats["ContentReady"])
        #expect(ready.count == 4)
        #expect(ready.mean == 25)
        #expect(ready.p50 == 20)
        #expect(ready.p95 == 40)
        #expect(ready.max == 40)
        #expect(stats["ContentReady@Home"]?.count == 4)
        #expect(stats["Hitch@Rooms"]?.max == 12)
        #expect(stats["Note"] == nil)
        #expect(TelemetryStats([]) == nil)
    }

    @Test func scrollCountsFramesLateByHalfABudgetAsHitches() throws {
        let log = TelemetryLog()
        // 120 Hz: 8.33 ms budget. 10 ms is jitter; 25 ms and 50 ms are hitches.
        log.addScroll(page: "Recipes", frameMs: [8.33, 10, 25, 50], budgetMs: 8.33)
        log.addScroll(page: "Recipes", frameMs: [], budgetMs: 8.33)
        let stats = try #require(log.scroll["Recipes"])
        #expect(stats.frames == 4)
        #expect(stats.hitches == 2)
        #expect(abs(stats.hitchMs - (25 - 8.33 + 50 - 8.33)) < 0.001)
        #expect(stats.worstFrameMs == 50)
        #expect(stats.hitchRatio > 0)
        #expect(ScrollStats().hitchRatio == 0)
    }

    @Test func countersAndExportRoundTrip() throws {
        let log = TelemetryLog()
        log.increment("image.memoryHits")
        log.increment("image.memoryHits", by: 2)
        log.record(TelemetryRecord(kind: "ImageFetch", durationMs: 12, detail: "304"))
        let data = try log.exportJSON(environment: ["device": "test"], now: Date(timeIntervalSince1970: 0))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let export = try decoder.decode(TelemetryExport.self, from: data)
        #expect(export.counters["image.memoryHits"] == 3)
        #expect(export.environment["device"] == "test")
        #expect(export.records.first?.detail == "304")
        #expect(export.stats["ImageFetch"]?.count == 1)
    }

    /// On the main actor so the global switch cannot be flipped by another suite's main-actor test between the lines.
    @MainActor
    @Test func intervalsAndEventsRecordWhileEnabled() {
        let wasEnabled = Telemetry.isEnabled
        defer { Telemetry.isEnabled = wasEnabled }
        Telemetry.isEnabled = true
        let before = Telemetry.log.records.count
        let interval = Telemetry.begin(Telemetry.Name.imageFetch, page: "Test", "message")
        let ms = Telemetry.end(interval, value: 3, detail: "200")
        #expect(ms >= 0)
        Telemetry.event(Telemetry.Name.hitch, page: "Test", value: 20, detail: "late")
        let measured = Telemetry.measure(Telemetry.Name.imageDecode) { 42 }
        #expect(measured == 42)
        Telemetry.count("test.counter")
        #expect(Telemetry.log.records.count >= before + 3)
        #expect((Telemetry.log.counters["test.counter"] ?? 0) >= 1)

        Telemetry.isEnabled = false
        let quiet = Telemetry.log.records.count
        Telemetry.event(Telemetry.Name.hitch)
        Telemetry.count("test.counter.off")
        #expect(Telemetry.log.records.count == quiet)
        #expect(Telemetry.log.counters["test.counter.off"] == nil)
    }

    @Test func durationMilliseconds() {
        #expect(Duration.milliseconds(1500).milliseconds == 1500)
        #expect(Duration.seconds(2).milliseconds == 2000)
    }
}
