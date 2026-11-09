import Foundation
import HassDesign
import HassTelemetry
import Testing
@testable import HassUI

/// What Settings → Performance and its export show, built from a telemetry log and the saved MetricKit payloads.
@MainActor
struct DiagnosticsReportTests {
    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("diag-\(UUID().uuidString)")
    }

    private func phase(_ log: TelemetryLog, _ surface: NavigationMeasurement.Surface, _ phase: Telemetry.Phase, _ ms: Double, page: String? = nil) {
        log.record(TelemetryRecord(kind: surface.kind, page: page, durationMs: ms, detail: phase.rawValue))
    }

    // MARK: Navigation

    @Test func everyTransitionKnowsItsSurfaceAndPage() {
        let cases: [(NavigationTransition, NavigationMeasurement.Surface)] = [
            (.tabSwitch("Home"), .tabSwitch), (.push("Room"), .push), (.pop("Room"), .pop), (.sheetPresent("Cam"), .sheetPresent),
            (.sheetDismiss("Cam"), .sheetDismiss), (.zoomOpen("Recipe"), .zoomOpen), (.zoomClose("Recipe"), .zoomClose),
        ]
        for (transition, surface) in cases {
            #expect(transition.surface == surface)
            #expect(!transition.page.isEmpty)
        }
    }

    @Test func navigationRowsListOnlyMeasuredSurfacesAndSummariseThem() {
        let log = TelemetryLog()
        #expect(NavigationTelemetry.summary(from: log.phaseStats) == "none")
        phase(log, .push, .firstFrame, 10)
        phase(log, .push, .firstFrame, 30)
        phase(log, .push, .settled, 120)
        phase(log, .push, .p95Turn, 4)
        phase(log, .push, .worstTurn, 9)
        phase(log, .tabSwitch, .settled, 50, page: "Home")
        let rows = NavigationTelemetry.rows(from: log.phaseStats)
        #expect(rows.map(\.surface) == [.tabSwitch, .push])
        let push = rows[1]
        #expect(push.id == "push")
        #expect(push.count == 1, "the settled count when there is one")
        #expect(push.firstFrame?.count == 2)
        #expect(rows[0].firstFrame == nil && rows[0].settled?.count == 1)
        let summary = NavigationTelemetry.summary(from: log.phaseStats)
        #expect(summary.contains("push.n=1"))
        #expect(summary.contains("push.first.p50="))
        #expect(summary.contains("push.settled.p95=120.00"))
        #expect(summary.contains("push.turn.p95=4.00"))
        #expect(summary.contains("push.turn.worst=9.00"))
        #expect(summary.contains("tabSwitch.settled.p50=50.00"))
        let firstFrameOnly = NavigationTelemetry.Row(surface: .pop, firstFrame: TelemetryStats([5]), settled: nil, turnP95: nil, turnWorst: nil)
        #expect(firstFrameOnly.count == 1)
        #expect(NavigationTelemetry.Row(surface: .pop, firstFrame: nil, settled: nil, turnP95: nil, turnWorst: nil).count == 0)
    }

    // MARK: MetricKit payloads

    @Test func savedPayloadsComeBackNewestFirstAsParsedJSON() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let collector = MetricKitCollector(directory: directory)
        #expect(collector.payloads().isEmpty)
        collector.store(Data(#"{"n":1}"#.utf8), kind: "metrics", date: Date(timeIntervalSince1970: 100))
        collector.store(Data(#"{"n":2}"#.utf8), kind: "diagnostics", date: Date(timeIntervalSince1970: 200))
        #expect(collector.payloads().count == 2)
        #expect(collector.payloads().first?.lastPathComponent.hasPrefix("metrics") == true, "named newest first by file name")
        #expect(collector.payloadObjects().count == 2)
        collector.removeAll()
        #expect(collector.payloads().isEmpty)
    }

    @Test func theLatestScrollHitchRatioIsReadFromAnyDepthInAnyOfTheThreeShapes() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let collector = MetricKitCollector(directory: directory)
        #expect(collector.latestScrollHitchRatio() == nil)
        collector.store(Data(#"{"diag":1}"#.utf8), kind: "diagnostics", date: Date(timeIntervalSince1970: 100))
        #expect(collector.latestScrollHitchRatio() == nil, "diagnostics are not metrics")
        collector.store(Data(#"{"a":[{"animationMetrics":{"scrollHitchTimeRatio":"3.2 ms per s"}}]}"#.utf8), kind: "metrics", date: Date(timeIntervalSince1970: 300))
        #expect(collector.latestScrollHitchRatio() == 3.2)
        #expect(MetricKitCollector.findHitchRatio(in: ["scrollHitchTimeRatio": ["value": 1.5, "unit": "ms"]]) == 1.5)
        #expect(MetricKitCollector.findHitchRatio(in: ["x": ["scrollHitchTimeRatio": 0.7]]) == 0.7)
        #expect(MetricKitCollector.findHitchRatio(in: ["x": [1, 2], "y": "z"]) == nil)
        #expect(MetricKitCollector.findHitchRatio(in: "plain") == nil)
    }

    // MARK: Report

    @Test func theReportRanksPagesAndScrollingWorstFirstAndCountsWhatWasLogged() throws {
        let log = TelemetryLog()
        let prefix = "\(Telemetry.Name.contentReady)"
        log.record(TelemetryRecord(kind: prefix + "@Slow", durationMs: 900))
        log.record(TelemetryRecord(kind: prefix + "@Fast", durationMs: 100))
        log.increment("image.demo_hit", by: 3)
        log.addScroll(page: "Smooth", frameMs: [8, 8, 8, 8], budgetMs: 16.7)
        log.addScroll(page: "Janky", frameMs: [8, 80, 8, 90], budgetMs: 16.7)
        phase(log, .push, .settled, 100)
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let report = PerformanceReport.current(log: log, metricKit: MetricKitCollector(directory: directory))
        #expect(report.pages.map(\.name) == ["Slow", "Fast"])
        #expect(report.scroll.map(\.page).first == "Janky")
        #expect(report.counter("image.demo_hit") == 3)
        #expect(report.counter("never") == 0)
        #expect(report.navigation.map(\.surface) == [.push])
        #expect(report.recordCount == 3)
        #expect(report.metricKitPayloads == 0)
        #expect(report.metricKitHitchRatio == nil)
    }

    @Test func theExportFileHoldsTheTelemetryTheMetricKitPayloadsAndTheEnvironment() async throws {
        let log = TelemetryLog()
        log.increment("export.test")
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let collector = MetricKitCollector(directory: directory)
        collector.store(Data(#"{"n":1}"#.utf8), kind: "metrics")
        let environment = PerformanceReport.environment()
        #expect(environment["os"]?.isEmpty == false)
        #expect(environment["app"] != nil && environment["thermalState"] != nil && environment["device"] != nil)
        let sync = try PerformanceReport.writeExport(log: log, metricKit: collector)
        let async = try await PerformanceReport.writeExportAsync(log: log, metricKit: collector)
        // Written in the same second they share a name: read before removing.
        defer { try? FileManager.default.removeItem(at: sync); try? FileManager.default.removeItem(at: async) }
        for url in [sync, async] {
            let object = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
            #expect((object["metricKit"] as? [Any])?.count == 1)
            let telemetry = try #require(object["telemetry"] as? [String: Any])
            #expect((telemetry["counters"] as? [String: Int])?["export.test"] == 1)
            #expect(url.lastPathComponent.hasPrefix("FentonHome-telemetry-"))
        }
    }
}
