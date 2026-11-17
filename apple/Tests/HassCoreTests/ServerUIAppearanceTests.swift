import Foundation
@testable import HassCore
import Testing

// MARK: - The words text case and the light and dark colour pair

/// The `words` text case (`sh.text-case-words@1`) and the colour that differs by appearance (`sh.solid-appearance@1`).
/// The shared corpus runs every case through the compiler (`ServerUIContractCorpusTests`) and the evaluator
/// (`ServerUIExpressionCorpusTests`); these tests pin the rule and what the decoder made of the pair.
@Suite(.timeLimit(.minutes(1)))
struct ServerUIAppearanceTests {
    private static let corpus = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("ContractCorpus", isDirectory: true)

    private static func publication(_ name: String) throws -> ServerUICompositionPublication {
        try ServerUICompositionPublication.decode(Data(contentsOf: corpus.appendingPathComponent("accept/\(name).json")))
    }

    private static func json(_ text: String) throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)) }

    private static let purple = ServerUIRGB(red: 156, green: 109, blue: 195)
    private static let lilac = ServerUIRGB(red: 200, green: 140, blue: 250)

    // MARK: Words

    @Test func wordsSplitsAtUnderscoresAndSpacesAndCapitalizesAnAsciiFirstLetter() {
        #expect(ServerUITextCase.words.apply(to: "Wheel stuck") == "Wheel Stuck")
        #expect(ServerUITextCase.words.apply(to: "heat_cool") == "Heat Cool")
        #expect(ServerUITextCase.words.apply(to: "wheel_stuck and jammed") == "Wheel Stuck And Jammed")
        #expect(ServerUITextCase.words.apply(to: "AUTO mode") == "AUTO Mode")
        #expect(ServerUITextCase.words.apply(to: "3rd floor") == "3rd Floor")
    }

    @Test func wordsKeepsEmptyPartsAndJoinsWithOneSpace() {
        #expect(ServerUITextCase.words.apply(to: "a  b") == "A  B")
        #expect(ServerUITextCase.words.apply(to: "_x") == " X")
        #expect(ServerUITextCase.words.apply(to: "x ") == "X ")
        #expect(ServerUITextCase.words.apply(to: "a__b") == "A  B")
        #expect(ServerUITextCase.words.apply(to: "").isEmpty)
    }

    @Test func wordsWorksOnScalarsSoANonAsciiLetterAndOtherWhitespaceAreLeftAlone() {
        #expect(ServerUITextCase.words.apply(to: "élan vital") == "élan Vital")
        #expect(ServerUITextCase.words.apply(to: "école_été") == "école été")
        // A tab and a newline stay inside their word: only `_` and U+0020 separate.
        #expect(ServerUITextCase.words.apply(to: "a\tb") == "A\tb")
        #expect(ServerUITextCase.words.apply(to: "a\nb c") == "A\nb C")
        // A combining mark after the first letter does not turn it into a different scalar.
        #expect(ServerUITextCase.words.apply(to: "e\u{301}x y") == "E\u{301}x Y")
    }

    @Test func wordsAndTitleDifferOnlyInTheSeparators() {
        #expect(ServerUITextCase.title.apply(to: "heat cool") == "Heat cool")
        #expect(ServerUITextCase.words.apply(to: "heat cool") == "Heat Cool")
        #expect(ServerUITextCase.title.apply(to: "heat_cool") == ServerUITextCase.words.apply(to: "heat_cool"))
    }

    @Test func wordsNeedsItsOwnIdAndTitleKeepsPipelineOperands() throws {
        func parse(_ letterCase: String) throws -> ServerUIExpressionParser {
            var parser = ServerUIExpressionParser()
            let raw = #"{"type":"format","pattern":"{t}","args":{"t":{"type":"literal","value":"x"}},"formats":{"t":{"text":{"case":"\#(letterCase)"}}}}"#
            _ = parser.operand(try Self.json(raw), at: "")
            return parser
        }
        let words = try parse("words")
        #expect(words.issues.isEmpty && words.needs == ["text-case-words"])
        let title = try parse("title")
        #expect(title.issues.isEmpty && title.needs == ["pipeline-operands"])
        let upper = try parse("upper")
        #expect(upper.issues.map { "\($0.code.rawValue) \($0.pointer)" } == ["unknown_variant /formats/t"])
    }

    @Test func wordsEvaluatesAFormatHoleAndLeavesAnUnavailableArgumentUnavailable() {
        let operand = ServerUIOperand.format(pattern: "Issue: {m}", args: ["m": .literal(.string("wheel_stuck"))], formats: ["m": .text(.words)])
        let gap = ServerUIOperand.format(pattern: "{m}", args: ["m": .literal(.null)], formats: ["m": .text(.words)])
        struct Empty: ServerUIReading {
            func read(sourceId: String, path: [String]) -> ServerUIReadResult { .unavailable }
            var viewer: ServerUIViewer? { nil }
            func viewerPersonState() -> ServerUIReadResult { .unavailable }
        }
        #expect(operand.evaluate(Empty()) == .value(.string("Issue: Wheel Stuck")))
        #expect(gap.evaluate(Empty()) == .unavailable)
    }

    // MARK: The pair

    @Test func aPairGivesItsMemberForEachAppearance() {
        let pair = ServerUICompositionDocument.TileFill.solidAppearance(light: Self.purple, dark: Self.lilac)
        #expect(pair.rgb(isDark: false) == Self.purple && pair.rgb(isDark: true) == Self.lilac)
        #expect(pair.appearances?.light == Self.purple && pair.appearances?.dark == Self.lilac)
        let one = ServerUICompositionDocument.TileFill.solidRGB(red: 1, green: 2, blue: 3)
        #expect(one.rgb(isDark: false) == one.rgb(isDark: true) && one.rgb(isDark: true) == ServerUIRGB(red: 1, green: 2, blue: 3))
        #expect(ServerUICompositionDocument.TileFill.standard.appearances == nil)
    }

    @Test func theRuleDecoderReadsAPairInASlot() throws {
        var decoder = ServerUIRuleDecoder()
        let pair = try Self.json(#"{"type":"solid-appearance","light":{"type":"solid-rgb","red":156,"green":109,"blue":195},"dark":{"type":"solid-rgb","red":200,"green":140,"blue":250}}"#)
        let result = decoder.fill(pair, at: "/glyph")
        let decoded = try #require(result)
        #expect(decoded.0 == .solidAppearance(light: Self.purple, dark: Self.lilac) && decoded.1 == nil)
        #expect(decoder.issues.isEmpty && decoder.needs.isEmpty)
        // A member that is not a `solid-rgb` colour decodes to nothing; the shape check refuses it first in a real document.
        let broken = try Self.json(#"{"type":"solid-appearance","light":{"type":"standard"},"dark":{"type":"solid-rgb","red":1,"green":2,"blue":3}}"#)
        let refused = decoder.fill(broken, at: "/glyph")
        #expect(refused == nil)
    }

    @Test func aGlyphPairComesThroughTheCompilerAsAnExactFill() throws {
        let publication = try Self.publication("appearance-glyph")
        #expect(publication.capabilities.contains("sh.solid-appearance@1"))
        let chip = try #require(publication.document.pages[2].surface.components.compactMap { component -> ServerUICompositionDocument.StatusChip? in
            if case .statusChip(let chip) = component { return chip }
            return nil
        }.first)
        let glyph = try #require(chip.states.first?.appearance.glyph)
        #expect(glyph == .solidAppearance(light: Self.purple, dark: Self.lilac))
        #expect(chip.states.first?.appearance.fill == .standard)
    }

    @Test func aPairBesideABoundColourIsOnlyItsFallbackAndAConditionCaseHoldsOne() throws {
        func glyph(_ name: String) throws -> (value: ServerUICompositionDocument.TileFill?, rule: ServerUIDynamicLook<ServerUICompositionDocument.TileFill>?) {
            let publication = try Self.publication(name)
            let chip = try #require(publication.document.pages[2].surface.components.compactMap { component -> ServerUICompositionDocument.StatusChip? in
                if case .statusChip(let chip) = component { return chip }
                return nil
            }.first)
            let appearance = try #require(chip.states.first?.appearance)
            return (appearance.glyph, appearance.glyphRule)
        }
        let bound = try glyph("appearance-bound-color-fallback")
        #expect(bound.value == .solidAppearance(light: Self.purple, dark: Self.lilac))
        guard case .bound? = bound.rule else { Issue.record("the glyph follows the entity's colour"); return }
        let conditional = try glyph("appearance-conditional")
        #expect(conditional.value != nil)
        guard case .conditional(let cases)? = conditional.rule else { Issue.record("the glyph follows a rule"); return }
        #expect(cases.first?.then == .solidAppearance(light: Self.purple, dark: Self.lilac))
    }

    @Test func aRoomCardColourKeepsItsDarkMemberAndAnEqualPairKeepsNone() throws {
        let publication = try Self.publication("appearance-room-state-colors")
        let definition = try #require(publication.document.pages[2].surface.components.compactMap { component -> ServerUICompositionDocument.RoomCard? in
            if case .roomCard(let card) = component { return card }
            return nil
        }.first)
        let color = try #require(ServerUIRooms.card(definition, entityId: "light.demo_x").stateColors["on"])
        #expect(color.red == 1 && color.green == 204.0 / 255 && color.blue == 0)
        #expect(color.dark == RoomColor.Dark(255, 214, 10))
        let same = try Self.publication("appearance-identical-colors")
        #expect(same.capabilities.contains("sh.solid-appearance@1"))
    }

    @Test func aStateStyleRuleKeepsBothMembersOfItsFillPair() throws {
        let publication = try Self.publication("appearance-state-style-fill")
        #expect(publication.capabilities.contains("sh.state-style-fills@1") && publication.capabilities.contains("sh.solid-appearance@1"))
        let rule = try #require(publication.document.stateStyles?.entries.first?.style.rules.first)
        #expect(rule.fill == 0x9C6DC3 && rule.fillDark == 0xC88CFA)
        let resolved = StateStyle(id: "s", name: "S", domain: "switch", actionId: "a", rules: [rule]).resolve(
            EntityState(entityId: "switch.demo_x", state: rule.states.first ?? "on"), entityId: "switch.demo_x")
        #expect(resolved.fill == 0x9C6DC3 && resolved.fillDark == 0xC88CFA)
    }

    @Test func aDocumentThatHoldsAPairMustDeclareItsCapability() throws {
        let data = try Data(contentsOf: Self.corpus.appendingPathComponent("accept/appearance-fill.json"))
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(throws: (any Error).self) {
            _ = try ServerUICompositionPublication.decode(Data(text.replacingOccurrences(of: "\"sh.solid-appearance@1\",", with: "").utf8))
        }
    }

    @Test func theScanFindsAPairAnywhereButInsideALiteral() throws {
        #expect(ServerUIAppearanceScan.holdsPair(try Self.json(#"{"a":[{"b":{"type":"solid-appearance"}}]}"#)))
        #expect(!ServerUIAppearanceScan.holdsPair(try Self.json(#"{"a":[{"b":{"type":"solid-rgb"}}]}"#)))
        #expect(!ServerUIAppearanceScan.holdsPair(try Self.json(#"{"type":"literal","value":{"type":"solid-appearance"}}"#)))
        #expect(ServerUIAppearanceScan.holdsPair(try Self.json(#"{"type":"literal","x":1,"y":{"type":"solid-appearance"}}"#)) == false)
    }

    @Test func theIdsAreShippedOnceAndTheIdsOfTheFlowLaneAreListed() {
        #expect(ServerUIIngestedCapabilities.appearance == ["sh.text-case-words@1", "sh.solid-appearance@1"])
        #expect(Set(ServerUIIngestedCapabilities.all).count == ServerUIIngestedCapabilities.all.count)
        #expect(ServerUIIngestedCapabilities.all.filter { $0 == "sh.pipeline-operands@1" }.count == 1)
    }
}
