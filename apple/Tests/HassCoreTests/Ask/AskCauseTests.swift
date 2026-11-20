import Foundation
import Testing
@testable import HassCore

struct AskCauseTests {
    private func index(restart: Bool = false) -> AskableIndex { AskDemoHouse.index() }

    private func row(_ secondsAgo: TimeInterval, state: String = "on", _ build: (inout AskLogbookRow) -> Void = { _ in }) -> AskLogbookRow {
        var r = AskLogbookRow(when: AskDemoHouse.ago(secondsAgo), state: state)
        build(&r)
        return r
    }

    private func cause(_ rows: [AskLogbookRow], id: String = "light.demo_kitchen_light") async -> AskCause {
        let idx = index()
        let resolver = AskCauseResolver(index: idx, dataSource: AskStubSource(logbookRows: [id: rows]))
        return await resolver.resolve(idx.entry(id)!).cause
    }

    @Test func anAutomationRowNamesTheAutomation() async {
        let result = await cause([row(600) { $0.contextEventType = "automation_triggered"; $0.contextName = "Demo Dusk"; $0.contextMessage = "triggered by time" }])
        guard case .automation(let name, let message, _) = result else { Issue.record("not an automation: \(result)"); return }
        #expect(name == "Demo Dusk")
        #expect(message == "triggered by time")
    }

    @Test func aRowWithNoContextMeansSomeoneDidItByHand() async {
        let result = await cause([row(600)])
        guard case .physical = result else { Issue.record("not physical: \(result)"); return }
    }

    @Test func aServiceCallWithoutAnActorIsNotAttributed() async {
        let result = await cause([row(600) { $0.contextDomain = "light"; $0.contextService = "turn_on" }])
        guard case .service(let service, _) = result else { Issue.record("not a service: \(result)"); return }
        #expect(service == "turn_on")
    }

    @Test func noRowInTheWindowGivesNone() async {
        #expect(await cause([]) == AskCause.none)
    }

    @Test func aRowOutsideTheWindowIsIgnored() async {
        #expect(await cause([row(60 * 60 * 5)]) == AskCause.none)
    }

    @Test func aFailingSourceGivesNone() async {
        let idx = index()
        let resolver = AskCauseResolver(index: idx, dataSource: AskNoDataSource())
        #expect(await resolver.resolve(idx.entry("light.demo_kitchen_light")!).cause == AskCause.none)
    }

    @Test func aRestartResetEntityReportsRestartWithoutALookup() async {
        let restart = AskDemoHouse.ago(80_000)
        var states = AskDemoHouse.states.map { s -> EntityState in
            var copy = s
            copy.lastChanged = restart.addingTimeInterval(Double(s.entityId.count % 60))
            return copy
        }
        states[0].lastChanged = AskDemoHouse.ago(60)
        var configuration = AskConfiguration()
        configuration.restartClusterMinimum = 10
        let idx = AskDemoHouse.index(configuration: configuration, states: states)
        let resolver = AskCauseResolver(index: idx, dataSource: AskStubSource(failsHistory: true))
        #expect(await resolver.resolve(idx.entry("light.demo_office_light")!).cause == .restart)
    }

    @Test func annotatorLinesComeFirst() async {
        var configuration = AskConfiguration()
        configuration.annotators = [
            AskAnnotatorRule(platform: "demo_ctl", domain: "sensor", subjectAttribute: "entity_id", role: .why, attributes: ["reason"], valuePhrases: [:]),
        ]
        var states = AskDemoHouse.states
        states.append(AskDemoHouse.state("sensor.demo_ctl", "idle", ["entity_id": .string("light.demo_office_light"), "reason": .string("the room cleared")], name: "Demo Controller"))
        var registry = AskDemoHouse.registry
        registry.append(AskRegistryEntity(entityId: "sensor.demo_ctl", platform: "demo_ctl"))
        let house = AskHouse(name: "Demo Home", states: states, registry: registry, areas: AskDemoHouse.areas, floors: AskDemoHouse.floors, document: AskDemoHouse.document(states), now: AskDemoHouse.now, timeZone: AskDemoHouse.utc)
        let idx = AskableIndex(house: house, configuration: configuration)
        let result = await AskCauseResolver(index: idx, dataSource: AskNoDataSource()).resolve(idx.entry("light.demo_office_light")!)
        #expect(result.annotatorLines.contains { $0.contains("the room cleared") })
    }
}
