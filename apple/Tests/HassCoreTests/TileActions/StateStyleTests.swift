import Foundation
@testable import HassCore
import HassTestSupport
import Testing

private func entity(_ id: String, _ state: String, _ attributes: [String: JSONValue] = [:]) -> EntityState {
    EntityState(entityId: id, state: state, attributes: attributes)
}

// MARK: - The state map

@Suite struct StateMapTests {
    @Test func theFirstMatchingRuleWins() {
        let style = StateStyle(id: "t", name: "T", domain: "switch", actionId: "t", rules: [
            StateRule(["on"], .warning, words: "First"),
            StateRule(["on", "off"], .resting, words: "Second"),
            StateRule([], .unknown),
        ])
        #expect(style.resolve(entity("switch.demo_x", "on"), entityId: "switch.demo_x").words == "First")
        #expect(style.resolve(entity("switch.demo_x", "off"), entityId: "switch.demo_x").words == "Second")
    }

    @Test func aStateNoRuleNamesFallsToTheLastRule() {
        let style = StateStyle(id: "t", name: "T", domain: "sensor", actionId: "t", rules: [
            StateRule(["home"], .resting, active: true),
            StateRule([], .resting, words: "Elsewhere"),
        ])
        #expect(style.rules.count == 3, "the map's two rules and the unknown rule the style adds")
        let zone = style.resolve(entity("sensor.demo_x", "work"), entityId: "sensor.demo_x")
        #expect(zone.stateClass == .resting && zone.words == "Elsewhere", "an open-ended map falls back to resting")
    }

    @Test(arguments: ["unavailable", "unknown"])
    func anAuthoredMapWithNoUnknownRuleGetsOneThatIsNeverRestingOrTappable(_ state: String) throws {
        let style = StateStyle(id: "t", name: "T", domain: "lock", actionId: "t", rules: [
            StateRule(["locked"], .resting, action: StateAction(verb: "Unlock", symbol: "lock.fill", service: "unlock")),
            StateRule([], .resting, words: "Elsewhere"),
        ])
        let resolved = style.resolve(entity("lock.demo_x", state), entityId: "lock.demo_x")
        #expect(resolved.stateClass == .unknown, "an authored resting fallback does not describe an unavailable entity")
        let action = try #require(resolved.action)
        #expect(action.isTappable == false && action.call == nil && action.verb == "Unlock" && action.symbol == "lock.fill")
        #expect(style.spec(for: entity("lock.demo_x", state), entityId: "lock.demo_x")?.phase == .unavailable)
        #expect(style.resolve(nil, entityId: "lock.demo_x").stateClass == .unknown)
        #expect(style.rules.last?.states.isEmpty == true, "the fallback stays last")
    }

    @Test func aMapThatNamesItsUnknownRuleKeepsIt() {
        let own = StateRule(["unavailable", "unknown"], .unknown, words: "Gone")
        let style = StateStyle(id: "t", name: "T", domain: "switch", actionId: "t", rules: [StateRule(["on"], .resting), own, StateRule([], .resting)])
        #expect(style.rules.count == 3 && style.rules[1] == own)
        #expect(style.resolve(entity("switch.demo_x", "unavailable"), entityId: "switch.demo_x").words == "Gone")
    }

    @Test func aMapWithNoActionGainsNoDisc() {
        let style = StateStyle(id: "t", name: "T", domain: "sensor", actionId: "t", rules: [StateRule(["home"], .resting)])
        #expect(style.resolve(entity("sensor.demo_x", "unavailable"), entityId: "sensor.demo_x").action == nil)
        #expect(style.spec(for: nil, entityId: "sensor.demo_x") == nil)
    }

    @Test func aMapWithoutAFallbackGetsTheUnknownClass() {
        let style = StateStyle(id: "t", name: "T", domain: "switch", actionId: "t", rules: [StateRule(["on"], .resting)])
        #expect(style.rules.last?.states.isEmpty == true)
        #expect(style.resolve(entity("switch.demo_x", "strange"), entityId: "switch.demo_x").stateClass == .unknown)
    }

