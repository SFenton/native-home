import Foundation
@testable import HassCore
import HassDemoHouse
import Testing

/// The Air Quality chip summary reads the two helpers the house document's chip names, not built-in ids.
struct AirQualityChipSummaryTests {
    private func summary(in source: HouseConfigSource, states: [String: String]) -> String {
        HouseConfigSource.$scoped.withValue(source) {
            RoomOverview.airQualityChipSummary { id in states[id].map { EntityState(entityId: id, state: $0) } }
        }
    }

    private func airChip(in source: HouseConfigSource) throws -> HomeConfig.StatusChip {
        try #require(HouseConfigSource.$scoped.withValue(source) { HomeConfig.statusChips.first { $0.tone == .air } })
    }

    @Test func theDemoHouseSummaryReadsItsChipsAQIAndDetailHelpers() throws {
        let chip = try airChip(in: DemoHouse.source)
        let detail = try #require(chip.detailEntityId, "the demo chip names its PM2.5 helper")
        let text = summary(in: DemoHouse.source, states: [chip.entityId: "21 - 34", detail: "4 - 9"])
        #expect(text == "AQI 21 - 34 · PM2.5 4 - 9")
        #expect(summary(in: DemoHouse.source, states: [:]) == "AQI Unavailable · PM2.5 Unavailable")
    }

    @Test func aDemoChipWhoseDetailIsClearedShowsPM25AsUnavailable() throws {
        var config = DemoHouse.config
        let index = try #require(config.home.statusChips.firstIndex { $0.tone == .air })
        config.home.statusChips[index].detailEntityId = nil
        let source = HouseConfigSource()
        source.set(config)
        let chip = try airChip(in: source)
        #expect(summary(in: source, states: [chip.entityId: "12 - 30"]) == "AQI 12 - 30 · PM2.5 Unavailable")
    }

    @Test func aChipWithoutADetailHelperShowsNoPM25Detail() throws {
        var config = DemoHouse.config
        let index = try #require(config.home.statusChips.firstIndex { $0.tone == .air })
        let detail = try #require(config.home.statusChips[index].detailEntityId)
        config.home.statusChips[index].detailEntityId = nil
        let source = HouseConfigSource()
        source.set(config)
        let chip = try airChip(in: source)
        #expect(summary(in: source, states: [chip.entityId: "12 - 30", detail: "1 - 4"]) == "AQI 12 - 30 · PM2.5 Unavailable")
    }

    @Test func withoutADocumentTheSummaryReadsNothing() {
        #expect(summary(in: HouseConfigSource(), states: [:]) == "AQI Unavailable · PM2.5 Unavailable")
    }
}
