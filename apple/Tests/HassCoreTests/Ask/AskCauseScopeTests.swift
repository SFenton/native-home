import Foundation
import Testing
@testable import HassCore

/// A "why" answer speaks only about what the configuration names, and only what the lock state allows. Demo names only.
struct AskCauseScopeTests {
    // MARK: Helpers

    private static let hidden: Set<String> = ["automation.demo_hidden_rule", "script.demo_hidden_scene", "sensor.demo_hidden_probe", "person.demo_hidden_guest"]

    private static var states: [EntityState] {
        AskDemoHouse.states + [
            AskDemoHouse.state("automation.demo_hidden_rule", "on", name: "Demo Hidden Rule"),
            AskDemoHouse.state("script.demo_goodnight", "off", name: "Demo Goodnight"),
            AskDemoHouse.state("script.demo_hidden_scene", "off", name: "Demo Hidden Scene"),
            AskDemoHouse.state("sensor.demo_hidden_probe", "on", name: "Demo Hidden Probe"),
            AskDemoHouse.state("person.demo_hidden_guest", "home", ["user_id": .string("user-hidden")], name: "Demo Hidden Guest"),
        ]
    }

    private static func answerer(rows: [AskLogbookRow], withhold: Bool = false, extraStates: [EntityState] = []) -> AskAnswerer {
        var configuration = AskConfiguration()
        configuration.withholdSecurityState = withhold
        var all = states + extraStates
        // The person with a known user id.
        all = all.map { s in
            guard s.entityId == "person.demo_alex" else { return s }
            var copy = s
            copy.attributes["user_id"] = .string("user-alex")
            return copy
        }
        let document = AskHouseDocument(referencedEntityIds: Set(all.map(\.entityId)).subtracting(AskDemoHouse.unconfigured).subtracting(hidden))
        let house = AskHouse(
            name: "Demo Home", states: all, registry: AskDemoHouse.registry, areas: AskDemoHouse.areas, floors: AskDemoHouse.floors,
            document: document, now: AskDemoHouse.now, timeZone: AskDemoHouse.utc
        )
        let index = AskableIndex(house: house, configuration: configuration)
        return AskAnswerer(index: index, dataSource: AskStubSource(logbookRows: ["light.demo_kitchen_light": rows]))
    }

    private static func row(_ build: (inout AskLogbookRow) -> Void) -> AskLogbookRow {
        var r = AskLogbookRow(when: AskDemoHouse.ago(600), state: "on")
        build(&r)
        return r
    }

    private func why(_ rows: [AskLogbookRow], allowing: AskSensitivity = .security, withhold: Bool = false) async -> AskResult {
        await Self.answerer(rows: rows, withhold: withhold).answer("Why is the kitchen light on?", allowing: allowing)
    }

    // MARK: Unconfigured causes