    @Test(arguments: StateStyle.builtIn)
    func unavailableAndUnknownAreTheUnknownClassInEveryStyle(_ style: StateStyle) {
        for state in ["unavailable", "unknown"] {
            let resolution = style.resolve(entity("sensor.demo_x", state), entityId: "sensor.demo_x")
            #expect(resolution.stateClass == .unknown && resolution.indicator == .none, "\(style.id): unknown never shows an arc")
            #expect(!resolution.isActive)
        }
        #expect(style.resolve(nil, entityId: "sensor.demo_x").stateClass == .unknown)
        #expect(style.rules.last?.states.isEmpty == true, "\(style.id) ends with a fallback rule")
    }

    @Test func wordsAreHomeAssistantsStateNamesUnlessGiven() {
        #expect(StateStyle.title("armed_home") == "Armed Home")
        #expect(StateStyle.title("opening") == "Opening")
        let alarm = StateStyle.alarm.resolve(entity("alarm_control_panel.demo_x", "armed_night"), entityId: "alarm_control_panel.demo_x")
        #expect(alarm.words == "Armed Night")
        #expect(StateStyle.title(nil) == "Unavailable")
    }
}

// MARK: - Indicators

@Suite struct StateIndicatorTests {
    @Test func theClassPicksTheDefaultIndicator() {
        #expect(StateStyle.defaultIndicator(.inProgress, hasAction: false) == .arcSpinner)
        #expect(StateStyle.defaultIndicator(.inProgress, hasAction: true) == .none, "a state with an action keeps its disc, so no arc")
        #expect(StateStyle.defaultIndicator(.warning, hasAction: false) == .pulse)
        #expect(StateStyle.defaultIndicator(.error, hasAction: true) == .wiggle)
        #expect(StateStyle.defaultIndicator(.resting, hasAction: false) == .none)
        #expect(StateStyle.defaultIndicator(.unknown, hasAction: false) == .none)
    }

    @Test func onlyBounceAndWigglePlayOnce() {
        #expect(StateIndicator.allCases.filter(\.playsOnce) == [.bounce, .wiggle])
        #expect(StateIndicator.allCases.count == 6, "the closed list: nothing else is authorable")
    }

    @Test func aRuleMayOverrideTheClassDefault() {
        let robot = StateStyle.robot.resolve(entity("vacuum.demo_x", "cleaning"), entityId: "vacuum.demo_x")
        #expect(robot.stateClass == .resting && robot.isActive && robot.indicator == .breathe)
    }

    @Test func aStyleWhoseInProgressStatesAuthorNoActionKeepsOneArcThroughThemAll() {
        let robot = StateStyle.robot.resolve(entity("vacuum.demo_x", "returning"), entityId: "vacuum.demo_x")
        #expect(robot.stateClass == .inProgress && robot.indicator == .arcSpinner && robot.action == nil)
    }
}

// MARK: - Built-in styles

@Suite(.demoHouse) struct BuiltInStyleTests {
    private let id = "cover.demo_garage_door_1"

    @Test func thereAreEightBuiltInStylesWithUniqueIds() {
        #expect(StateStyle.builtIn.map(\.id) == ["garage-door", "lock", "blind", "alarm", "robot", "detector", "notice", "switch"])
        #expect(Set(StateStyle.builtIn.map(\.id)).count == 8)
        #expect(StateStyle.builtIn(id: "alarm") == StateStyle.alarm && StateStyle.builtIn(id: "nope") == nil)
    }

    @Test func garageDoorClassesAndGlyphs() {
        func look(_ state: String, _ attributes: [String: JSONValue] = [:]) -> StateResolution {
            StateStyle.garageDoor.resolve(entity(id, state, attributes), entityId: id)
        }
        #expect(look("closed").stateClass == .resting && !look("closed").isActive && look("closed").glyph == "door.garage.closed")
        #expect(look("open").stateClass == .resting && look("open").isActive && look("open").glyph == "door.garage.open")
        let stop = look("opening", ["supported_features": .number(11)])
        #expect(stop.stateClass == .inProgress && stop.isActive && stop.glyph == "stop.fill" && stop.indicator == .none)
        #expect(look("opening").glyph == "arrow.uturn.down" && look("closing").glyph == "arrow.uturn.up")
    }

    @Test func garageDoorRequestSettingsAreTheWebs() throws {
        let request = try #require(StateStyle.garageDoor.request)
        // The web's `constants/garageDoors.ts` values, kept here since `GarageDoorController.Timing` was retired.
        #expect(request.lockout == .seconds(2) && request.ackTimeout == .seconds(10))
        #expect(request.settleTimeout == .seconds(45) && request.errorHold == .seconds(8))
        #expect(request.pendingWords["open_cover"] == "Sending Open…" && request.pendingWords["close_cover"] == "Sending Close…")
        #expect(request.errorWords == "Error" && request.onTimeout == .error)
    }

