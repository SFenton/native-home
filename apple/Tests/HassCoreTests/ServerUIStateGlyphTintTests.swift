import Foundation
@testable import HassCore
import Testing

// MARK: - Icon colour by state (`sh.state-style-glyph-tint@1`)

/// A state style rule's `glyphTint`. The shared corpus runs every accept and refusal through the compiler
/// (`ServerUIContractCorpusTests`); these tests pin what the decoder made of the field, how it resolves per state, the capability it
/// needs, and that a style which authors none resolves exactly as before.
@Suite(.timeLimit(.minutes(1)))
struct ServerUIStateGlyphTintTests {
    private static let corpus = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("ContractCorpus", isDirectory: true)

    private static func publication(_ name: String) throws -> ServerUICompositionPublication {
        try ServerUICompositionPublication.decode(Data(contentsOf: corpus.appendingPathComponent("accept/state-style-glyph-tint-\(name).json")))
    }

    private static func style(_ name: String) throws -> StateStyle {
        try #require(publication(name).document.stateStyles?.entries.first?.style)
    }

    private static let warm: UInt32 = 0xF2A65A
    private static let cool: UInt32 = 0x78B4F0
    private static let warmLight: UInt32 = 0xB5651D

    private static func resolve(_ style: StateStyle, _ state: String) -> StateResolution {
        style.resolve(EntityState(entityId: "vacuum.demo_robot", state: state), entityId: "vacuum.demo_robot")
    }

    // MARK: Decode

    @Test func eachRuleKeepsItsOwnColourAndTheUnknownRuleHasNone() throws {
        let rules = try Self.style("per-state").rules
        #expect(rules.first { $0.states.contains("docked") }?.glyphTint == Self.warm)
        #expect(rules.first { $0.states == ["cleaning"] }?.glyphTint == Self.cool)
        #expect(rules.first { $0.states.contains("unavailable") }?.glyphTint == nil)
        #expect(rules.compactMap(\.glyphTintDark).isEmpty, "a single colour has no separate dark member")
    }

    @Test func aPairKeepsItsTwoMembers() throws {
        let rule = try #require(Self.style("pair").rules.first)
        #expect(rule.glyphTint == Self.warmLight && rule.glyphTintDark == Self.warm)
    }

    @Test func theFallbackMayCarryTheColour() throws {
        let fallback = try #require(Self.style("fallback").rules.last)
        #expect(fallback.states.isEmpty && fallback.glyphTint == Self.warm)
    }

    // MARK: Fallback order and resolution

    @Test func theResolutionCarriesTheMatchingRulesColour() throws {
        let style = try Self.style("per-state")
        #expect(Self.resolve(style, "docked").glyphTint == Self.warm)
        #expect(Self.resolve(style, "idle").glyphTint == Self.warm)
        #expect(Self.resolve(style, "cleaning").glyphTint == Self.cool)
    }

    @Test func aStateTheRulesDoNotListTakesTheFallbacksColourOrNone() throws {
        #expect(Self.resolve(try Self.style("fallback"), "returning").glyphTint == Self.warm)
        #expect(Self.resolve(try Self.style("per-state"), "returning").glyphTint == nil, "a fallback with no colour leaves the tile's own")
    }

    @Test func anUnavailableStateNeverCarriesAColour() throws {
        for name in ["per-state", "pair", "fallback"] {
            let style = try Self.style(name)
            #expect(Self.resolve(style, "unavailable").glyphTint == nil, Comment(rawValue: name))
            #expect(Self.resolve(style, "unknown").glyphTint == nil, Comment(rawValue: name))
        }
    }

    @Test func aPairResolvesBothMembers() throws {
        let resolved = Self.resolve(try Self.style("pair"), "docked")
        #expect(resolved.glyphTint == Self.warmLight && resolved.glyphTintDark == Self.warm)
    }

    @Test func aStyleThatAuthorsNoColourResolvesAsBefore() throws {
        let style = try Self.style("absent-needs-no-capability")
        let resolved = Self.resolve(style, "docked")
        #expect(resolved.glyphTint == nil && resolved.glyphTintDark == nil)
        #expect(!(try #require(Self.publication("absent-needs-no-capability").document.stateStyles)).usesGlyphTint)
    }

    @Test func theColourDoesNotChangeAnyOtherLayer() throws {
        let bare = StateRule(["on"], .resting, active: true, glyph: "fan", words: "Running")
        var tinted = bare
        tinted.glyphTint = Self.warm
        let domain = "switch", entity = "switch.demo_x"
        func resolved(_ rule: StateRule) -> StateResolution {
            StateStyle(id: "s", name: "S", domain: domain, actionId: "a", rules: [rule]).resolve(EntityState(entityId: entity, state: "on"), entityId: entity)
        }
        var left = resolved(tinted), right = resolved(bare)
        left.glyphTint = nil
        right.glyphTint = nil
        #expect(left == right, "only the tint differs")
    }

    @Test func anOverrideKeepsTheColourOfTheRuleItSplitsOff() {
        var rule = StateRule(["on", "off"], .resting, active: true)
        rule.glyphTint = Self.warm
        rule.glyphTintDark = Self.cool
        let style = StateStyle(id: "s", name: "S", domain: "switch", actionId: "a", rules: [rule])
        let layered = style.applying([.init(state: "off", icon: nil, text: "Away", indicator: nil, colour: nil)])
        let split = layered.rules.first { $0.states == ["off"] }
        #expect(split?.glyphTint == Self.warm && split?.glyphTintDark == Self.cool)
    }

    // MARK: Capability

    @Test func theFieldNeedsTheIdAndOnlyWhenWritten() throws {
        for name in ["per-state", "pair", "fallback", "with-static-tint"] {
            #expect(try Self.publication(name).capabilities.contains("sh.state-style-glyph-tint@1"), "\(name) declares the id")
        }
        #expect(try !Self.publication("absent-needs-no-capability").capabilities.contains("sh.state-style-glyph-tint@1"))
    }

    @Test func theIdIsListedOnce() {
        #expect(ServerUIIngestedCapabilities.styleGlyphTint == ["sh.state-style-glyph-tint@1"])
        #expect(ServerUIIngestedCapabilities.all.filter { $0 == "sh.state-style-glyph-tint@1" }.count == 1)
    }

    @Test func aStaticTileTintBesideARuleTintBothDecode() throws {
        let publication = try Self.publication("with-static-tint")
        let rules = try #require(publication.document.stateStyles?.entries.first?.style.rules)
        #expect(rules.first?.glyphTint == Self.warm)
        #expect(rules.first { $0.states == ["cleaning"] }?.glyphTint == nil, "the in-progress state falls to the tile's static tint")
    }
}
