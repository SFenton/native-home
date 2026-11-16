import Foundation
@testable import HassCore
import Testing

// MARK: - Tile ink and cell fit (`sh.tile-ink@1`)

/// A state tile's `glyphTint`, `discGlyphTint` and `cellFit`, and a state style rule's `fillInk`. The shared corpus runs every case through the
/// compiler (`ServerUIContractCorpusTests`: nine accepts, nineteen refusals); these tests pin what the decoder made of the fields, the capability
/// each needs, and the defaults, which must leave every existing tile as it was.
@Suite(.timeLimit(.minutes(1)))
struct ServerUITileInkTests {
    private static let corpus = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("ContractCorpus", isDirectory: true)

    private static func publication(_ name: String) throws -> ServerUICompositionPublication {
        try ServerUICompositionPublication.decode(Data(contentsOf: corpus.appendingPathComponent("accept/\(name).json")))
    }

    /// The state tiles of the sample page, in order, including the ones inside a grid.
    private static func tiles(_ publication: ServerUICompositionPublication) -> [ServerUICompositionDocument.StateTile] {
        func walk(_ components: [ServerUICompositionDocument.Component]) -> [ServerUICompositionDocument.StateTile] {
            components.flatMap { component -> [ServerUICompositionDocument.StateTile] in
                switch component {
                case .stateTile(let tile): [tile]
                case .grid(let grid): walk(grid.children)
                default: []
                }
            }
        }
        return walk(publication.document.pages[2].surface.components)
    }

    private static let darkPurple = ServerUIRGB(red: 193, green: 140, blue: 238)
    private static let lightPurple = ServerUIRGB(red: 142, green: 109, blue: 172)
    private static let discDark = ServerUIRGB(red: 184, green: 141, blue: 221)

    // MARK: The glyph tint

    @Test func aSingleColourIsTheSameInBothAppearances() throws {
        let tile = try #require(Self.tiles(Self.publication("tile-ink-glyph-tint")).first)
        let tint = try #require(tile.ink.glyphTint)
        #expect(tint.light == Self.lightPurple && tint.dark == Self.lightPurple)
        #expect(tint.packed(isDark: true) == 0x8E6DAC && tint.packed(isDark: false) == 0x8E6DAC)
        #expect(tile.ink.discGlyphTint == nil && tile.ink.cellFit == .fill && tile.ink.isDeclared)
    }

    @Test func aPairKeepsItsTwoMembersAndNeedsTheAppearanceId() throws {
        let publication = try Self.publication("tile-ink-glyph-tint-pair")
        #expect(publication.capabilities.contains("sh.solid-appearance@1") && publication.capabilities.contains("sh.tile-ink@1"))
        let tint = try #require(Self.tiles(publication).first?.ink.glyphTint)
        #expect(tint.light == Self.lightPurple && tint.dark == Self.darkPurple)
        #expect(tint.packed(isDark: false) == 0x8E6DAC && tint.packed(isDark: true) == 0xC18CEE)
        #expect(tint.rgb(isDark: true) == Self.darkPurple)
    }

    @Test func theTwoTintsAreIndependent() throws {
        let tile = try #require(Self.tiles(Self.publication("tile-ink-both-tints")).first)
        #expect(tile.ink.glyphTint?.dark == Self.darkPurple)
        #expect(tile.ink.discGlyphTint?.dark == Self.discDark && tile.ink.discGlyphTint?.light == Self.lightPurple)
        let disc = try #require(Self.tiles(Self.publication("tile-ink-disc-glyph-tint")).first)
        #expect(disc.ink.glyphTint == nil && disc.ink.discGlyphTint?.dark == Self.discDark)
    }

    // MARK: The cell fit

    @Test func theCellFitIsReadPerTileAndFillIsTheDefault() throws {
        let tiles = Self.tiles(try Self.publication("tile-ink-cell-fit-natural"))
        #expect(tiles.map(\.ink.cellFit) == [.natural, .fill])
        #expect(tiles.map(\.ink.keepsNaturalHeight) == [true, false])
        let written = try #require(Self.tiles(Self.publication("tile-ink-cell-fit-fill")).first)
        #expect(written.ink.cellFit == .fill && written.ink.isDeclared)
    }