    @Test func garageDoorTapSendsTheCommandForTheLiveState() {
        // The web's `garageDoorCommandForState`, as `GarageDoorController.command(for:)` held it: closed or closing opens, open or opening closes.
        let expected: [String: String] = ["closed": "open_cover", "closing": "open_cover", "open": "close_cover", "opening": "close_cover"]
        for (state, service) in expected {
            #expect(StateStyle.garageDoor.spec(for: entity(id, state), entityId: id)?.call?.service == service, Comment(rawValue: state))
        }
        for state in ["unavailable", "unknown"] {
            #expect(StateStyle.garageDoor.spec(for: entity(id, state), entityId: id)?.call == nil, Comment(rawValue: state))
        }
    }

    @Test func lockStyleRequestSettings() throws {
        let request = try #require(StateStyle.lock.request)
        #expect(request.settleTimeout == .seconds(2) && request.onTimeout == .revert)
        #expect(request.errorHold == .seconds(4) && request.errorWords == "Didn't Respond")
    }

    @Test func blindOffersStopOnlyWhereTheCoverSupportsIt() throws {
        let blind = StateStyle.blind
        let moving = blind.resolve(entity("cover.demo_x", "opening", ["supported_features": .number(8)]), entityId: "cover.demo_x")
        #expect(moving.action?.verb == "Stop" && moving.indicator == .none)
        let unsupported = blind.resolve(entity("cover.demo_x", "closing"), entityId: "cover.demo_x")
        #expect(unsupported.action == nil && unsupported.indicator == .arcSpinner, "no action, so the arc stands in")
        #expect(blind.spec(for: entity("cover.demo_x", "closing"), entityId: "cover.demo_x") == nil)
    }

    @Test func detectorAndNoticeAndSwitch() {
        func cls(_ style: StateStyle, _ state: String) -> StateClass { style.resolve(entity("sensor.demo_x", state), entityId: "sensor.demo_x").stateClass }
        #expect(cls(.detector, "off") == .resting && cls(.detector, "on") == .error)
        #expect(cls(.notice, "off") == .resting && cls(.notice, "on") == .warning)
        let on = StateStyle.switch.resolve(entity("switch.demo_x", "on"), entityId: "switch.demo_x")
        #expect(on.stateClass == .resting && on.isActive)
        #expect(!StateStyle.switch.resolve(entity("switch.demo_x", "off"), entityId: "switch.demo_x").isActive)
    }

    @Test func robotClasses() {
        func cls(_ state: String) -> StateClass { StateStyle.robot.resolve(entity("vacuum.demo_x", state), entityId: "vacuum.demo_x").stateClass }
        #expect(cls("docked") == .resting && cls("idle") == .resting && cls("cleaning") == .resting && cls("mowing") == .resting)
        #expect(cls("paused") == .warning && cls("returning") == .inProgress && cls("error") == .error)
    }

    @Test func theThreeWarningsAreClassedWarning() {
        let lock = StateStyle.lock.resolve(entity("lock.demo_x", "open"), entityId: "lock.demo_x")
        let alarm = StateStyle.alarm.resolve(entity("alarm_control_panel.demo_x", "pending"), entityId: "alarm_control_panel.demo_x")
        let robot = StateStyle.robot.resolve(entity("vacuum.demo_x", "paused"), entityId: "vacuum.demo_x")
        for warning in [lock, alarm, robot] {
            #expect(warning.stateClass == .warning && warning.indicator == .pulse)
        }
        #expect(lock.action?.isTappable == true && alarm.action?.verb == "Disarm", "a warning that offers an action keeps it")
    }

    @Test func jammedAndTriggeredAreErrors() {
        #expect(StateStyle.lock.resolve(entity("lock.demo_x", "jammed"), entityId: "lock.demo_x").stateClass == .error)
        let triggered = StateStyle.alarm.resolve(entity("a.demo_x", "triggered"), entityId: "a.demo_x")
        #expect(triggered.stateClass == .error && triggered.indicator == .wiggle && triggered.action?.verb == "Disarm")
    }
}
