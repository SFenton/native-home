import Foundation
@testable import HassCore
import Testing

// MARK: - Authored state styles (`sh.state-style@1`)

/// The decoder for the style library and the `state-tile` binding, over the shared corpus the Studio writes
/// (`ContractCorpus/state-styles/built-in.json`, `accept/state-style-*.json`). The corpus index runs every case through the compiler
/// (`ServerUIContractCorpusTests`); these tests read what the decoder made of them.
@Suite(.timeLimit(.minutes(1)))
struct ServerUIStateStyleTests {
    private static let corpus = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("ContractCorpus", isDirectory: true)

    private static func json(_ path: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: corpus.appendingPathComponent(path)))
    }

    private static func publication(_ name: String) throws -> ServerUICompositionPublication {
        try ServerUICompositionPublication.decode(Data(contentsOf: corpus.appendingPathComponent("accept/state-style-\(name).json")))
    }

    private static func tile(_ publication: ServerUICompositionPublication) throws -> ServerUICompositionDocument.StateTile {
        for component in publication.document.pages.flatMap(\.surface.components) {
            if case .stateTile(let tile) = component { return tile }
        }
        throw CocoaError(.fileReadCorruptFile)
    }

    private static func entity(_ id: String, _ state: String) -> EntityState { EntityState(entityId: id, state: state) }

    // MARK: Fixture parity

    @Test func theBuiltInFixtureDecodesToTheAppsBuiltInStyles() throws {
        let fixture = try Self.json("state-styles/built-in.json")
        #expect(fixture["format"]?.number == 1)
        let decoded = ServerUIStateStyles.decodeLibrary(fixture, at: "")
        #expect(decoded.issues.isEmpty, "the built-in data raises no issue")
        #expect(decoded.library.entries.map(\.style.id) == StateStyle.builtIn.map(\.id))
        for (entry, builtIn) in zip(decoded.library.entries, StateStyle.builtIn) {
            #expect(entry.style == builtIn, "\(builtIn.id) differs from the fixture")
        }
    }

    @Test func everyBuiltInStyleEndsWithAFallbackThatCopiesItsUnknownRule() {
        for style in StateStyle.builtIn {
            #expect(style.rules.last?.states.isEmpty == true, "\(style.id)")
            let unknown = style.rules.first { $0.stateClass == .unknown }
            #expect(unknown.map { var copy = $0; copy.states = []; return copy } == style.rules.last, "\(style.id)")
        }
    }

    @Test func theCapabilityNameIsTheOneBothRepositoriesShare() {
        #expect(serverUIStateStyleCapability == "sh.state-style@1")
        #expect(ServerUICompositionPublication.supportedCapabilities.contains(serverUIStateStyleCapability))
    }

    // MARK: Decoding a library

    @Test func anAuthoredLibraryDecodesIntoStateStyles() throws {
        let publication = try Self.publication("authored-vacuum")
        let library = try #require(publication.document.stateStyles)
        let entry = try #require(library.entries.first)
        #expect(entry.base == "robot")
        let style = try #require(library.style(id: "tidy-vacuum"))
        #expect(style.domain == "vacuum" && style.actionId == "tidy-vacuum")
        #expect(style.rules.last?.states.isEmpty == true, "the authored fallback ends the map")
        let cleaning = style.resolve(Self.entity("vacuum.demo_robot", "cleaning"), entityId: "vacuum.demo_robot")
        #expect(cleaning.stateClass == .resting && cleaning.isActive && cleaning.glyph == "fan" && cleaning.words == "Tidying" && cleaning.indicator == .breathe)
        let returning = style.resolve(Self.entity("vacuum.demo_robot", "returning"), entityId: "vacuum.demo_robot")
        #expect(returning.stateClass == .inProgress && returning.indicator == .arcSpinner, "an authored arc on a state with no action")
        let paused = style.resolve(Self.entity("vacuum.demo_robot", "paused"), entityId: "vacuum.demo_robot")
        #expect(paused.stateClass == .warning && paused.colour == nil, "the corpus puts no colour on a warning state")
    }

    @Test func aStateTheMapDoesNotNameUsesTheFallback() throws {
        let style = try #require(Self.publication("authored-vacuum").document.stateStyles?.style(id: "tidy-vacuum"))
        let mystery = style.resolve(Self.entity("vacuum.demo_robot", "defrosting"), entityId: "vacuum.demo_robot")
        #expect(mystery.stateClass == .unknown)
        #expect(mystery.words == "Defrosting", "the state's own name, title-cased")
    }

    @Test func aStateWithAnActionDecodesTheActionAndTheRequestSettings() throws {
        let library = try #require(Self.publication("request-lifecycle").document.stateStyles)
        let style = try #require(library.style(id: "player"))
        let off = style.resolve(Self.entity("media_player.demo_player", "off"), entityId: "media_player.demo_player")
        #expect(off.action?.verb == "Turn On" && off.action?.call == ServiceCall("media_player", "turn_on", target: "media_player.demo_player"))
        #expect(off.action?.confirmation?.confirmVerb == "Turn On")
        let buffering = style.resolve(Self.entity("media_player.demo_player", "buffering"), entityId: "media_player.demo_player")
        #expect(buffering.action?.verb == "Pause", "no Stop feature: the otherwise action")
        #expect(buffering.indicator == .none, "a state with an action keeps its disc")
        let request = try #require(style.request)
        #expect(request.lockout == .seconds(2) && request.settleTimeout == .seconds(45) && request.onTimeout == .error)
        #expect(request.pendingWords == ["media_pause": "Pausing…"])
        #expect(request.script == "script.demo_player_lifecycle" && request.errorTimer == "timer.demo_player_error")
    }

    @Test func aLibraryWithAnArcOnAStateWithAnActionIsAnIssueAtTheRulesIndicator() {
        let rule: JSONValue = .object(["states": .array([.string("on")]), "class": .string("in-progress"), "active": .bool(true),
                                      "indicator": .string("arc-spinner"),
                                      "action": .object(["verb": .string("Stop"), "icon": .string("stop.fill")])])
        let library: JSONValue = .object(["styles": .array([.object(["id": .string("s"), "name": .string("S"), "domain": .string("switch"),
                                                                       "rules": .array([rule]), "fallback": .object(["class": .string("unknown"), "active": .bool(false)])])])])
        let decoded = ServerUIStateStyles.decodeLibrary(library, at: "/document/stateStyles")
        #expect(decoded.issues == [ServerUICompositionError(.invalidCombination, "/document/stateStyles/styles/0/rules/0/indicator")])
    }

    // MARK: Resolving a tile

    @Test func aTileResolvesItsAuthoredStyleWithItsOverridesApplied() throws {
        let publication = try Self.publication("authored-vacuum")
        let tile = try Self.tile(publication)
        let style = try #require(tile.binding.resolve(in: publication.document.stateStyles))
        #expect(style.id == "tidy-vacuum")
        let cleaning = style.resolve(Self.entity("vacuum.demo_robot", "cleaning"), entityId: "vacuum.demo_robot")
        #expect(cleaning.words == "Vacuuming" && cleaning.indicator == .pulse, "the override beats the rule; the rule's icon stays")
        #expect(cleaning.glyph == "fan")
        let returning = style.resolve(Self.entity("vacuum.demo_robot", "returning"), entityId: "vacuum.demo_robot")
        #expect(returning.glyph == "house" && returning.colour == .lit)
        #expect(returning.indicator == .arcSpinner, "a layer an override leaves alone stays the rule's")
    }

    @Test func anUnknownStyleIdFallsBackToTheTilesBuiltInStyle() throws {
        let publication = try Self.publication("unknown-style-id-falls-back")
        let tile = try Self.tile(publication)
        #expect(tile.binding.styleId == "removed-style")
        let style = try #require(tile.binding.resolve(in: publication.document.stateStyles))
        #expect(style == StateStyle.robot.applying(tile.binding.overrides))
        #expect(style.id == "robot")
    }

    @Test func aDeviceWithoutTheCapabilityKeepsTheBuiltInStyleAlone() throws {
        let publication = try Self.publication("authored-vacuum")
        let tile = try Self.tile(publication)
        let style = try #require(tile.binding.resolve(in: publication.document.stateStyles, capability: false))
        #expect(style == StateStyle.robot, "no authored style and no override reaches a device that lacks the capability")
        let cleaning = style.resolve(Self.entity("vacuum.demo_robot", "cleaning"), entityId: "vacuum.demo_robot")
        #expect(cleaning.words == "Cleaning" && cleaning.indicator == .breathe)
    }

    @Test func aTileWithNoStyleAtAllResolvesToNothingAndNeverRejects() throws {
        let publication = try Self.publication("style-without-base-or-built-in")
        let tile = try Self.tile(publication)
        #expect(tile.binding.builtIn == nil)
        #expect(tile.binding.resolve(in: publication.document.stateStyles) != nil)
        #expect(tile.binding.resolve(in: nil) == nil, "a style id with no library and no built-in style: the tile draws the unknown look")
        #expect(tile.binding.resolve(in: publication.document.stateStyles, capability: false) == nil)
    }

    @Test func aBuiltInOnlyTileNeedsNoLibrary() throws {
        let publication = try Self.publication("built-in-only-tile")
        #expect(publication.document.stateStyles == nil)
        let tile = try Self.tile(publication)
        #expect(tile.binding.resolve(in: nil) == StateStyle.robot)
        #expect(publication.capabilities.contains(serverUIStateStyleCapability))
    }

    // MARK: Overrides

    @Test func anOverrideSplitsAStateOffTheRuleItSharesAndTouchesItAlone() {
        let styled = StateStyle.robot.applying([.init(state: "idle", icon: nil, text: "Resting", indicator: nil, colour: .lit)])
        let idle = styled.resolve(Self.entity("vacuum.demo_x", "idle"), entityId: "vacuum.demo_x")
        let docked = styled.resolve(Self.entity("vacuum.demo_x", "docked"), entityId: "vacuum.demo_x")
        #expect(idle.words == "Resting" && idle.colour == .lit)
        #expect(docked.words == "Docked" && docked.colour == nil)
        #expect(styled.rules.last?.states.isEmpty == true)
    }

    @Test func anIconOverrideReplacesTheGlyphTheDiscDraws() {
        let styled = StateStyle.lock.applying([.init(state: "locked", icon: "key.fill", text: nil, indicator: nil, colour: nil)])
        let locked = styled.resolve(Self.entity("lock.demo_x", "locked"), entityId: "lock.demo_x")
        #expect(locked.glyph == "key.fill" && locked.action?.symbol == "key.fill" && locked.action?.verb == "Unlock")
    }

    @Test func anOverrideOfAStateNoRuleNamesGetsARuleMadeFromTheFallback() {
        let styled = StateStyle.switch.applying([.init(state: "standby", icon: nil, text: "Standing by", indicator: nil, colour: nil)])
        #expect(styled.resolve(Self.entity("switch.demo_x", "standby"), entityId: "switch.demo_x").words == "Standing by")
        #expect(styled.resolve(Self.entity("switch.demo_x", "other"), entityId: "switch.demo_x").stateClass == .unknown)
    }

    @Test func noOverridesLeavesTheStyleUntouched() {
        #expect(StateStyle.alarm.applying([]) == StateStyle.alarm)
    }

    // MARK: Defaults of the colour layer

    @Test func theColourListIsClosed() {
        #expect(StateColour.allCases.map(\.rawValue) == ["unlit", "lit"])
    }

    // MARK: A colour token is cosmetic

    private static func rule(_ states: [String], _ stateClass: String, colour: String? = "lit") -> JSONValue {
        var fields: [String: JSONValue] = ["states": .array(states.map { .string($0) }), "class": .string(stateClass), "active": .bool(false)]
        if let colour { fields["colour"] = .string(colour) }
        return .object(fields)
    }

    private static func library(_ rule: JSONValue) -> JSONValue {
        .object(["styles": .array([.object(["id": .string("s"), "name": .string("S"), "domain": .string("switch"), "rules": .array([rule]),
                                            "fallback": .object(["class": .string("unknown"), "active": .bool(false)])])])])
    }

    @Test(arguments: ["warning", "error", "unknown"])
    func aRuleColourOnAWarningErrorOrUnknownClassIsAnIssueAtColour(stateClass: String) {
        let decoded = ServerUIStateStyles.decodeLibrary(Self.library(Self.rule(["x"], stateClass)), at: "/document/stateStyles")
        #expect(decoded.issues == [ServerUICompositionError(.invalidCombination, "/document/stateStyles/styles/0/rules/0/colour")])
    }

    @Test(arguments: ["resting", "in-progress"])
    func aRuleColourOnARestingOrInProgressClassIsAccepted(stateClass: String) {
        let decoded = ServerUIStateStyles.decodeLibrary(Self.library(Self.rule(["x"], stateClass)), at: "/document/stateStyles")
        #expect(decoded.issues.isEmpty)
    }

    @Test func aFallbackColourOnTheUnknownClassIsAnIssueAtColour() {
        let library: JSONValue = .object(["styles": .array([.object([
            "id": .string("s"), "name": .string("S"), "domain": .string("switch"), "rules": .array([Self.rule(["on"], "resting", colour: nil)]),
            "fallback": .object(["class": .string("unknown"), "active": .bool(false), "colour": .string("unlit")])])])])
        let decoded = ServerUIStateStyles.decodeLibrary(library, at: "/document/stateStyles")
        #expect(decoded.issues == [ServerUICompositionError(.invalidCombination, "/document/stateStyles/styles/0/fallback/colour")])
    }

    @Test(arguments: [("paused", true), ("unavailable", true), ("returning", false), ("cleaning", false)])
    func anOverrideColourFollowsTheClassOfTheStateItNames(state: String, rejected: Bool) throws {
        let publication = try Self.publication("authored-vacuum")
        let library = try #require(publication.document.stateStyles)
        let binding: JSONValue = .object(["entityId": .string("vacuum.demo_robot"), "styleId": .string("tidy-vacuum"),
                                          "overrides": .array([.object(["state": .string(state), "colour": .string("lit")])])])
        let decoded = ServerUIStateStyles.decodeBinding(binding, at: "/b", library: library)
        #expect(decoded.issues == (rejected ? [ServerUICompositionError(.invalidCombination, "/b/overrides/0/colour")] : []))
    }

    @Test func anOverrideColourOnABuiltInErrorStateIsAnIssueAtColour() {
        let binding: JSONValue = .object(["entityId": .string("lock.demo_door"), "builtIn": .string("lock"),
                                          "overrides": .array([.object(["state": .string("jammed"), "colour": .string("unlit")])])])
        #expect(ServerUIStateStyles.decodeBinding(binding, at: "/b", library: nil).issues
            == [ServerUICompositionError(.invalidCombination, "/b/overrides/0/colour")])
    }

    @Test func lockOpeningIsInProgressAndLitAlongsideUnlocking() {
        let lock = StateStyle.lock
        for state in ["unlocking", "opening"] {
            let resolution = lock.resolve(Self.entity("lock.demo_x", state), entityId: "lock.demo_x")
            #expect(resolution.stateClass == .inProgress && resolution.isActive, Comment(rawValue: state))
        }
    }
}