    @Test func aTileWithNoFieldsHasTheDefaultsAndIsNotDeclared() throws {
        let tile = try #require(Self.tiles(Self.publication("state-style-authored-vacuum")).first)
        #expect(tile.ink == ServerUITileInk())
        #expect(!tile.ink.isDeclared && tile.ink.cellFit == .fill && tile.ink.glyphTint == nil && tile.ink.discGlyphTint == nil)
    }

    // MARK: The ink on a fill

    @Test func aRuleKeepsItsFillInkAndAnAbsentOneIsNil() throws {
        let soft = try #require(Self.publication("tile-ink-fill-ink-soft").document.stateStyles?.entries.first?.style.rules)
        #expect(soft.first?.fillInk == .soft && soft.first?.fill != nil)
        #expect(soft.dropFirst().allSatisfy { $0.fillInk == nil })
        let white = try #require(Self.publication("tile-ink-fill-ink-white").document.stateStyles?.entries.first?.style.rules.first)
        #expect(white.fillInk == .white)
    }

    @Test func theFallbackAndAPairFillTakeAnInkToo() throws {
        let publication = try Self.publication("tile-ink-fill-ink-on-pair-fill")
        let rules = try #require(publication.document.stateStyles?.entries.first?.style.rules)
        #expect(rules.first?.fillInk == .soft && rules.first?.fillDark != nil)
        #expect(rules.last?.fillInk == .soft && rules.last?.states.isEmpty == true)
    }

    @Test func theInkResolvesWithTheFillAndDefaultsToWhite() throws {
        func resolved(_ ink: StateFillInk?) -> StateResolution {
            var rule = StateRule(["on"], .resting, active: true)
            rule.fill = 0x785AA0
            rule.fillInk = ink
            return StateStyle(id: "s", name: "S", domain: "switch", actionId: "a", rules: [rule]).resolve(
                EntityState(entityId: "switch.demo_x", state: "on"), entityId: "switch.demo_x")
        }
        #expect(resolved(nil).fillInk == .white)
        #expect(resolved(.white).fillInk == .white)
        #expect(resolved(.soft).fillInk == .soft)
        #expect(StateFillInk.white.opacity == 1 && StateFillInk.soft.opacity == 0.92)
    }

    @Test func anOverrideKeepsTheInkOfTheRuleItSplitsOff() throws {
        var rule = StateRule(["on", "off"], .resting, active: true)
        rule.fill = 0x785AA0
        rule.fillInk = .soft
        let style = StateStyle(id: "s", name: "S", domain: "switch", actionId: "a", rules: [rule])
        let layered = style.applying([.init(state: "off", icon: nil, text: "Away", indicator: nil, colour: nil)])
        #expect(layered.rules.filter { $0.states == ["off"] }.first?.fillInk == .soft)
    }

    // MARK: The capability

    @Test func eachFieldNeedsTheIdAndOnlyThatId() throws {
        for name in ["glyph-tint", "disc-glyph-tint", "cell-fit-fill", "cell-fit-natural", "fill-ink-soft", "fill-ink-white"] {
            let publication = try Self.publication("tile-ink-" + name)
            #expect(publication.capabilities.contains("sh.tile-ink@1"), "\(name) declares the id")
            let data = try Data(contentsOf: Self.corpus.appendingPathComponent("accept/tile-ink-\(name).json"))
            let text = try #require(String(data: data, encoding: .utf8)).replacingOccurrences(of: "\"sh.tile-ink@1\",", with: "")
            #expect(throws: (any Error).self, "\(name) without the id is refused") { _ = try ServerUICompositionPublication.decode(Data(text.utf8)) }
        }
    }

    @Test func theIdIsShippedOnceAndTheFlowIdsAreListedOnce() {
        #expect(ServerUIIngestedCapabilities.tileInk == ["sh.tile-ink@1"])
        #expect(ServerUIIngestedCapabilities.all.filter { $0 == "sh.tile-ink@1" }.count == 1)
        #expect(ServerUIIngestedCapabilities.all.filter { $0 == "sh.pipeline-operands@1" }.count == 1)
    }
}
