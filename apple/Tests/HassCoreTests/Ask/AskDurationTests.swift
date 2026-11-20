import Foundation
import Testing
@testable import HassCore

struct AskDurationTests {
    static let phraseRows: [PhraseRow] = [
        PhraseRow(seconds: 30, expected: "30 seconds"), PhraseRow(seconds: 89, expected: "89 seconds"),
        PhraseRow(seconds: 120, expected: "2 minutes"), PhraseRow(seconds: 5_340, expected: "89 minutes"),
        PhraseRow(seconds: 10_800, expected: "3 hours"), PhraseRow(seconds: 169_200, expected: "47 hours"),
        PhraseRow(seconds: 259_200, expected: "3 days"), PhraseRow(seconds: 216_000, expected: "2.5 days"),
    ]

    struct PhraseRow: Sendable { let seconds: Double; let expected: String }

    @Test(arguments: phraseRows) func phrases(row: PhraseRow) {
        #expect(AskDuration.phrase(seconds: row.seconds) == row.expected)
    }

    @Test func spokenMarksALowerBound() {
        let d = AskDuration(seconds: 7_200, since: AskDemoHouse.ago(7_200), atLeast: true, source: .restartBound)
        #expect(d.spoken == "at least 2 hours")
    }

    @Test func anOrdinaryLastChangedIsTrusted() async {
        let index = AskDemoHouse.index()
        let resolver = AskDurationResolver(index: index, dataSource: AskNoDataSource())
        let d = await resolver.resolve(index.entry("light.demo_kitchen_light")!)
        #expect(d.source == .lastChanged)
        #expect(d.atLeast == false)
        #expect(abs(d.seconds - 600) < 1)
    }

    /// Builds a house where most states changed at the same moment, as after a restart.
    private func restartedIndex() -> AskableIndex {
        let restart = AskDemoHouse.ago(80_000)
        var states = AskDemoHouse.states.map { s -> EntityState in
            var copy = s
            copy.lastChanged = restart.addingTimeInterval(Double(s.entityId.count % 60))
            return copy
        }
        // One entity that really changed a minute ago.
        states[0].lastChanged = AskDemoHouse.ago(60)
        var configuration = AskConfiguration()
        configuration.restartClusterMinimum = 10
        return AskDemoHouse.index(configuration: configuration, states: states)
    }

    @Test func aRestartClusterIsDetectedAndItsMembersAreFlagged() {
        let index = restartedIndex()
        #expect(index.restartTime != nil)
        let kitchen = index.entry("light.demo_kitchen_light")!
        let office = index.entry("light.demo_office_light")!
        #expect(AskRestartGuard.isRestartReset(kitchen.state, restart: index.restartTime, configuration: index.configuration) == false)
        #expect(AskRestartGuard.isRestartReset(office.state, restart: index.restartTime, configuration: index.configuration))
    }

    @Test func aRestartResetEntityWithoutHistoryGivesALowerBound() async {
        let index = restartedIndex()
        let resolver = AskDurationResolver(index: index, dataSource: AskStubSource(failsHistory: true))
        let d = await resolver.resolve(index.entry("light.demo_office_light")!)
        #expect(d.atLeast)
        #expect(d.source == .restartBound)
    }

    @Test func historyWalksBackOverAnUnavailableGap() async {
        let index = restartedIndex()
        let office = index.entry("light.demo_office_light")!
        let points = [
            AskHistoryPoint(at: AskDemoHouse.ago(5 * 3_600), state: "off"),
            AskHistoryPoint(at: AskDemoHouse.ago(4 * 3_600), state: "on"),
            AskHistoryPoint(at: AskDemoHouse.ago(3 * 3_600), state: "unavailable"),
            AskHistoryPoint(at: AskDemoHouse.ago(2 * 3_600), state: "on"),
        ]
        let resolver = AskDurationResolver(index: index, dataSource: AskStubSource(historyPoints: [office.id: points]))
        let d = await resolver.resolve(office)
        #expect(d.source == .history)
        #expect(d.atLeast == false)
        #expect(abs(d.seconds - 4 * 3_600) < 1)
    }

    @Test func aHistoryThatStartsAtTheWindowEdgeIsALowerBound() {
        let from = AskDemoHouse.ago(7 * 86_400)
        let points = [AskHistoryPoint(at: from, state: "on")]
        let d = AskDurationResolver.walkBack(points, current: "on", from: from, now: AskDemoHouse.now)
        #expect(d?.atLeast == true)
    }

    @Test func aHistoryEndingInAnotherStateGivesNothing() {
        let points = [AskHistoryPoint(at: AskDemoHouse.ago(3_600), state: "off")]
        #expect(AskDurationResolver.walkBack(points, current: "on", from: AskDemoHouse.ago(86_400), now: AskDemoHouse.now) == nil)
    }

    @Test func timestampsParseWithAndWithoutFractions() {
        #expect(AskDurationResolver.parse("2030-01-15T10:00:00+00:00") == AskDemoHouse.ago(7_200))
        #expect(AskDurationResolver.parse("2030-01-15T10:00:00.250+00:00") != nil)
        #expect(AskDurationResolver.parse("not a date") == nil)
    }

    @Test func anAnnotatorTimestampBeatsLastChanged() async {
        var configuration = AskConfiguration()
        configuration.annotators = [
            AskAnnotatorRule(platform: "demo_since", domain: "sensor", subjectAttribute: "entity_id", role: .since, attributes: [], valuePhrases: [:]),
        ]
        var states = AskDemoHouse.states
        states.append(AskDemoHouse.state("sensor.demo_since", "2030-01-14T12:00:00+00:00", ["entity_id": .string("light.demo_office_light")], name: "Demo Since"))
        var registry = AskDemoHouse.registry
        registry.append(AskRegistryEntity(entityId: "sensor.demo_since", platform: "demo_since"))
        let house = AskHouse(name: "Demo Home", states: states, registry: registry, areas: AskDemoHouse.areas, floors: AskDemoHouse.floors, document: AskDemoHouse.document(states), now: AskDemoHouse.now, timeZone: AskDemoHouse.utc)
        let index = AskableIndex(house: house, configuration: configuration)
        let d = await AskDurationResolver(index: index, dataSource: AskNoDataSource()).resolve(index.entry("light.demo_office_light")!)
        #expect(d.source == .annotator)
        #expect(abs(d.seconds - 86_400) < 1)
    }
}