    @Test func anUnconfiguredEntityIsNeverNamedOrStated() async {
        let result = await why([Self.row { $0.contextEntityId = "sensor.demo_hidden_probe"; $0.contextName = "Demo Hidden Probe"; $0.contextState = "on" }])
        #expect(result.answer.contains(AskCause.otherWording), "\(result.answer)")
        for leak in ["Hidden", "probe", "sensor.", "changed to"] { #expect(!result.answer.contains(leak), "\(result.answer)") }
        #expect(result.sensitivity == .everyday)
    }

    @Test func anEntityTheDocumentNeverNamesStaysUnnamedEvenWhenItIsInTheIndexAsAnOutsider() async {
        let result = await why([Self.row { $0.contextEntityId = "light.demo_porch_light"; $0.contextName = "Demo Porch Light"; $0.contextState = "on" }])
        #expect(result.answer.contains(AskCause.otherWording), "\(result.answer)")
        #expect(!result.answer.contains("Porch"), "\(result.answer)")
    }

    @Test func anUnconfiguredAutomationOrScriptIsNotNamed() async {
        let automation = await why([Self.row { $0.contextEventType = "automation_triggered"; $0.contextName = "Demo Hidden Rule"; $0.contextEntityId = "automation.demo_hidden_rule"; $0.contextMessage = "triggered by time" }])
        let script = await why([Self.row { $0.contextEventType = "script_started"; $0.contextName = "Demo Hidden Scene"; $0.contextEntityId = "script.demo_hidden_scene" }])
        let service = await why([Self.row { $0.contextEventType = "call_service"; $0.contextDomain = "script"; $0.contextName = "Demo Hidden Scene" }])
        for result in [automation, script, service] {
            #expect(result.answer.contains(AskCause.otherWording), "\(result.answer)")
            #expect(!result.answer.contains("Hidden"), "\(result.answer)")
            #expect(!result.answer.contains("triggered by time"), "\(result.answer)")
        }
    }

    @Test func anUnconfiguredPersonIsAGenericHouseholdMember() async {
        let result = await why([Self.row { $0.contextEventType = "call_service"; $0.contextUserId = "user-hidden"; $0.contextService = "turn_on" }])
        #expect(result.answer.contains("a household member"), "\(result.answer)")
        #expect(!result.answer.contains("Hidden"), "\(result.answer)")
    }

    // MARK: Configured causes

    @Test func aConfiguredAutomationAndScriptAreNamed() async {
        let automation = await why([Self.row { $0.contextEventType = "automation_triggered"; $0.contextName = "Demo Porch Schedule"; $0.contextEntityId = "automation.demo_porch_schedule" }])
        #expect(automation.answer.contains("Demo Porch Schedule"), "\(automation.answer)")
        let byName = await why([Self.row { $0.contextEventType = "automation_triggered"; $0.contextName = "Demo Porch Schedule" }])
        #expect(byName.answer.contains("Demo Porch Schedule"), "\(byName.answer)")
        let script = await why([Self.row { $0.contextEventType = "script_started"; $0.contextName = "Demo Goodnight"; $0.contextEntityId = "script.demo_goodnight" }])
        #expect(script.answer.contains("script \"Demo Goodnight\""), "\(script.answer)")
    }

    @Test func aConfiguredEverydayEntityIsNamedWithItsState() async {
        let result = await why([Self.row { $0.contextEntityId = "light.demo_office_light"; $0.contextState = "on" }], allowing: .everyday)
        #expect(result.answer.contains("Demo Office Light"), "\(result.answer)")
        #expect(result.answer.contains("on"), "\(result.answer)")
        #expect(result.path == .code)
    }

    @Test func aConfiguredPersonIsNamedOnlyWhereHomeClassIsAllowed() async {
        let rows = [Self.row { $0.contextEventType = "call_service"; $0.contextUserId = "user-alex"; $0.contextService = "turn_on" }]
        let allowed = await why(rows, allowing: .home)
        #expect(allowed.answer.contains("Demo Alex"), "\(allowed.answer)")
        #expect(allowed.sensitivity == .home)
        let locked = await why(rows, allowing: .everyday)
        #expect(locked.path == .fixedLocked)
        #expect(locked.answer == "Unlock your phone to ask about that.")
        #expect(!locked.answer.contains("Alex"))
    }

    // MARK: Security-class causes

    @Test func aSecurityCauseNeedsTheStricterClassAndIsWithheldByDefault() async {
        let rows = [Self.row { $0.contextEntityId = "lock.demo_front_door"; $0.contextState = "unlocked" }]
        let locked = await why(rows, allowing: .home)
        #expect(locked.path == .fixedLocked)
        #expect(locked.sensitivity == .security)
        #expect(!locked.answer.contains("Front Door") && !locked.answer.contains("unlocked"), "\(locked.answer)")
        let unlockedPhone = await why(rows, allowing: .security)
        #expect(unlockedPhone.path == .code)
        #expect(unlockedPhone.answer.contains("Demo Front Door Lock"), "\(unlockedPhone.answer)")
        let withheld = await why(rows, allowing: .security, withhold: true)
        #expect(withheld.path == .fixedWithheld)
        #expect(withheld.answer == "Open the app to check that.")
    }
}
