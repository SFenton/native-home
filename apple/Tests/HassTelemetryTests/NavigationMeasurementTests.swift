import Foundation
@testable import HassTelemetry
import Testing

/// ``NavigationMeasurement`` and the phase stats it feeds (design: `.agents/design/motion.md` §10).
@MainActor
struct NavigationMeasurementTests {
    @Test func surfacesMapToTheirSignpostNames() {
        let names = NavigationMeasurement.Surface.allCases.map(\.kind)
        #expect(names == ["TabSwitch", "Push", "Pop", "SheetPresent", "SheetDismiss", "ZoomOpen", "ZoomClose"])
        #expect(NavigationMeasurement.Surface.sheetPresent.title == "Sheet opens")
        #expect(Set(NavigationMeasurement.Surface.allCases.map(\.title)).count == 7)
        #expect("\(Telemetry.Name.intro)" == "Intro" && "\(Telemetry.Name.arrival)" == "Arrival")
    }

    @Test func aTransitionRecordsFirstFrameSettledAndTurnCost() {
        let wasEnabled = Telemetry.isEnabled
        defer { Telemetry.isEnabled = wasEnabled }
        Telemetry.isEnabled = true
        let page = "measure-\(UUID().uuidString)"
        let measurement = NavigationMeasurement.begin(.push, page: page, measuresCost: true)
        measurement.firstFrame()
        measurement.firstFrame() // Idempotent.
        measurement.settled()
        measurement.settled() // Idempotent.
        let records = Telemetry.log.records.filter { $0.page == page }
        #expect(records.map(\.detail) == ["firstFrame", "settled", "p95Turn", "worstTurn"])
        #expect(records.allSatisfy { $0.kind == "Push" })
        #expect(records[0].durationMs != nil && records[1].durationMs != nil)
        #expect(records[2].value != nil && records[3].value != nil)
        let phases = Telemetry.log.phaseStats
        #expect(phases["Push.settled@\(page)"]?.count == 1)
        #expect(phases["Push.firstFrame"] != nil)
        #expect(phases["Push.worstTurn@\(page)"] != nil)
    }

    @Test func settlingWithoutAFirstFrameRecordsBoth() {
        let wasEnabled = Telemetry.isEnabled
        defer { Telemetry.isEnabled = wasEnabled }
        Telemetry.isEnabled = true
        let page = "direct-\(UUID().uuidString)"
        let measurement = NavigationMeasurement.begin(.tabSwitch, page: page, measuresCost: false)
        measurement.settled()
        let details = Telemetry.log.records.filter { $0.page == page }.map(\.detail)
        #expect(details == ["firstFrame", "settled"])
    }

    @Test func aCancelledTransitionRecordsNothing() {
        let wasEnabled = Telemetry.isEnabled
        defer { Telemetry.isEnabled = wasEnabled }
        Telemetry.isEnabled = true
        let page = "cancel-\(UUID().uuidString)"
        let measurement = NavigationMeasurement.begin(.sheetPresent, page: page, measuresCost: true)
        measurement.cancel()
        measurement.cancel()
        measurement.firstFrame() // Ignored once finished.
        measurement.settled()
        #expect(Telemetry.log.records.filter { $0.page == page }.isEmpty)
    }

    @Test func withTelemetryOffNothingIsLogged() {
        let wasEnabled = Telemetry.isEnabled
        defer { Telemetry.isEnabled = wasEnabled }
        Telemetry.isEnabled = false
        let page = "off-\(UUID().uuidString)"
        NavigationMeasurement.begin(.pop, page: page).settled()
        Telemetry.record(Telemetry.Name.pop, page: page, phase: .worstTurn, value: 3)
        #expect(Telemetry.log.records.filter { $0.page == page }.isEmpty)
    }

    @Test func phaseStatsGroupByKindPhaseAndPage() throws {
        let log = TelemetryLog()
        for ms in [10.0, 20, 30, 40] {
            log.record(TelemetryRecord(kind: "Push", page: "Room", durationMs: ms, detail: "settled"))
        }
        log.record(TelemetryRecord(kind: "Push", page: "Food", durationMs: 100, detail: "settled"))
        log.record(TelemetryRecord(kind: "Push", page: "Room", value: 6, detail: "worstTurn"))
        // Records without a phase detail are not phases.
        log.record(TelemetryRecord(kind: "Push", page: "Room", durationMs: 1, detail: "other"))
        log.record(TelemetryRecord(kind: "Push", durationMs: 1))
        let phases = log.phaseStats
        #expect(phases["Push.settled"]?.count == 5)
        #expect(phases["Push.settled@Room"]?.p50 == 20)
        #expect(phases["Push.settled@Food"]?.max == 100)
        #expect(phases["Push.worstTurn"]?.max == 6)
        #expect(phases.count == 5)
        let export = log.export()
        #expect(export.phases["Push.settled@Room"]?.count == 4)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(TelemetryExport.self, from: log.exportJSON())
        #expect(decoded.phases.count == 5)
    }
}
